from __future__ import annotations

from datetime import datetime, timezone
from typing import Any


JOB_RUNS_TABLE = "job_runs"


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def reap_orphaned_job_runs(supabase, *, older_than_iso: str, stuck_hours: float = 6.0) -> int:
    """Mark job_runs stuck in 'running' as 'failed'.

    Two cases are reaped:
      1. rows started before ``older_than_iso`` (i.e. before this process started) — they
         belong to a previous container instance that was replaced, so they can never be
         finished (no writer is left).
      2. rows older than ``stuck_hours`` regardless — covers a job that crashed without a
         restart.
    Returns the count reaped. Best-effort; never raises.
    """
    from datetime import timedelta

    reaped = 0
    try:
        cutoff_stuck = (
            datetime.now(timezone.utc) - timedelta(hours=stuck_hours)
        ).isoformat()
        rows = (
            supabase.table(JOB_RUNS_TABLE)
            .select("id, started_at")
            .eq("status", "running")
            .execute()
            .data
            or []
        )
        stale_ids = [
            r["id"]
            for r in rows
            if r.get("id")
            and (
                str(r.get("started_at") or "") < older_than_iso
                or str(r.get("started_at") or "") < cutoff_stuck
            )
        ]
        for rid in stale_ids:
            supabase.table(JOB_RUNS_TABLE).update(
                {
                    "status": "failed",
                    "completed_at": utcnow_iso(),
                    "error_json": {"reason": "orphaned: reaped on scheduler startup"},
                }
            ).eq("id", rid).execute()
            reaped += 1
    except Exception:
        return reaped
    return reaped


def start_job_run(
    supabase,
    *,
    job_id: str,
    tier: str,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload = {
        "job_id": job_id,
        "tier": tier,
        "status": "running",
        "started_at": utcnow_iso(),
        "metadata": metadata or {},
    }
    result = supabase.table(JOB_RUNS_TABLE).insert(payload).execute()
    rows = result.data or []
    if rows:
        return rows[0]
    return payload


def finish_job_run(
    supabase,
    run_id: str | None,
    *,
    status: str,
    items_processed: int = 0,
    items_skipped: int = 0,
    items_failed: int = 0,
    error_json: dict[str, Any] | None = None,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload = {
        "status": status,
        "completed_at": utcnow_iso(),
        "items_processed": items_processed,
        "items_skipped": items_skipped,
        "items_failed": items_failed,
        "error_json": error_json,
    }
    if metadata is not None:
        payload["metadata"] = metadata
    if not run_id:
        return payload
    result = (
        supabase.table(JOB_RUNS_TABLE)
        .update(payload)
        .eq("id", run_id)
        .execute()
    )
    rows = result.data or []
    if rows:
        return rows[0]
    return {**payload, "id": run_id}
