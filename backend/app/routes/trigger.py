from __future__ import annotations
from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends, Request, HTTPException
import traceback
from pydantic import BaseModel
from ..services.supabase import get_supabase
from ..pipeline.scheduler import enqueue_analysis_run

router = APIRouter()
MANUAL_ANALYSIS_DAILY_LIMIT = 3
MANUAL_ANALYSIS_COOLDOWN = timedelta(minutes=15)


def require_user_id(request: Request) -> str:
    return request.state.user_id


class TriggerAnalysisRequest(BaseModel):
    position_id: str | None = None


def _parse_iso_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except ValueError:
        return None


@router.post("")
async def trigger_analysis(
    payload: TriggerAnalysisRequest | None = None,
    user_id: str = Depends(require_user_id),
):
    supabase = get_supabase()
    now = datetime.now(timezone.utc)
    cutoff = (now - timedelta(hours=24)).isoformat()
    recent_manual_runs = (
        supabase.table("analysis_runs")
        .select("id, started_at")
        .eq("user_id", user_id)
        .eq("triggered_by", "manual")
        .gte("started_at", cutoff)
        .order("started_at", desc=True)
        .limit(MANUAL_ANALYSIS_DAILY_LIMIT)
        .execute()
        .data
        or []
    )
    if recent_manual_runs:
        latest_started_at = _parse_iso_datetime(recent_manual_runs[0].get("started_at"))
        if latest_started_at and now - latest_started_at < MANUAL_ANALYSIS_COOLDOWN:
            raise HTTPException(
                429,
                "Manual analysis is cooling down. Please try again in a few minutes.",
            )

    if len(recent_manual_runs) >= MANUAL_ANALYSIS_DAILY_LIMIT:
        raise HTTPException(
            429,
            "Manual analysis is limited to 3 requests per 24 hours.",
        )

    try:
        result = await enqueue_analysis_run(
            user_id,
            "manual",
            target_position_id=payload.position_id if payload else None,
        )
        prefs_payload = {
            "user_id": user_id,
            "last_analysis_request_at": now.isoformat(),
        }
        existing = (
            supabase.table("user_preferences")
            .select("id")
            .eq("user_id", user_id)
            .limit(1)
            .execute()
            .data
        )
        if existing:
            supabase.table("user_preferences").update(prefs_payload).eq(
                "user_id", user_id
            ).execute()
        else:
            supabase.table("user_preferences").insert(prefs_payload).execute()
        result["progress"] = 0
        result["digest_ready"] = False
        result["events_analyzed"] = 0
        result["error"] = None
        return result
    except Exception as e:
        print(f"Trigger analysis error: {e}")
        traceback.print_exc()
        raise HTTPException(500, "Analysis failed")
