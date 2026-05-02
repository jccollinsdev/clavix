import asyncio
import sys
import types

from fastapi import BackgroundTasks, Response

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

from app.routes import positions, tickers
from app.routes.positions import _select_current_analysis


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


def test_select_current_analysis_prefers_latest_substantive_ready_row():
    analyses = [
        {
            "status": "ready",
            "source_count": 0,
            "top_news": [],
            "top_risks": ["No new material risk catalysts identified."],
        },
        {
            "status": "ready",
            "source_count": 3,
            "top_news": ["JPMorgan Joins Project Glasswing"],
            "top_risks": ["Meaningful risk"],
        },
    ]

    selected = _select_current_analysis(analyses)

    assert selected == analyses[1]


def test_select_current_analysis_ignores_draft_rows():
    analyses = [
        {
            "status": "draft",
            "source_count": 2,
            "summary": "Quick brief ready for AMD. Found 2 relevant headlines and started the deeper analysis.",
        },
        {
            "status": "queued",
            "source_count": 1,
        },
    ]

    selected = _select_current_analysis(analyses)

    assert selected is None


def test_select_current_analysis_falls_back_to_latest_ready_when_none_substantive():
    analyses = [
        {
            "status": "ready",
            "source_count": 0,
            "top_news": [],
            "top_risks": ["No new material risk catalysts identified."],
        },
        {
            "status": "ready",
            "source_count": 0,
            "top_news": [],
            "top_risks": [],
        },
    ]

    selected = _select_current_analysis(analyses)

    assert selected == analyses[0]


def test_get_position_detail_ignores_quick_brief_placeholder(monkeypatch):
    rows = {
        "ticker_universe": [
            {
                "ticker": "AMD",
                "company_name": "Advanced Micro Devices",
                "exchange": "NASDAQ",
                "sector": "Technology",
                "industry": "Semiconductors",
                "index_membership": "SP500",
                "is_active": True,
            }
        ],
        "positions": [
            {
                "id": "pos-1",
                "user_id": "user-1",
                "ticker": "AMD",
                "current_price": 155.0,
                "risk_grade": "C",
                "total_score": 58,
                "previous_grade": "D",
            }
        ],
        "position_analyses": [
            {
                "position_id": "pos-1",
                "analysis_run_id": "run-draft",
                "status": "draft",
                "summary": "Quick brief ready for AMD. Found 3 relevant headlines and started the deeper analysis.",
                "long_report": "Draft status text.",
                "methodology": "Initial draft based on the earliest matched headlines while the deeper event analysis is still running.",
                "top_news": ["Draft headline"],
                "top_risks": ["Draft risk"],
                "watch_items": ["Draft watch item"],
                "source_count": 3,
                "updated_at": "2026-04-29T07:00:00+00:00",
            },
            {
                "position_id": "pos-1",
                "analysis_run_id": "run-ready",
                "status": "ready",
                "summary": "AMD faces macro pressure but the AI thesis remains intact.",
                "long_report": "Final report body.",
                "methodology": "Final investor-facing analysis.",
                "top_news": ["AMD gains traction"],
                "top_risks": ["Macro pressure"],
                "watch_items": ["Watch earnings"],
                "source_count": 2,
                "updated_at": "2026-04-29T08:00:00+00:00",
            },
        ],
        "ticker_risk_snapshots": [
            {
                "id": "snap-1",
                "ticker": "AMD",
                "grade": "C",
                "safety_score": 58,
                "analysis_as_of": "2026-04-29T08:00:00+00:00",
                "coverage_state": "substantive",
                "source_count": 2,
                "news_summary": "Company news is supportive for AMD.",
                "reasoning": "Company news is supportive for AMD. Risks are manageable near-term but worth monitoring.",
                "dimension_rationale": {},
            }
        ],
        "ticker_metadata": [
            {
                "ticker": "AMD",
                "company_name": "Advanced Micro Devices",
                "price": 155.0,
                "price_as_of": "2026-04-29T08:00:00+00:00",
                "last_price_source": "finnhub",
            }
        ],
        "ticker_news_cache": [],
        "risk_scores": [
            {
                "position_id": "pos-1",
                "safety_score": 58,
                "grade": "C",
                "calculated_at": "2026-04-29T08:05:00+00:00",
                "reasoning": "",
                "source_count": 2,
            }
        ],
        "analysis_runs": [
            {
                "id": "run-draft",
                "user_id": "user-1",
                "target_position_id": "pos-1",
                "status": "failed",
                "started_at": "2026-04-29T07:00:00+00:00",
                "completed_at": "2026-04-29T07:02:00+00:00",
            },
            {
                "id": "run-ready",
                "user_id": "user-1",
                "target_position_id": "pos-1",
                "status": "completed",
                "started_at": "2026-04-29T08:00:00+00:00",
                "completed_at": "2026-04-29T08:10:00+00:00",
            },
        ],
        "ticker_refresh_jobs": [],
        "alerts": [],
        "watchlists": [],
        "watchlist_items": [],
        "event_analyses": [],
    }
    fake_supabase = _FakeSupabase(rows)
    monkeypatch.setattr("app.routes.positions.get_supabase", lambda: fake_supabase)

    response = asyncio.run(
        positions.get_position_detail(
            "pos-1",
            Response(),
            BackgroundTasks(),
            user_id="user-1",
        )
    )

    current_analysis = response["current_analysis"] or {}
    current_score = response["current_score"] or {}

    assert "Quick brief ready" not in str(current_analysis.get("summary"))
    assert "started the deeper analysis" not in str(current_analysis.get("summary"))
    assert "Quick brief ready" not in str(current_score.get("reasoning"))
    assert "started the deeper analysis" not in str(current_score.get("reasoning"))
    assert current_analysis.get("status") == "ready"


def test_get_ticker_detail_honors_selected_position_id(monkeypatch):
    monkeypatch.setattr(
        "app.services.ticker_cache_service.ensure_sp500_universe_seeded",
        lambda _supabase: None,
    )
    rows = {
        "ticker_universe": [
            {
                "ticker": "AMD",
                "company_name": "Advanced Micro Devices",
                "exchange": "NASDAQ",
                "sector": "Technology",
                "industry": "Semiconductors",
                "index_membership": "SP500",
                "is_active": True,
            }
        ],
        "positions": [
            {
                "id": "pos-1",
                "user_id": "user-1",
                "ticker": "AMD",
                "current_price": 155.0,
                "risk_grade": "C",
                "total_score": 58,
                "previous_grade": "D",
            },
            {
                "id": "pos-2",
                "user_id": "user-1",
                "ticker": "AMD",
                "current_price": 155.0,
                "risk_grade": "F",
                "total_score": 25,
                "previous_grade": "D",
            },
        ],
        "position_analyses": [
            {
                "position_id": "pos-1",
                "analysis_run_id": "run-1",
                "status": "ready",
                "summary": "Position one summary.",
                "long_report": "Position one report.",
                "methodology": "Position one methodology.",
                "top_news": [],
                "top_risks": [],
                "watch_items": [],
                "source_count": 2,
                "updated_at": "2026-04-29T07:00:00+00:00",
            },
            {
                "position_id": "pos-2",
                "analysis_run_id": "run-2",
                "status": "ready",
                "summary": "Position two summary.",
                "long_report": "Position two report.",
                "methodology": "Position two methodology.",
                "top_news": [],
                "top_risks": [],
                "watch_items": [],
                "source_count": 4,
                "updated_at": "2026-04-29T08:00:00+00:00",
            },
        ],
        "ticker_risk_snapshots": [
            {
                "id": "snap-1",
                "ticker": "AMD",
                "grade": "F",
                "safety_score": 25,
                "analysis_as_of": "2026-04-29T08:00:00+00:00",
                "coverage_state": "substantive",
                "source_count": 4,
                "news_summary": "Coverage is substantive.",
                "reasoning": "Coverage is substantive.",
                "dimension_rationale": {},
            }
        ],
        "ticker_metadata": [
            {
                "ticker": "AMD",
                "company_name": "Advanced Micro Devices",
                "price": 155.0,
                "price_as_of": "2026-04-29T08:00:00+00:00",
                "last_price_source": "finnhub",
            }
        ],
        "ticker_news_cache": [],
        "risk_scores": [
            {
                "position_id": "pos-1",
                "safety_score": 58,
                "grade": "C",
                "calculated_at": "2026-04-29T08:05:00+00:00",
                "reasoning": "",
                "source_count": 2,
            },
            {
                "position_id": "pos-2",
                "safety_score": 25,
                "grade": "F",
                "calculated_at": "2026-04-29T08:15:00+00:00",
                "reasoning": "",
                "source_count": 4,
            },
        ],
        "analysis_runs": [
            {
                "id": "run-1",
                "user_id": "user-1",
                "target_position_id": "pos-1",
                "status": "completed",
                "started_at": "2026-04-29T07:00:00+00:00",
                "completed_at": "2026-04-29T07:10:00+00:00",
            },
            {
                "id": "run-2",
                "user_id": "user-1",
                "target_position_id": "pos-2",
                "status": "completed",
                "started_at": "2026-04-29T08:00:00+00:00",
                "completed_at": "2026-04-29T08:10:00+00:00",
            },
        ],
        "ticker_refresh_jobs": [],
        "alerts": [],
        "watchlists": [
            {
                "id": "watchlist-1",
                "user_id": "user-1",
                "name": "Watchlist",
                "is_default": True,
            }
        ],
        "watchlist_items": [
            {"id": "item-1", "watchlist_id": "watchlist-1", "ticker": "AMD"}
        ],
        "event_analyses": [],
    }
    fake_supabase = _FakeSupabase(rows)
    monkeypatch.setattr("app.routes.tickers.get_supabase", lambda: fake_supabase)

    response = asyncio.run(
        tickers.get_ticker_detail(
            "AMD",
            BackgroundTasks(),
            position_id="pos-2",
            user_id="user-1",
        )
    )

    assert response["position"]["id"] == "pos-2"
    assert response["position"]["total_score"] == 25
    assert response["current_analysis"]["position_id"] == "pos-2"
    assert response["current_analysis"]["driver_cards"] == []
    assert response["current_analysis"]["driver_cards_state"] == "pending"
