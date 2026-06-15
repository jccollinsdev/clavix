from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from ..services.supabase import get_supabase
from ..services.ticker_cache_service import (
    get_default_watchlist_detail,
    get_or_create_default_watchlist,
    require_supported_ticker,
)

router = APIRouter()


class WatchlistItemCreate(BaseModel):
    ticker: str


def get_user_id(request: Request) -> str:
    return request.state.user_id


@router.get("")
async def get_watchlists(user_id: str = Depends(get_user_id)):
    supabase = get_supabase()
    watchlist = get_default_watchlist_detail(supabase, user_id)
    return {"watchlists": [watchlist], "message": "ok"}


FREE_TIER_WATCHLIST_LIMIT = 5


def _get_subscription_tier(supabase, user_id: str) -> str:
    """Return effective tier, honouring the 14-day trial window."""
    from datetime import datetime, timezone

    row = (
        supabase.table("user_preferences")
        .select("subscription_tier, trial_ends_at")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
        .data
    )
    if not row:
        return "free"
    prefs = row[0]
    tier = (prefs.get("subscription_tier") or "free").lower()
    if tier in ("pro", "admin"):
        return tier
    trial_ends_raw = prefs.get("trial_ends_at")
    if trial_ends_raw:
        try:
            trial_ends = datetime.fromisoformat(
                str(trial_ends_raw).replace("Z", "+00:00")
            )
            if trial_ends.tzinfo is None:
                trial_ends = trial_ends.replace(tzinfo=timezone.utc)
            if datetime.now(timezone.utc) < trial_ends:
                return "trial"
        except (ValueError, TypeError):
            pass
    return "free"


@router.post("/default/items")
async def add_to_default_watchlist(
    payload: WatchlistItemCreate, user_id: str = Depends(get_user_id)
):
    supabase = get_supabase()
    supported = require_supported_ticker(supabase, payload.ticker)
    watchlist = get_or_create_default_watchlist(supabase, user_id)

    existing = (
        supabase.table("watchlist_items")
        .select("id")
        .eq("watchlist_id", watchlist["id"])
        .eq("ticker", supported["ticker"])
        .limit(1)
        .execute()
        .data
    )
    if existing:
        return get_default_watchlist_detail(supabase, user_id)

    tier = _get_subscription_tier(supabase, user_id)
    if tier == "free":
        current_count = (
            supabase.table("watchlist_items")
            .select("id", count="exact")
            .eq("watchlist_id", watchlist["id"])
            .execute()
            .count
        ) or 0
        if current_count >= FREE_TIER_WATCHLIST_LIMIT:
            raise HTTPException(
                status_code=403,
                detail={
                    "code": "watchlist_limit_reached",
                    "limit": FREE_TIER_WATCHLIST_LIMIT,
                    "message": f"Free plan supports up to {FREE_TIER_WATCHLIST_LIMIT} watchlist items. Upgrade to Clavix Pro for unlimited.",
                },
            )

    supabase.table("watchlist_items").insert(
        {"watchlist_id": watchlist["id"], "ticker": supported["ticker"]}
    ).execute()

    return get_default_watchlist_detail(supabase, user_id)


@router.delete("/default/items/{ticker}")
async def remove_from_default_watchlist(
    ticker: str, user_id: str = Depends(get_user_id)
):
    supabase = get_supabase()
    watchlist = get_or_create_default_watchlist(supabase, user_id)
    result = (
        supabase.table("watchlist_items")
        .delete()
        .eq("watchlist_id", watchlist["id"])
        .eq("ticker", ticker.upper())
        .execute()
    )
    if result.data is None:
        raise HTTPException(404, "Watchlist item not found")
    return get_default_watchlist_detail(supabase, user_id)
