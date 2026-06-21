import base64
import json
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from app.services import app_store


def _signed_payload(environment: str = "Sandbox") -> str:
    def encode(value: dict) -> str:
        raw = json.dumps(value, separators=(",", ":")).encode()
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")

    return f"{encode({'alg': 'ES256'})}.{encode({'environment': environment})}.signature"


def _signed_notification(environment: str = "Sandbox") -> str:
    def encode(value: dict) -> str:
        raw = json.dumps(value, separators=(",", ":")).encode()
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")

    payload = {"data": {"environment": environment}}
    return f"{encode({'alg': 'ES256'})}.{encode(payload)}.signature"


def _transaction_payload(**overrides):
    now = datetime.now(timezone.utc)
    values = {
        "productId": "clavix_pro_monthly",
        "rawType": "Auto-Renewable Subscription",
        "originalTransactionId": "1000000000000001",
        "transactionId": "1000000000000002",
        "expiresDate": int((now + timedelta(days=14)).timestamp() * 1000),
        "purchaseDate": int(now.timestamp() * 1000),
        "signedDate": int(now.timestamp() * 1000),
        "revocationDate": None,
        "isUpgraded": False,
        "appAccountToken": "11111111-1111-1111-1111-111111111111",
        "rawOfferType": 1,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def test_verified_introductory_transaction_becomes_active_trial(monkeypatch):
    verifier = SimpleNamespace(
        verify_and_decode_signed_transaction=lambda _signed: _transaction_payload()
    )
    monkeypatch.setattr(app_store, "_verifier", lambda _environment: verifier)
    monkeypatch.setattr(
        app_store,
        "get_settings",
        lambda: SimpleNamespace(app_store_product_ids="clavix_pro_monthly"),
    )

    verified = app_store.verify_signed_transaction(_signed_payload())

    assert verified.is_active is True
    assert verified.offer_type == 1
    assert verified.environment == "Sandbox"
    assert verified.app_account_token == "11111111-1111-1111-1111-111111111111"


def test_expired_or_revoked_transaction_never_grants_access(monkeypatch):
    now = datetime.now(timezone.utc)
    verifier = SimpleNamespace(
        verify_and_decode_signed_transaction=lambda _signed: _transaction_payload(
            expiresDate=int((now - timedelta(minutes=1)).timestamp() * 1000),
            revocationDate=int(now.timestamp() * 1000),
        )
    )
    monkeypatch.setattr(app_store, "_verifier", lambda _environment: verifier)
    monkeypatch.setattr(
        app_store,
        "get_settings",
        lambda: SimpleNamespace(app_store_product_ids="clavix_pro_monthly"),
    )

    assert app_store.verify_signed_transaction(_signed_payload()).is_active is False


def test_unknown_environment_is_rejected_before_certificate_work():
    with pytest.raises(app_store.AppStoreVerificationError):
        app_store.verify_signed_transaction(_signed_payload("Xcode"))


def test_notification_environment_is_read_from_nested_data(monkeypatch):
    expected = SimpleNamespace(notificationUUID="notification-1")
    verifier = SimpleNamespace(
        verify_and_decode_notification=lambda _signed: expected
    )
    monkeypatch.setattr(app_store, "_verifier", lambda environment: verifier)

    assert app_store.verify_notification(_signed_notification()) is expected


def test_unexpected_product_is_rejected(monkeypatch):
    verifier = SimpleNamespace(
        verify_and_decode_signed_transaction=lambda _signed: _transaction_payload(
            productId="attacker_product"
        )
    )
    monkeypatch.setattr(app_store, "_verifier", lambda _environment: verifier)
    monkeypatch.setattr(
        app_store,
        "get_settings",
        lambda: SimpleNamespace(app_store_product_ids="clavix_pro_monthly"),
    )

    with pytest.raises(app_store.AppStoreVerificationError):
        app_store.verify_signed_transaction(_signed_payload())
