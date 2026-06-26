"""Regression smoke-suite for the 2026-06-25 data-honesty remediation.

Each test pins an exact bug or false-completion that was fixed, so a future change
that silently reintroduces it fails CI instead of shipping. Specifically:

  1. macro R^2 < 0.10 must fall back to the beta heuristic (degenerate-regression bug).
  2. macro beta proxy must be continuous + monotone (the bucket-collapse fix).
  3. financial revenue_growth_trend is a PERCENT, not a fraction (unit bug).
  4. NULL/limited dimensions must NOT be stamped fresh (the freshness lie).
  5. ops_monitor must flag no-history and distribution-collapse.
"""
import sys
import types
from types import SimpleNamespace

# ── Stub heavy optional imports before importing app code ────────────────────
_fake_openai_module = types.ModuleType("openai")


class _FakeOpenAI:  # pragma: no cover - trivial stub
    def __init__(self, *args, **kwargs):
        pass


_fake_openai_module.OpenAI = _FakeOpenAI
sys.modules.setdefault("openai", _fake_openai_module)

from app.pipeline import risk_scorer  # noqa: E402
from app.jobs import ops_monitor  # noqa: E402
from app.services.ticker_cache_service import (  # noqa: E402
    compute_dimension_last_refreshed,
    compute_limited_dimensions,
)


# ── 1. Macro: degenerate regression must be ignored ──────────────────────────
def test_macro_low_r2_ignores_regression_and_uses_beta():
    md = {
        "factor_breakdown": {
            "macro_regression": {"r_squared": 0.02, "sensitivity_score": 95}
        },
        "beta": 2.0,
        "macro_sensitivity": "moderate",
    }
    score = risk_scorer._score_macro_exposure(md)
    # 81 - 2.0*18 = 45 via the beta path; the inflated 95 from the bad fit is rejected.
    assert score == 45
    assert score != 95


def test_macro_good_fit_uses_regression():
    md = {
        "factor_breakdown": {
            "macro_regression": {"r_squared": 0.55, "sensitivity_score": 30}
        },
        "beta": 2.0,
        "macro_sensitivity": "moderate",
    }
    assert risk_scorer._score_macro_exposure(md) == 30


# ── 2. Macro: beta proxy is continuous + monotone ────────────────────────────
def test_macro_beta_proxy_is_continuous_and_monotone():
    def s(beta):
        return risk_scorer._score_macro_exposure(
            {"beta": beta, "macro_sensitivity": "moderate", "factor_breakdown": {}}
        )

    low, mid, high = s(0.5), s(1.0), s(1.5)
    assert (low, mid, high) == (72, 63, 54)
    assert low > mid > high  # lower beta == more resilient == higher score


# ── 3. Financial: revenue growth is a percent, not a fraction ────────────────
def test_financial_revenue_growth_treated_as_percent():
    def f(growth):
        return risk_scorer._score_financial_health({"revenue_growth_trend": growth})

    # Pre-fix, 15.55 was compared as a fraction (>= 0.30) and tied the top bonus with
    # 50%. Post-fix 15.55% lands in the +4 tier, strictly below 50%'s +8 tier.
    assert f(50.0) > f(15.55) > f(-10.0)


# ── 4. Honesty: limited/NULL dimensions are never stamped fresh ──────────────
def test_limited_dimensions_not_stamped_fresh():
    inputs = {
        "financial_health": {"debt_to_equity": 0.5},
        "news_sentiment": {"limited_data": True},  # NULL news
        "macro_exposure": {"limited": True},
        "sector_exposure": {"sector_beta": 1.0},
        "volatility": {"iv": 0.3},
    }
    limited = compute_limited_dimensions(inputs)
    assert set(limited) == {"news_sentiment", "macro_exposure"}

    stamped = compute_dimension_last_refreshed(inputs, "2026-06-25T00:00:00Z")
    assert "news_sentiment" not in stamped
    assert "macro_exposure" not in stamped
    assert set(stamped) == {"financial_health", "sector_exposure", "volatility"}
    assert stamped["financial_health"] == "2026-06-25T00:00:00Z"


# ── 5. ops_monitor: no-history + distribution-collapse ───────────────────────
class _FakeQuery:
    def __init__(self, rows):
        self._rows = rows

    def select(self, *a, **k):
        return self

    def order(self, *a, **k):
        return self

    def limit(self, *a, **k):
        return self

    def eq(self, *a, **k):
        return self

    def gte(self, *a, **k):
        return self

    def range(self, *a, **k):
        return self

    @property
    def not_(self):
        return self

    def is_(self, *a, **k):
        return self

    def execute(self):
        return SimpleNamespace(data=list(self._rows))


class _FakeSupabase:
    def __init__(self, tables):
        self._tables = tables

    def table(self, name):
        return _FakeQuery(self._tables.get(name, []))


def _varied_snapshots(n=546, *, collapse_macro=False):
    rows = []
    for i in range(n):
        rows.append(
            {
                "ticker": f"T{i:04d}",
                "snapshot_date": "2026-06-25",
                "financial_health": 40 + (i % 41),
                "news_sentiment_dim": 35 + (i % 51),
                "macro_exposure_dim": 90.0 if collapse_macro else 30 + (i % 61),
                "sector_exposure": 45 + (i % 31),
                "volatility": 30 + (i % 61),
                "safety_score": 50 + (i % 41),
            }
        )
    return rows


def test_ops_monitor_flags_distribution_collapse(monkeypatch):
    from datetime import datetime, timezone

    now_iso = datetime.now(timezone.utc).isoformat()
    job_runs = [
        {"job_id": jid, "started_at": now_iso} for jid in ops_monitor.JOB_CADENCE_HOURS
    ]
    fake = _FakeSupabase(
        {
            "job_runs": job_runs,
            "ticker_risk_snapshots": _varied_snapshots(collapse_macro=True),
            "shared_ticker_events": [],
        }
    )
    monkeypatch.setattr(ops_monitor, "get_supabase", lambda: fake)

    result = ops_monitor.run()
    warnings = result["metadata"]["warnings"]
    assert any("distribution" in w and "macro_exposure_dim" in w for w in warnings)
    # A genuinely varied dimension must NOT be flagged collapsed.
    assert not any("distribution" in w and "financial_health" in w for w in warnings)


def test_ops_monitor_flags_missing_job_history(monkeypatch):
    fake = _FakeSupabase(
        {
            "job_runs": [],  # no history at all
            "ticker_risk_snapshots": _varied_snapshots(),
            "shared_ticker_events": [],
        }
    )
    monkeypatch.setattr(ops_monitor, "get_supabase", lambda: fake)

    result = ops_monitor.run()
    warnings = result["metadata"]["warnings"]
    assert any("has no job_runs history" in w for w in warnings)


# ── 6. FRED macro regression recovers real factor betas ──────────────────────
def test_fred_macro_regression_recovers_betas(monkeypatch):
    import math
    import time as _time
    from datetime import date, timedelta

    from app.services import macro_regression as mr

    days = []
    d = date(2025, 9, 1)
    for _ in range(180):
        days.append(d.isoformat())
        d += timedelta(days=1)

    def seq(seed, scale):
        # deterministic pseudo-random without Math.random/Date — index-driven
        return [(dd, scale * math.sin(seed + i * 0.7)) for i, dd in enumerate(days)]

    changes = {
        "spy": seq(1.0, 0.01),
        "ust10y": seq(2.0, 0.03),
        "credit": seq(3.0, 0.02),
        "dxy": seq(4.0, 0.004),
        "vix": seq(5.0, 0.8),
    }
    spy_map = dict(changes["spy"])
    ust_map = dict(changes["ust10y"])
    mr._FRED_CACHE.update(
        {"ts": _time.monotonic(), "changes": changes,
         "levels": {"spy": 5000.0, "ust10y": 4.5, "credit": 3.2, "dxy": 100.0, "vix": 15.0}}
    )

    # ticker return = 1.3*spy - 0.5*ust (exact, no noise) -> betas recoverable, R^2 ~ 1
    price, bars = 100.0, []
    for i, dd in enumerate(days):
        if i > 0:
            price *= 1 + (1.3 * spy_map[dd] - 0.5 * ust_map[dd])
        bars.append({"t": dd, "c": price})

    res = mr.run_macro_regression("TEST", bars)
    assert res["limited_data"] is False
    assert res["data_source"] == "fred"
    assert res["r_squared"] > 0.9
    assert abs(res["coefficients"]["spy"] - 1.3) < 0.15
    assert abs(res["coefficients"]["ust10y"] + 0.5) < 0.15
    assert 0 <= res["sensitivity_score"] <= 100
