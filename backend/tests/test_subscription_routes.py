import asyncio
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.routes import subscriptions
from app.services.app_store import VerifiedSubscription


class _Result:
    def __init__(self, data):
        self.data = data


class _Query:
    def __init__(self, db, table):
        self.db = db
        self.table = table
        self.filters = {}
        self.operation = None
        self.payload = None
        self.on_conflict = None

    def select(self, *_args, **_kwargs):
        return self

    def eq(self, key, value):
        self.filters[key] = value
        return self

    def limit(self, *_args):
        return self

    def insert(self, payload):
        self.operation = "insert"
        self.payload = payload
        return self

    def update(self, payload):
        self.operation = "update"
        self.payload = payload
        return self

    def upsert(self, payload, on_conflict=None):
        self.operation = "upsert"
        self.payload = payload
        self.on_conflict = on_conflict
        return self

    def execute(self):
        rows = self.db.rows.setdefault(self.table, [])
        matches = [
            row
            for row in rows
            if all(row.get(key) == value for key, value in self.filters.items())
        ]
        if self.operation == "insert":
            rows.append(dict(self.payload))
            return _Result([self.payload])
        if self.operation == "update":
            for row in matches:
                row.update(self.payload)
            return _Result(matches)
        if self.operation == "upsert":
            key = self.on_conflict
            existing = next(
                (row for row in rows if row.get(key) == self.payload.get(key)),
                None,
            )
            if existing:
                existing.update(self.payload)
            else:
                rows.append(dict(self.payload))
            return _Result([self.payload])
        return _Result(matches)


class _Supabase:
    def __init__(self, rows):
        self.rows = rows

    def table(self, name):
        return _Query(self, name)


def _verified_subscription(*, user_id, active=True, signed_at=None):
    now = signed_at or datetime.now(timezone.utc)
    return VerifiedSubscription(
        original_transaction_id="1000000000000001",
        transaction_id="1000000000000002",
        product_id="clavix_pro_monthly",
        environment="Sandbox",
        app_account_token=user_id,
        purchase_date=now,
        signed_at=now,
        expires_at=now + timedelta(days=14) if active else now - timedelta(minutes=1),
        revoked_at=None,
        offer_type=1,
        is_active=active,
    )


def test_sync_binds_purchase_to_authenticated_user_and_persists_trial(monkeypatch):
    user_id = "11111111-1111-1111-1111-111111111111"
    db = _Supabase(
        {
            "app_store_subscriptions": [],
            "user_preferences": [
                {"id": "pref-1", "user_id": user_id, "subscription_tier": "free"}
            ],
        }
    )
    monkeypatch.setattr(subscriptions, "get_supabase", lambda: db)
    monkeypatch.setattr(
        subscriptions,
        "verify_signed_transaction",
        lambda _signed: _verified_subscription(user_id=user_id),
    )
    request = SimpleNamespace(state=SimpleNamespace(user_id=user_id))

    result = asyncio.run(
        subscriptions.sync_subscription(
            subscriptions.SubscriptionSyncRequest(signed_transaction="signed"),
            request,
        )
    )

    assert result["effective_tier"] == "trial"
    assert db.rows["user_preferences"][0]["subscription_tier"] == "pro"
    assert db.rows["user_preferences"][0]["trial_ends_at"] is None
    assert db.rows["app_store_subscriptions"][0]["user_id"] == user_id


def test_sync_rejects_transaction_bound_to_another_user(monkeypatch):
    authenticated_user_id = "11111111-1111-1111-1111-111111111111"
    purchase_user_id = "22222222-2222-2222-2222-222222222222"
    db = _Supabase({"app_store_subscriptions": [], "user_preferences": []})
    monkeypatch.setattr(subscriptions, "get_supabase", lambda: db)
    monkeypatch.setattr(
        subscriptions,
        "verify_signed_transaction",
        lambda _signed: _verified_subscription(user_id=purchase_user_id),
    )
    request = SimpleNamespace(
        state=SimpleNamespace(user_id=authenticated_user_id)
    )

    with pytest.raises(HTTPException) as exc:
        asyncio.run(
            subscriptions.sync_subscription(
                subscriptions.SubscriptionSyncRequest(signed_transaction="signed"),
                request,
            )
        )

    assert exc.value.status_code == 403
    assert db.rows["app_store_subscriptions"] == []


def test_expired_verified_transaction_downgrades_existing_pro(monkeypatch):
    user_id = "11111111-1111-1111-1111-111111111111"
    db = _Supabase(
        {
            "app_store_subscriptions": [],
            "user_preferences": [
                {"id": "pref-1", "user_id": user_id, "subscription_tier": "pro"}
            ],
        }
    )
    monkeypatch.setattr(subscriptions, "get_supabase", lambda: db)
    monkeypatch.setattr(
        subscriptions,
        "verify_signed_transaction",
        lambda _signed: _verified_subscription(user_id=user_id, active=False),
    )
    request = SimpleNamespace(state=SimpleNamespace(user_id=user_id))

    result = asyncio.run(
        subscriptions.sync_subscription(
            subscriptions.SubscriptionSyncRequest(signed_transaction="signed"),
            request,
        )
    )

    assert result["effective_tier"] == "free"
    assert db.rows["user_preferences"][0]["subscription_tier"] == "free"


def test_stale_event_cannot_reenable_a_newer_revoked_entitlement():
    user_id = "11111111-1111-1111-1111-111111111111"
    now = datetime.now(timezone.utc)
    db = _Supabase(
        {
            "app_store_subscriptions": [
                {
                    "user_id": user_id,
                    "original_transaction_id": "1000000000000001",
                    "last_event_at": now.isoformat(),
                    "is_active": False,
                }
            ],
            "user_preferences": [
                {"id": "pref-1", "user_id": user_id, "subscription_tier": "free"}
            ],
        }
    )
    stale = _verified_subscription(
        user_id=user_id,
        active=True,
        signed_at=now - timedelta(minutes=5),
    )

    applied = subscriptions._persist_entitlement(
        db,
        user_id=user_id,
        subscription=stale,
        is_active=True,
        effective_expires_at=stale.expires_at,
        event_at=stale.signed_at,
    )

    assert applied is False
    assert db.rows["user_preferences"][0]["subscription_tier"] == "free"
    assert db.rows["app_store_subscriptions"][0]["is_active"] is False
