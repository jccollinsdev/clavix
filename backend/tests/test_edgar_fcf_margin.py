"""Regression tests for EDGAR FCF-margin extraction.

Covers the two defects that produced HOOD's 131% FCF margin:
  1. No plausibility guard on an op-cash-flow-as-FCF proxy that exceeds revenue.
  2. Period mismatch — dividing current cash flow by a stale abandoned revenue tag
     (e.g. ICE retired the ``Revenues`` tag in 2017), which the independent
     per-concept "latest" lookup happily paired with 2025 cash flow.
"""
from __future__ import annotations

from app.services.edgar_client import _extract_fundamentals, validate_fcf_margin


def _fact_row(start, end, val):
    return {"form": "10-K", "start": start, "end": end, "val": val, "accn": f"a-{end}"}


def _facts(concepts):
    return {"facts": {"us-gaap": {c: {"units": {"USD": rows}} for c, rows in concepts.items()}}}


def test_validate_fcf_margin_rejects_impossible():
    # FCF cannot exceed revenue for a going concern.
    assert validate_fcf_margin(1.313) is None      # HOOD as reported
    assert validate_fcf_margin(1.9974) is None     # STT
    assert validate_fcf_margin(-1.5) is None
    assert validate_fcf_margin(float("nan")) is None
    assert validate_fcf_margin(None) is None
    # Plausible values pass through unchanged.
    assert validate_fcf_margin(0.3662) == 0.3662
    assert validate_fcf_margin(-0.35) == -0.35
    assert validate_fcf_margin("0.4") == 0.4


def test_stale_revenue_tag_does_not_inflate_margin():
    # Modern revenue tag reports 2025; the legacy Revenues tag was abandoned in 2017.
    # Naive "latest per concept" would divide 2025 op-cash-flow by 2017 revenue.
    facts = _facts({
        "RevenueFromContractWithCustomerExcludingAssessedTax": [
            _fact_row("2025-01-01", "2025-12-31", 12_640_000_000),
            _fact_row("2024-01-01", "2024-12-31", 11_761_000_000),
        ],
        "Revenues": [
            _fact_row("2017-01-01", "2017-12-31", 5_834_000_000),
        ],
        "NetCashProvidedByUsedInOperatingActivities": [
            _fact_row("2025-01-01", "2025-12-31", 4_662_000_000),
        ],
        "PaymentsToAcquirePropertyPlantAndEquipment": [
            _fact_row("2025-01-01", "2025-12-31", 373_000_000),
        ],
    })
    out = _extract_fundamentals(facts, "ICE")
    # (4662 - 373) / 12640 = 0.339, NOT 4289 / 5834 = 0.735
    assert out["fcf_margin"] == 0.3393


def test_op_cf_exceeding_revenue_is_discarded():
    # Broker-style year where operating cash flow (customer-balance swings) tops revenue.
    facts = _facts({
        "Revenues": [_fact_row("2024-01-01", "2024-12-31", 1_000_000_000)],
        "NetCashProvidedByUsedInOperatingActivities": [
            _fact_row("2024-01-01", "2024-12-31", 2_000_000_000)
        ],
    })
    out = _extract_fundamentals(facts, "BROKER")
    assert out["fcf_margin"] is None


def test_deposit_bank_fcf_margin_suppressed():
    # A deposit-taker (reports deposit-liability / interest-income concepts) has no
    # meaningful FCF margin, so it is suppressed even when op-cf < revenue would compute.
    facts = _facts({
        "Revenues": [_fact_row("2024-01-01", "2024-12-31", 100_000_000_000)],
        "NetCashProvidedByUsedInOperatingActivities": [
            _fact_row("2024-01-01", "2024-12-31", 20_000_000_000)
        ],
        "InterestAndDividendIncomeOperating": [
            _fact_row("2024-01-01", "2024-12-31", 90_000_000_000)
        ],
    })
    out = _extract_fundamentals(facts, "BANK")
    assert out["fcf_margin"] is None
    # Revenue growth is still computed for banks when history exists.
    facts["facts"]["us-gaap"]["Revenues"]["units"]["USD"].append(
        _fact_row("2023-01-01", "2023-12-31", 80_000_000_000)
    )
    assert _extract_fundamentals(facts, "BANK")["revenue_growth_trend"] == 0.25


def test_broker_without_deposits_keeps_fcf_margin():
    # A broker (no deposit-bank concepts) keeps a plausible FCF margin — this is the HOOD
    # case the fix must preserve at ~37%, not suppress.
    facts = _facts({
        "Revenues": [_fact_row("2025-01-01", "2025-12-31", 4_473_000_000)],
        "NetCashProvidedByUsedInOperatingActivities": [
            _fact_row("2025-01-01", "2025-12-31", 1_638_000_000)
        ],
    })
    out = _extract_fundamentals(facts, "HOOD")
    assert out["fcf_margin"] == 0.3662


def test_quarterly_stub_not_mistaken_for_annual():
    # A 10-K carrying a 3-month stub with the same year-end must not be picked over the
    # full-year figure, which would understate op-cash-flow against full-year revenue.
    facts = _facts({
        "Revenues": [_fact_row("2024-01-01", "2024-12-31", 1_000_000_000)],
        "NetCashProvidedByUsedInOperatingActivities": [
            _fact_row("2024-10-01", "2024-12-31", 80_000_000),   # Q4 stub
            _fact_row("2024-01-01", "2024-12-31", 300_000_000),  # full year
        ],
    })
    out = _extract_fundamentals(facts, "CO")
    assert out["fcf_margin"] == 0.3  # 300M / 1000M, not 80M / 1000M
