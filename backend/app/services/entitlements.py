from __future__ import annotations

from datetime import datetime, timezone
from typing import Any


def _parse_datetime(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def effective_tier_from_preferences(
    preferences: dict[str, Any] | None,
    *,
    now: datetime | None = None,
) -> str:
    """Return the access tier from a server-verified StoreKit entitlement."""
    prefs = preferences or {}
    stored_tier = str(prefs.get("subscription_tier") or "free").lower()
    if stored_tier == "admin":
        return "admin"
    if stored_tier != "pro":
        return "free"

    expires_at = _parse_datetime(prefs.get("subscription_expires_at"))
    current_time = now or datetime.now(timezone.utc)
    if expires_at is None or expires_at <= current_time:
        return "free"

    if prefs.get("subscription_offer_type") == 1:
        return "trial"
    return "pro"


def get_effective_tier(supabase, user_id: str) -> str:
    rows = (
        supabase.table("user_preferences")
        .select(
            "subscription_tier,subscription_expires_at,subscription_offer_type"
        )
        .eq("user_id", user_id)
        .limit(1)
        .execute()
        .data
        or []
    )
    return effective_tier_from_preferences(rows[0] if rows else None)
