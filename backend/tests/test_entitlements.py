from datetime import datetime, timedelta, timezone

from app.services.entitlements import effective_tier_from_preferences, has_paid_access


def test_admin_override_does_not_require_storekit_expiration():
    assert effective_tier_from_preferences({"subscription_tier": "admin"}) == "admin"


def test_pro_requires_unexpired_server_verified_expiration():
    now = datetime(2026, 6, 21, tzinfo=timezone.utc)
    assert (
        effective_tier_from_preferences(
            {
                "subscription_tier": "pro",
                "subscription_expires_at": (now + timedelta(days=1)).isoformat(),
            },
            now=now,
        )
        == "pro"
    )
    assert (
        effective_tier_from_preferences(
            {
                "subscription_tier": "pro",
                "subscription_expires_at": (now - timedelta(seconds=1)).isoformat(),
            },
            now=now,
        )
        == "free"
    )
    assert effective_tier_from_preferences({"subscription_tier": "pro"}, now=now) == "free"


def test_introductory_offer_is_reported_as_trial():
    now = datetime(2026, 6, 21, tzinfo=timezone.utc)
    assert (
        effective_tier_from_preferences(
            {
                "subscription_tier": "pro",
                "subscription_expires_at": (now + timedelta(days=14)).isoformat(),
                "subscription_offer_type": 1,
            },
            now=now,
        )
        == "trial"
    )


def test_legacy_server_trial_dates_no_longer_grant_access():
    now = datetime(2026, 6, 21, tzinfo=timezone.utc)
    assert (
        effective_tier_from_preferences(
            {
                "subscription_tier": "free",
                "trial_ends_at": (now + timedelta(days=14)).isoformat(),
            },
            now=now,
        )
        == "free"
    )


def test_only_server_verified_paid_tiers_grant_product_access():
    assert has_paid_access("trial")
    assert has_paid_access("pro")
    assert has_paid_access("admin")
    assert not has_paid_access("free")
    assert not has_paid_access("unknown")
