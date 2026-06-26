"""iOS decode-contract guards for the financial-health dimension.

The iOS app decodes `Methodology.financialHealth.revenueGrowthTrend` as `String?` and
calls `.humanizedTitleCasedDisplayText` on it. A regression that emits the raw numeric
`revenue_growth_trend` (the EDGAR XBRL value stored on ticker_metadata) would crash the
methodology drawer. These tests pin the served field to a string-or-None label and pin
the provenance label to the real fundamentals source (EDGAR), not a hardcoded "finnhub".
"""
from app.services.ticker_cache_service import (
    _build_financial_health_inputs,
    _normalize_growth_trend_label,
)


def test_revenue_growth_trend_is_string_or_none_not_numeric():
    # Numeric EDGAR value on metadata must be served as a string label, never a float.
    inputs = _build_financial_health_inputs(
        {
            "debt_to_equity": 0.5,
            "fcf_margin": 0.2,
            "current_ratio": 2.0,
            "revenue_growth_trend": 0.24,  # numeric (EDGAR XBRL)
            "fundamentals_source": "edgar",
        }
    )
    rgt = inputs["revenue_growth_trend"]
    assert rgt is None or isinstance(rgt, str), f"revenue_growth_trend must be str|None, got {type(rgt)}"
    assert rgt == "positive_3q"


def test_revenue_growth_trend_none_when_missing():
    inputs = _build_financial_health_inputs({"debt_to_equity": 0.5})
    assert inputs["revenue_growth_trend"] is None


def test_normalize_growth_trend_label_never_returns_numeric():
    for v in (0.5, -0.5, 0.0, 0.04, "0.2", None, "garbage"):
        out = _normalize_growth_trend_label(v)
        assert out is None or isinstance(out, str)


def test_data_source_reflects_real_fundamentals_source():
    edgar = _build_financial_health_inputs({"fundamentals_source": "edgar"})
    assert edgar["data_source"] == "edgar"
    finnhub = _build_financial_health_inputs({"fundamentals_source": "finnhub"})
    assert finnhub["data_source"] == "finnhub"
    # Default when unknown should be the primary source, not the legacy hardcode.
    unknown = _build_financial_health_inputs({})
    assert unknown["data_source"] == "edgar"
