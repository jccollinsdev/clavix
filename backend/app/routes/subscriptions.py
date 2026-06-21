from __future__ import annotations

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel

from ..services.app_store import (
    AppStoreConfigurationError,
    AppStoreRetryableVerificationError,
    AppStoreVerificationError,
    VerifiedSubscription,
    normalized_app_account_token,
    verify_notification,
    verify_notification_renewal_info,
    verify_notification_transaction,
    verify_signed_transaction,
)
from ..services.supabase import get_supabase

logger = logging.getLogger(__name__)
router = APIRouter()

_ACTIVE_NOTIFICATION_STATUSES = {1, 4}
_FORCE_INACTIVE_NOTIFICATIONS = {
    "EXPIRED",
    "GRACE_PERIOD_EXPIRED",
    "REFUND",
    "REVOKE",
}


class SubscriptionSyncRequest(BaseModel):
    signed_transaction: str


class AppStoreNotificationRequest(BaseModel):
    signedPayload: str


def _existing_subscription(supabase, original_transaction_id: str) -> dict | None:
    rows = (
        supabase.table("app_store_subscriptions")
        .select("*")
        .eq("original_transaction_id", original_transaction_id)
        .limit(1)
        .execute()
        .data
        or []
    )
    return rows[0] if rows else None


def _resolve_user_id(
    supabase,
    subscription: VerifiedSubscription,
    *,
    authenticated_user_id: str | None,
) -> str | None:
    existing = _existing_subscription(
        supabase, subscription.original_transaction_id
    )
    existing_user_id = str(existing.get("user_id")) if existing else None
    app_account_user_id = normalized_app_account_token(
        subscription.app_account_token
    )

    if authenticated_user_id:
        expected_user_id = normalized_app_account_token(authenticated_user_id)
        if expected_user_id is None:
            raise HTTPException(401, "Authenticated user ID is invalid")
        if app_account_user_id and app_account_user_id != expected_user_id:
            raise HTTPException(403, "Purchase belongs to a different app account")
        if existing_user_id and existing_user_id != expected_user_id:
            raise HTTPException(409, "Purchase is already linked to another account")
        if app_account_user_id is None and existing_user_id != expected_user_id:
            raise HTTPException(
                400,
                "Purchase is missing its app account binding; contact support",
            )
        return expected_user_id

    if existing_user_id and app_account_user_id and existing_user_id != app_account_user_id:
        logger.error(
            "app_store_notification_account_mismatch original_transaction_id=%s",
            subscription.original_transaction_id,
        )
        return None
    return existing_user_id or app_account_user_id


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value else None


def _parse_iso(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def _persist_entitlement(
    supabase,
    *,
    user_id: str,
    subscription: VerifiedSubscription,
    is_active: bool,
    effective_expires_at: datetime,
    event_at: datetime,
    notification_status: int | None = None,
) -> bool:
    now_iso = datetime.now(timezone.utc).isoformat()
    existing_subscription = _existing_subscription(
        supabase, subscription.original_transaction_id
    )
    existing_event_at = _parse_iso(
        str(existing_subscription.get("last_event_at"))
        if existing_subscription and existing_subscription.get("last_event_at")
        else None
    )
    if existing_event_at and event_at < existing_event_at:
        return False

    subscription_payload = {
        "user_id": user_id,
        "original_transaction_id": subscription.original_transaction_id,
        "latest_transaction_id": subscription.transaction_id,
        "product_id": subscription.product_id,
        "environment": subscription.environment,
        "app_account_token": subscription.app_account_token,
        "purchase_date": _iso(subscription.purchase_date),
        "transaction_signed_at": _iso(subscription.signed_at),
        "last_event_at": _iso(event_at),
        "expires_at": _iso(effective_expires_at),
        "revoked_at": _iso(subscription.revoked_at),
        "offer_type": subscription.offer_type,
        "is_active": is_active,
        "notification_status": notification_status,
        "updated_at": now_iso,
    }
    supabase.table("app_store_subscriptions").upsert(
        subscription_payload,
        on_conflict="original_transaction_id",
    ).execute()

    preferences_payload = {
        "subscription_tier": "pro" if is_active else "free",
        "subscription_expires_at": _iso(effective_expires_at),
        "subscription_offer_type": subscription.offer_type,
        "subscription_original_transaction_id": subscription.original_transaction_id,
        "subscription_environment": subscription.environment,
        "trial_started_at": None,
        "trial_ends_at": None,
    }
    existing_preferences = (
        supabase.table("user_preferences")
        .select("id,subscription_tier")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
        .data
        or []
    )
    if existing_preferences:
        if str(existing_preferences[0].get("subscription_tier") or "").lower() == "admin":
            preferences_payload["subscription_tier"] = "admin"
        supabase.table("user_preferences").update(preferences_payload).eq(
            "user_id", user_id
        ).execute()
    else:
        supabase.table("user_preferences").insert(
            {"user_id": user_id, **preferences_payload}
        ).execute()
    return True


def _verify_or_http_error(signed_transaction: str) -> VerifiedSubscription:
    try:
        return verify_signed_transaction(signed_transaction)
    except AppStoreVerificationError as exc:
        raise HTTPException(400, str(exc)) from exc
    except AppStoreConfigurationError as exc:
        logger.error("app_store_configuration_error error=%s", exc)
        raise HTTPException(503, "App Store verification is not configured") from exc
    except AppStoreRetryableVerificationError as exc:
        raise HTTPException(503, str(exc)) from exc


@router.post("/sync")
async def sync_subscription(payload: SubscriptionSyncRequest, request: Request):
    user_id = request.state.user_id
    subscription = _verify_or_http_error(payload.signed_transaction)
    supabase = get_supabase()
    resolved_user_id = _resolve_user_id(
        supabase,
        subscription,
        authenticated_user_id=user_id,
    )
    assert resolved_user_id is not None
    _persist_entitlement(
        supabase,
        user_id=resolved_user_id,
        subscription=subscription,
        is_active=subscription.is_active,
        effective_expires_at=subscription.expires_at,
        event_at=subscription.signed_at,
    )
    effective_tier = (
        "trial"
        if subscription.is_active and subscription.offer_type == 1
        else "pro"
        if subscription.is_active
        else "free"
    )
    return {
        "status": "ok",
        "effective_tier": effective_tier,
        "expires_at": subscription.expires_at.isoformat(),
        "environment": subscription.environment,
    }


@router.post("/app-store-notifications", include_in_schema=False)
async def app_store_notifications(
    payload: AppStoreNotificationRequest,
    response: Response,
):
    try:
        notification = verify_notification(payload.signedPayload)
    except AppStoreVerificationError as exc:
        raise HTTPException(400, str(exc)) from exc
    except AppStoreConfigurationError as exc:
        logger.error("app_store_notification_configuration_error error=%s", exc)
        raise HTTPException(503, "App Store verification is not configured") from exc
    except AppStoreRetryableVerificationError as exc:
        raise HTTPException(503, str(exc)) from exc

    notification_uuid = notification.notificationUUID
    if not notification_uuid:
        raise HTTPException(400, "App Store notification UUID is missing")

    supabase = get_supabase()
    duplicate = (
        supabase.table("app_store_notifications")
        .select("notification_uuid")
        .eq("notification_uuid", notification_uuid)
        .limit(1)
        .execute()
        .data
        or []
    )
    if duplicate:
        response.status_code = 200
        return {"status": "duplicate"}

    data = notification.data
    raw_notification_type = notification.rawNotificationType
    raw_subtype = notification.rawSubtype
    if not data or not data.signedTransactionInfo:
        supabase.table("app_store_notifications").insert(
            {
                "notification_uuid": notification_uuid,
                "notification_type": raw_notification_type,
                "subtype": raw_subtype,
                "environment": data.rawEnvironment if data else None,
            }
        ).execute()
        return {"status": "ok"}

    subscription = verify_notification_transaction(data.signedTransactionInfo)
    notification_signed_at = (
        datetime.fromtimestamp(notification.signedDate / 1000, tz=timezone.utc)
        if notification.signedDate is not None
        else subscription.signed_at
    )
    grace_period_expires_at = verify_notification_renewal_info(
        data.signedRenewalInfo
    )
    effective_expires_at = max(
        value
        for value in (subscription.expires_at, grace_period_expires_at)
        if value is not None
    )
    status = data.rawStatus
    is_active = (
        subscription.revoked_at is None
        and (
            status in _ACTIVE_NOTIFICATION_STATUSES
            if status is not None
            else effective_expires_at > datetime.now(timezone.utc)
        )
    )
    if raw_notification_type in _FORCE_INACTIVE_NOTIFICATIONS:
        is_active = False

    user_id = _resolve_user_id(
        supabase,
        subscription,
        authenticated_user_id=None,
    )
    if user_id:
        _persist_entitlement(
            supabase,
            user_id=user_id,
            subscription=subscription,
            is_active=is_active,
            effective_expires_at=effective_expires_at,
            event_at=notification_signed_at,
            notification_status=status,
        )
    else:
        logger.warning(
            "app_store_notification_unmatched notification_uuid=%s original_transaction_id=%s",
            notification_uuid,
            subscription.original_transaction_id,
        )

    supabase.table("app_store_notifications").insert(
        {
            "notification_uuid": notification_uuid,
            "user_id": user_id,
            "notification_type": raw_notification_type,
            "subtype": raw_subtype,
            "environment": subscription.environment,
            "original_transaction_id": subscription.original_transaction_id,
        }
    ).execute()
    return {"status": "ok"}
