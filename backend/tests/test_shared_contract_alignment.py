import asyncio
import os
import sys
import types

from fastapi import BackgroundTasks, Response

os.environ.setdefault("SUPABASE_URL", "https://example.com")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "dummy")
os.environ.setdefault("SUPABASE_JWT_SECRET", "dummy")
os.environ.setdefault("MINIMAX_API_KEY", "dummy")

_fake_supabase_module = types.ModuleType("supabase")
_fake_supabase_module.create_client = lambda *args, **kwargs: None
_fake_supabase_module.Client = object
sys.modules.setdefault("supabase", _fake_supabase_module)

_fake_openai_module = types.ModuleType("openai")


class _FakeOpenAI:
    def __init__(self, *args, **kwargs):
        pass


_fake_openai_module.OpenAI = _FakeOpenAI
sys.modules.setdefault("openai", _fake_openai_module)

from app.routes import dashboard, digest, holdings, positions, tickers, watchlists
from app.services import ticker_cache_service


class _FakeResult:
    def __init__(self, data):
        self.data = data


class _FakeQuery:
    def __init__(self, supabase, table_name):
        self.supabase = supabase
        self.table_name = table_name
        self.filters = {}
        self.in_filters = {}

    def select(self, *_args, **_kwargs):
        return self

    def eq(self, key, value):
        self.filters[key] = value
        return self

    def in_(self, key, values):
        self.in_filters[key] = set(values)
        return self

    def order(self, *_args, **_kwargs):
        return self

    def limit(self, *_args, **_kwargs):
        return self

    def execute(self):
        rows = list(self.supabase.rows.get(self.table_name, []))
        for key, value in self.filters.items():
            rows = [row for row in rows if row.get(key) == value]
        for key, values in self.in_filters.items():
            rows = [row for row in rows if row.get(key) in values]
        return _FakeResult(rows)


class _FakeSupabase:
    def __init__(self, rows):
        self.rows = rows

    def table(self, table_name):
        return _FakeQuery(self, table_name)


def _base_rows():
    return {
        "ticker_universe": [
            {
                "ticker": "AMD",
                "company_name": "Advanced Micro Devices",
                "exchange": "NASDAQ",
                "sector": "Technology",
                "industry": "Semiconductors",
                "is_active": True,
            }
        ],
        "ticker_metadata": [
            {
                "ticker": "AMD",
                "company_name": "Advanced Micro Devices",
                "exchange": "NASDAQ",
                "sector": "Technology",
                "industry": "Semiconductors",
                "price": 155.0,
                "price_as_of": "2026-05-05T08:00:00+00:00",
                "last_price_source": "finnhub",
                "pe_ratio": 31.2,
                "week_52_high": 170.0,
                "week_52_low": 92.0,
                "market_cap": 250000000000,
                "avg_volume": 55000000,
                "previous_close": 153.0,
                "open_price": 154.0,
                "day_high": 156.0,
                "day_low": 152.0,
            }
        ],
        "ticker_risk_snapshots": [
            {
                "id": "snap-amd-1",
                "ticker": "AMD",
                "snapshot_type": "daily",
                "snapshot_date": "2026-05-05",
                "grade": "C",
                "safety_score": 58,
                "analysis_as_of": "2026-05-05T08:00:00+00:00",
                "coverage_state": "substantive",
                "source_count": 3,
                "news_summary": "AMD's AI demand remains solid, but valuation and competitive pressure keep downside risk elevated.",
                "reasoning": "AMD's AI demand remains solid, but valuation and competitive pressure keep downside risk elevated.",
                "methodology_version": "sp500-ai-analysis-v2",
                "factor_breakdown": {
                    "ai_dimensions": {
                        "news_sentiment": 61,
                        "macro_exposure": 49,
                        "volatility_trend": 45,
                    }
                },
                "dimension_rationale": {},
            },
            {
                "id": "snap-amd-prev",
                "ticker": "AMD",
                "snapshot_type": "daily",
                "snapshot_date": "2026-05-04",
                "grade": "D",
                "safety_score": 52,
                "analysis_as_of": "2026-05-04T08:00:00+00:00",
                "coverage_state": "substantive",
                "source_count": 3,
                "news_summary": "Older AMD summary.",
                "reasoning": "Older AMD summary.",
                "methodology_version": "sp500-ai-analysis-v2",
                "factor_breakdown": {
                    "ai_dimensions": {
                        "news_sentiment": 56,
                        "macro_exposure": 47,
                        "volatility_trend": 42,
                    }
                },
                "dimension_rationale": {},
            },
        ],
        "ticker_news_cache": [
            {
                "id": "news-amd-1",
                "ticker": "AMD",
                "headline": "AMD expands MI350 AI server footprint",
                "summary": "Enterprise AI demand is building, but Nvidia pricing pressure remains a risk.",
                "source": "Reuters",
                "url": "https://example.com/amd-1",
                "sentiment": "neutral",
                "published_at": "2026-05-05T07:30:00+00:00",
                "processed_at": "2026-05-05T07:35:00+00:00",
                "event_type": "company_specific",
            },
            {
                "id": "news-amd-2",
                "ticker": "AMD",
                "headline": "Hyperscaler capex outlook stays firm",
                "summary": "Cloud spending supports the AI chip cycle.",
                "source": "CNBC",
                "url": "https://example.com/amd-2",
                "sentiment": "positive",
                "published_at": "2026-05-05T06:45:00+00:00",
                "processed_at": "2026-05-05T06:50:00+00:00",
                "event_type": "sector",
            },
        ],
        "positions": [
            {
                "id": "pos-user-amd",
                "user_id": "user-1",
                "ticker": "AMD",
                "shares": 10,
                "purchase_price": 120.0,
                "current_price": 155.0,
                "archetype": "growth",
                "created_at": "2026-05-01T08:00:00+00:00",
                "updated_at": "2026-05-05T08:00:00+00:00",
            },
            {
                "id": "pos-user-msft",
                "user_id": "user-1",
                "ticker": "MSFT",
                "shares": 4,
                "purchase_price": 400.0,
                "current_price": 410.0,
                "archetype": "growth",
                "created_at": "2026-05-01T08:00:00+00:00",
                "updated_at": "2026-05-05T08:00:00+00:00",
            },
            {
                "id": "pos-system-amd",
                "user_id": ticker_cache_service.SYSTEM_SP500_USER_ID,
                "ticker": "AMD",
                "shares": 0.0,
                "purchase_price": 0.0,
                "current_price": 155.0,
                "archetype": "growth",
                "created_at": "2026-05-01T08:00:00+00:00",
                "updated_at": "2026-05-05T08:00:00+00:00",
            },
        ],
        "position_analyses": [
            {
                "position_id": "pos-system-amd",
                "analysis_run_id": "run-shared-amd",
                "ticker": "AMD",
                "status": "ready",
                "summary": "AMD's AI server momentum is real, but competitive intensity keeps the rating in elevated territory.",
                "long_report": "AI server demand supports AMD, but pricing discipline and execution against Nvidia remain the key downside checks.",
                "methodology": "Shared ticker analysis from the canonical AMD run.",
                "top_risks": ["Competitive pricing pressure", "Valuation sensitivity"],
                "watch_items": ["Track MI350 adoption", "Track hyperscaler orders"],
                "top_tailwinds": ["AI demand remains healthy"],
                "major_event_count": 1,
                "minor_event_count": 1,
                "source_count": 3,
                "driver_cards_state": "ready",
                "driver_cards_source": "generated",
                "driver_cards": [
                    {
                        "id": "driver-1",
                        "rank": 1,
                        "theme": "ai_demand",
                        "direction": "positive",
                        "title": "AI demand supports AMD",
                        "summary": "Enterprise AI demand remains healthy, but the rating still reflects execution and valuation risk.",
                        "strength": "moderate",
                        "source_chips": ["Reuters", "CNBC"],
                        "supporting_evidence": [{"id": "event-1"}],
                    }
                ],
                "updated_at": "2026-05-05T08:05:00+00:00",
            }
        ],
        "event_analyses": [
            {
                "id": "event-1",
                "analysis_run_id": "run-shared-amd",
                "position_id": "pos-system-amd",
                "event_hash": "hash-amd-1",
                "title": "AMD expands MI350 AI server footprint",
                "summary": "Enterprise AI demand is building.",
                "source": "Reuters",
                "source_url": "https://example.com/amd-1",
                "published_at": "2026-05-05T07:30:00+00:00",
                "event_type": "company_specific",
                "significance": "major",
                "analysis_source": "minimax",
                "confidence": 0.78,
                "risk_direction": "neutral",
                "what_happened": "AMD expanded MI350 server deployments.",
                "tldr": "Demand is improving, but the rating still reflects execution risk.",
                "what_it_means": "AI demand is supportive, but competitive pressure still matters.",
                "key_implications": ["AI demand remains healthy"],
                "recommended_followups": ["Track hyperscaler order follow-through"],
                "created_at": "2026-05-05T08:04:00+00:00",
            }
        ],
        "analysis_runs": [
            {
                "id": "run-shared-amd",
                "user_id": ticker_cache_service.SYSTEM_SP500_USER_ID,
                "target_position_id": "pos-system-amd",
                "status": "completed",
                "started_at": "2026-05-05T07:40:00+00:00",
                "completed_at": "2026-05-05T08:06:00+00:00",
            },
            {
                "id": "run-dashboard-1",
                "user_id": "user-1",
                "status": "completed",
                "current_stage": "completed",
                "started_at": "2026-05-05T08:10:00+00:00",
                "completed_at": "2026-05-05T08:15:00+00:00",
            },
        ],
        "ticker_refresh_jobs": [
            {
                "id": "job-amd-1",
                "ticker": "AMD",
                "job_type": "daily",
                "status": "completed",
                "started_at": "2026-05-05T07:20:00+00:00",
                "completed_at": "2026-05-05T07:40:00+00:00",
                "error_message": None,
            }
        ],
        "watchlists": [
            {"id": "watchlist-1", "user_id": "user-1", "name": "Watchlist", "is_default": True},
            {"id": "watchlist-2", "user_id": "user-2", "name": "Watchlist", "is_default": True},
        ],
        "watchlist_items": [
            {"id": "watch-item-amd", "watchlist_id": "watchlist-1", "ticker": "AMD"}
        ],
        "alerts": [
            {
                "id": "alert-amd-1",
                "user_id": "user-1",
                "position_ticker": "AMD",
                "type": "major_event",
                "message": "AMD event",
                "created_at": "2026-05-05T08:20:00+00:00",
            }
        ],
        "digests": [
            {
                "id": "digest-1",
                "user_id": "user-1",
                "analysis_run_id": "run-dashboard-1",
                "overall_grade": "C",
                "overall_score": 58,
                "generated_at": "2026-05-05T08:16:00+00:00",
                "content": "Digest content",
                "structured_sections": {},
                "summary": "Digest summary",
                "grade_summary": {"AMD": "C"},
            }
        ],
        "portfolio_risk_snapshots": [
            {
                "id": "prs-1",
                "user_id": "user-1",
                "as_of_date": "2026-05-05",
                "portfolio_allocation_risk_score": 58,
                "confidence": 0.8,
                "concentration_risk": 51,
                "cluster_risk": 40,
                "correlation_risk": 35,
                "liquidity_mismatch": 10,
                "macro_stack_risk": 32,
                "factor_breakdown": {},
                "top_risk_drivers": [],
                "danger_clusters": [],
            }
        ],
        "user_preferences": [
            {"user_id": "user-1", "notifications_enabled": True, "digest_time": "07:00", "subscription_tier": "pro"},
            {"user_id": "user-2", "notifications_enabled": True, "digest_time": "07:00", "subscription_tier": "free"},
        ],
    }


def _patch_shared_reads(monkeypatch, supabase):
    monkeypatch.setattr(
        "app.services.ticker_cache_service.ensure_sp500_universe_seeded",
        lambda _supabase: None,
    )
    monkeypatch.setattr(holdings, "get_supabase", lambda: supabase)
    monkeypatch.setattr(watchlists, "get_supabase", lambda: supabase)
    monkeypatch.setattr(tickers, "get_supabase", lambda: supabase)
    monkeypatch.setattr(positions, "get_supabase", lambda: supabase)
    monkeypatch.setattr(dashboard, "get_supabase", lambda: supabase)
    monkeypatch.setattr(digest, "get_supabase", lambda: supabase)


def test_same_ticker_returns_same_shared_summary_across_surfaces(monkeypatch):
    supabase = _FakeSupabase(_base_rows())
    _patch_shared_reads(monkeypatch, supabase)

    holdings_result = asyncio.run(
        holdings.list_holdings(BackgroundTasks(), user_id="user-1")
    )
    watchlists_result = asyncio.run(watchlists.get_watchlists(user_id="user-1"))
    search_result = asyncio.run(
        tickers.search_tickers(q="AMD", limit=10, user_id="user-1")
    )
    detail_result = asyncio.run(
        tickers.get_ticker_detail(
            "AMD",
            BackgroundTasks(),
            position_id="pos-user-amd",
            user_id="user-1",
        )
    )

    holdings_summary = holdings_result[0]["shared_analysis"]
    watchlist_summary = watchlists_result["watchlists"][0]["items"][0]["shared_analysis"]
    search_summary = search_result["results"][0]["shared_analysis"]
    detail_summary = detail_result["shared_analysis"]["summary"]

    assert holdings_summary == watchlist_summary == search_summary == detail_summary


def test_held_and_non_held_ticker_detail_differ_only_by_overlay(monkeypatch):
    supabase = _FakeSupabase(_base_rows())
    monkeypatch.setattr(
        "app.services.ticker_cache_service.ensure_sp500_universe_seeded",
        lambda _supabase: None,
    )

    held_detail = ticker_cache_service.get_ticker_detail_bundle(supabase, "user-1", "AMD")
    unheld_detail = ticker_cache_service.get_ticker_detail_bundle(supabase, "user-2", "AMD")

    assert held_detail["shared_analysis"] == unheld_detail["shared_analysis"]
    assert held_detail["current_score"] == unheld_detail["current_score"]
    assert held_detail["portfolio_overlay"] != unheld_detail["portfolio_overlay"]
    assert held_detail["portfolio_overlay"]["is_held"] is True
    assert unheld_detail["portfolio_overlay"]["is_held"] is False


def test_position_detail_matches_ticker_detail_for_same_position(monkeypatch):
    supabase = _FakeSupabase(_base_rows())
    _patch_shared_reads(monkeypatch, supabase)

    position_detail = asyncio.run(
        positions.get_position_detail(
            "pos-user-amd",
            Response(),
            BackgroundTasks(),
            user_id="user-1",
        )
    )
    ticker_detail = asyncio.run(
        tickers.get_ticker_detail(
            "AMD",
            BackgroundTasks(),
            position_id="pos-user-amd",
            user_id="user-1",
        )
    )

    assert position_detail == ticker_detail


def test_dashboard_positions_match_holdings(monkeypatch):
    supabase = _FakeSupabase(_base_rows())
    _patch_shared_reads(monkeypatch, supabase)

    holdings_result = asyncio.run(
        holdings.list_holdings(BackgroundTasks(), user_id="user-1")
    )
    dashboard_result = asyncio.run(
        dashboard.get_dashboard(Response(), BackgroundTasks(), user_id="user-1")
    )

    assert dashboard_result["positions"] == holdings_result


def test_digest_and_dashboard_score_metadata_are_consistent(monkeypatch):
    supabase = _FakeSupabase(_base_rows())
    _patch_shared_reads(monkeypatch, supabase)

    dashboard_result = asyncio.run(
        dashboard.get_dashboard(Response(), BackgroundTasks(), user_id="user-1")
    )
    digest_result = asyncio.run(digest.get_digest(force_refresh=False, user_id="user-1"))

    for key in (
        "overall_score",
        "overall_grade",
        "score_source",
        "score_as_of",
        "score_version",
    ):
        assert dashboard_result[key] == digest_result[key]


def test_compatibility_fields_remain_present_for_ios_decoders(monkeypatch):
    supabase = _FakeSupabase(_base_rows())
    monkeypatch.setattr(
        "app.services.ticker_cache_service.ensure_sp500_universe_seeded",
        lambda _supabase: None,
    )

    detail = ticker_cache_service.get_ticker_detail_bundle(supabase, "user-1", "AMD")

    assert "position" in detail
    assert "current_score" in detail
    assert "current_analysis" in detail
    assert "latest_event_analyses" in detail
    assert "freshness" in detail
    assert "analysis_state" in detail
    assert "latest_risk_snapshot" in detail
    assert detail["position"]["risk_grade"] == detail["shared_analysis"]["summary"]["current_grade"]
    assert detail["current_score"]["total_score"] == detail["shared_analysis"]["summary"]["current_score"]
    assert detail["current_analysis"]["summary"] == detail["shared_analysis"]["executive_summary"]
