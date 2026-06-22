import json

import pytest
from fastapi import Request
from fastapi.responses import JSONResponse

from app import main
from app.main import _is_entitlement_exempt_path


def test_purchase_recovery_and_account_routes_are_exempt():
    assert _is_entitlement_exempt_path("POST", "/subscriptions/sync")
    assert _is_entitlement_exempt_path("GET", "/preferences/")
    assert _is_entitlement_exempt_path("DELETE", "/account")
    assert _is_entitlement_exempt_path("POST", "/analytics/events")


def test_minimum_onboarding_routes_are_exempt():
    assert _is_entitlement_exempt_path("GET", "/tickers/search")
    assert _is_entitlement_exempt_path("POST", "/holdings")
    assert _is_entitlement_exempt_path("POST", "/brokerage/connect")


def test_paid_product_routes_are_not_exempt():
    assert not _is_entitlement_exempt_path("GET", "/holdings")
    assert not _is_entitlement_exempt_path("GET", "/today")
    assert not _is_entitlement_exempt_path("GET", "/tickers/AAPL")
    assert not _is_entitlement_exempt_path("POST", "/holdings/refresh")
    assert not _is_entitlement_exempt_path("GET", "/accounting")


def _request(method: str, path: str) -> Request:
    return Request(
        {
            "type": "http",
            "method": method,
            "path": path,
            "headers": [(b"authorization", b"Bearer valid-token")],
            "query_string": b"",
            "server": ("test", 443),
            "client": ("test", 123),
            "scheme": "https",
        }
    )


@pytest.mark.asyncio
async def test_unpaid_user_is_stopped_before_protected_route(monkeypatch):
    monkeypatch.setattr(main.settings, "hard_paywall_enabled", True)
    monkeypatch.setattr(main, "_resolve_user_id_from_token", lambda _token: "user-1")
    monkeypatch.setattr(main, "get_supabase", lambda: object())
    monkeypatch.setattr(main, "get_effective_tier", lambda _db, _user_id: "free")

    async def call_next(_request):
        return JSONResponse({"unexpected": True})

    response = await main.validate_jwt_middleware(
        _request("GET", "/today"),
        call_next,
    )

    assert response.status_code == 402
    assert json.loads(response.body)["code"] == "subscription_required"


@pytest.mark.asyncio
async def test_unpaid_user_can_reach_subscription_recovery(monkeypatch):
    monkeypatch.setattr(main.settings, "hard_paywall_enabled", True)
    monkeypatch.setattr(main, "_resolve_user_id_from_token", lambda _token: "user-1")

    async def call_next(_request):
        return JSONResponse({"reached": True})

    response = await main.validate_jwt_middleware(
        _request("POST", "/subscriptions/sync"),
        call_next,
    )

    assert response.status_code == 200
    assert json.loads(response.body)["reached"] is True
