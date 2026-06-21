from __future__ import annotations

import base64
import json
import logging
import ssl
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any
from uuid import UUID

from appstoreserverlibrary.models.Environment import Environment
from appstoreserverlibrary.signed_data_verifier import (
    SignedDataVerifier,
    VerificationException,
    VerificationStatus,
)

from ..config import get_settings

logger = logging.getLogger(__name__)

MAX_SIGNED_PAYLOAD_BYTES = 64_000
AUTO_RENEWABLE_SUBSCRIPTION = "Auto-Renewable Subscription"


class AppStoreVerificationError(ValueError):
    pass


class AppStoreConfigurationError(RuntimeError):
    pass


class AppStoreRetryableVerificationError(RuntimeError):
    pass


@dataclass(frozen=True)
class VerifiedSubscription:
    original_transaction_id: str
    transaction_id: str
    product_id: str
    environment: str
    app_account_token: str | None
    purchase_date: datetime | None
    signed_at: datetime
    expires_at: datetime
    revoked_at: datetime | None
    offer_type: int | None
    is_active: bool


def _milliseconds_to_datetime(value: int | None) -> datetime | None:
    if value is None:
        return None
    return datetime.fromtimestamp(value / 1000, tz=timezone.utc)


def _decode_unverified_payload(signed_payload: str) -> dict[str, Any]:
    if not signed_payload or len(signed_payload.encode("utf-8")) > MAX_SIGNED_PAYLOAD_BYTES:
        raise AppStoreVerificationError("Invalid signed App Store payload size")
    parts = signed_payload.split(".")
    if len(parts) != 3:
        raise AppStoreVerificationError("Malformed signed App Store payload")
    try:
        padding = "=" * (-len(parts[1]) % 4)
        decoded = base64.urlsafe_b64decode(parts[1] + padding)
        payload = json.loads(decoded)
    except (ValueError, json.JSONDecodeError) as exc:
        raise AppStoreVerificationError("Malformed signed App Store payload") from exc
    if not isinstance(payload, dict):
        raise AppStoreVerificationError("Malformed signed App Store payload")
    return payload


def _environment_from_payload(signed_payload: str) -> Environment:
    raw_environment = _decode_unverified_payload(signed_payload).get("environment")
    return _environment_from_value(raw_environment)


def _notification_environment_from_payload(signed_payload: str) -> Environment:
    payload = _decode_unverified_payload(signed_payload)
    data = payload.get("data") or {}
    summary = payload.get("summary") or {}
    app_data = payload.get("appData") or {}
    raw_environment = (
        data.get("environment")
        or summary.get("environment")
        or app_data.get("environment")
    )
    return _environment_from_value(raw_environment)


def _environment_from_value(raw_environment: Any) -> Environment:
    if raw_environment == Environment.SANDBOX.value:
        return Environment.SANDBOX
    if raw_environment == Environment.PRODUCTION.value:
        return Environment.PRODUCTION
    raise AppStoreVerificationError("Unsupported App Store environment")


@lru_cache(maxsize=1)
def _root_certificates() -> tuple[bytes, ...]:
    certificate_dir = Path(__file__).resolve().parents[1] / "certificates"
    certificates: list[bytes] = []
    for path in sorted(certificate_dir.glob("Apple*.pem")):
        pem = path.read_text(encoding="ascii")
        certificates.append(ssl.PEM_cert_to_DER_cert(pem))
    if not certificates:
        raise AppStoreConfigurationError("Apple root certificates are missing")
    return tuple(certificates)


@lru_cache(maxsize=2)
def _verifier(environment: Environment) -> SignedDataVerifier:
    settings = get_settings()
    app_apple_id = settings.app_store_app_apple_id
    if environment == Environment.PRODUCTION and app_apple_id is None:
        raise AppStoreConfigurationError(
            "APP_STORE_APP_APPLE_ID is required for production transactions"
        )
    return SignedDataVerifier(
        list(_root_certificates()),
        settings.app_store_online_checks,
        environment,
        settings.app_store_bundle_id,
        app_apple_id,
    )


def _verification_failure(exc: VerificationException) -> Exception:
    if exc.status == VerificationStatus.RETRYABLE_VERIFICATION_FAILURE:
        return AppStoreRetryableVerificationError(
            "Apple transaction verification is temporarily unavailable"
        )
    return AppStoreVerificationError("Apple transaction verification failed")


def verify_signed_transaction(signed_transaction: str) -> VerifiedSubscription:
    environment = _environment_from_payload(signed_transaction)
    try:
        payload = _verifier(environment).verify_and_decode_signed_transaction(
            signed_transaction
        )
    except VerificationException as exc:
        raise _verification_failure(exc) from exc

    settings = get_settings()
    allowed_products = {
        item.strip()
        for item in settings.app_store_product_ids.split(",")
        if item.strip()
    }
    if payload.productId not in allowed_products:
        raise AppStoreVerificationError("Unexpected App Store product")
    if payload.rawType != AUTO_RENEWABLE_SUBSCRIPTION:
        raise AppStoreVerificationError("Transaction is not an auto-renewable subscription")
    if not payload.originalTransactionId or not payload.transactionId:
        raise AppStoreVerificationError("Transaction identifiers are missing")

    expires_at = _milliseconds_to_datetime(payload.expiresDate)
    if expires_at is None:
        raise AppStoreVerificationError("Subscription expiration is missing")
    signed_at = _milliseconds_to_datetime(payload.signedDate)
    if signed_at is None:
        raise AppStoreVerificationError("Transaction signature date is missing")
    revoked_at = _milliseconds_to_datetime(payload.revocationDate)
    is_active = (
        expires_at > datetime.now(timezone.utc)
        and revoked_at is None
        and payload.isUpgraded is not True
    )
    return VerifiedSubscription(
        original_transaction_id=payload.originalTransactionId,
        transaction_id=payload.transactionId,
        product_id=payload.productId,
        environment=environment.value,
        app_account_token=payload.appAccountToken,
        purchase_date=_milliseconds_to_datetime(payload.purchaseDate),
        signed_at=signed_at,
        expires_at=expires_at,
        revoked_at=revoked_at,
        offer_type=payload.rawOfferType,
        is_active=is_active,
    )


def verify_notification(signed_payload: str):
    environment = _notification_environment_from_payload(signed_payload)
    try:
        return _verifier(environment).verify_and_decode_notification(signed_payload)
    except VerificationException as exc:
        raise _verification_failure(exc) from exc


def verify_notification_transaction(signed_transaction: str) -> VerifiedSubscription:
    return verify_signed_transaction(signed_transaction)


def verify_notification_renewal_info(
    signed_renewal_info: str | None,
) -> datetime | None:
    if not signed_renewal_info:
        return None
    environment = _environment_from_payload(signed_renewal_info)
    try:
        renewal = _verifier(environment).verify_and_decode_renewal_info(
            signed_renewal_info
        )
    except VerificationException as exc:
        raise _verification_failure(exc) from exc
    return _milliseconds_to_datetime(renewal.gracePeriodExpiresDate)


def normalized_app_account_token(value: str | None) -> str | None:
    if not value:
        return None
    try:
        return str(UUID(value))
    except ValueError:
        return None
