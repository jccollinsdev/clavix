"""SEC EDGAR XBRL fundamentals client.

Fetches as-reported financial data from EDGAR's free, public-domain companyfacts
XBRL API. Commercial use is unrestricted (US government data). MANDATORY: the
User-Agent header must be descriptive with a contact email or the IP is blocked.

Endpoints:
  Company ticker -> CIK: https://www.sec.gov/files/company_tickers.json
  Company facts:         https://data.sec.gov/api/xbrl/companyfacts/CIK{10d}.json

Rate limit: ~10 req/sec (be conservative; EDGAR blocks aggressive crawlers).
"""
from __future__ import annotations

import asyncio
import logging
import time
from datetime import date, datetime
from functools import lru_cache
from typing import Any

import httpx

logger = logging.getLogger(__name__)

EDGAR_USER_AGENT = "Clavix support@getclavix.com"
EDGAR_TICKERS_URL = "https://www.sec.gov/files/company_tickers.json"
EDGAR_FACTS_URL = "https://data.sec.gov/api/xbrl/companyfacts/CIK{cik}.json"

_EDGAR_MIN_CALL_INTERVAL = 0.12  # ~8 req/sec (comfortably under 10/s limit)
_last_edgar_call: float = 0.0

_HEADERS = {
    "User-Agent": EDGAR_USER_AGENT,
    "Accept": "application/json",
}

# Free cash flow cannot plausibly exceed revenue for a going concern. When capex is
# unavailable we proxy FCF with operating cash flow, but for banks and brokers that
# figure is dominated by customer-balance, deposit and trading-book swings and can
# dwarf total net revenue, producing nonsense margins (e.g. HOOD 131%, STT 200%,
# JPM 109%). Discard anything outside this band so a meaningless value never scores,
# renders in the audit view, or pollutes the sector median.
FCF_MARGIN_MAX = 1.0
FCF_MARGIN_MIN = -1.0


def validate_fcf_margin(value: Any) -> float | None:
    """Return the FCF margin only if it is economically plausible, else None.

    A margin outside [-100%, +100%] of revenue is not achievable by a sustained
    operating business; such values arise from using operating cash flow as an FCF
    proxy for financial firms, where it is swamped by customer/deposit flows rather
    than reflecting cash the business actually generates.
    """
    if value is None:
        return None
    try:
        v = float(value)
    except (TypeError, ValueError):
        return None
    if v != v:  # NaN
        return None
    if v > FCF_MARGIN_MAX or v < FCF_MARGIN_MIN:
        return None
    return v


# XBRL concepts only genuine deposit-taking institutions report. For a bank, operating
# cash flow is dominated by loan/deposit/trading-book changes, so "FCF margin" is not a
# meaningful figure regardless of how it is computed — we suppress it entirely rather
# than surface a misleading (often negative or >100%) number. A bare `Deposits` balance
# line is intentionally excluded because asset managers with a small trust subsidiary
# (e.g. BEN, AMP) report it without being banks; the concepts below appear only for real
# deposit-takers. Brokers without deposits (HOOD, IBKR) are deliberately NOT matched.
_DEPOSIT_BANK_CONCEPTS = (
    "InterestBearingDepositLiabilities",
    "NoninterestBearingDepositLiabilities",
    "InterestAndDividendIncomeOperating",
)


def _is_deposit_bank(facts: dict[str, Any]) -> bool:
    us_gaap = (facts.get("facts") or {}).get("us-gaap") or {}
    return any(concept in us_gaap for concept in _DEPOSIT_BANK_CONCEPTS)


@lru_cache(maxsize=1)
def _load_cik_map_sync() -> dict[str, str]:
    """Load ticker -> 10-digit padded CIK mapping from EDGAR.

    Result is cached for the process lifetime since it changes rarely.
    Returns {TICKER: "0000123456"}.
    """
    import requests

    try:
        resp = requests.get(
            EDGAR_TICKERS_URL,
            headers={"User-Agent": EDGAR_USER_AGENT},
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()
        mapping: dict[str, str] = {}
        for entry in data.values():
            ticker = str(entry.get("ticker") or "").upper().strip()
            cik_raw = entry.get("cik_str") or entry.get("cik")
            if ticker and cik_raw is not None:
                mapping[ticker] = str(int(cik_raw)).zfill(10)
        logger.info("[EDGAR] CIK map loaded: %d tickers", len(mapping))
        return mapping
    except Exception as exc:
        logger.warning("[EDGAR] Failed to load CIK map: %s", exc)
        return {}


def get_cik(ticker: str) -> str | None:
    """Return the 10-digit padded CIK for a ticker, or None if not found."""
    return _load_cik_map_sync().get(ticker.upper().strip())


def _latest_value(
    facts: dict[str, Any],
    concept: str,
    *,
    form: str | None = None,
    units: str = "USD",
) -> float | None:
    """Extract the most recent annual value for a XBRL concept.

    Prefers annual 10-K data (form='10-K') for stability over quarterly.
    Returns the value from the most recent filing with the given concept.
    """
    try:
        us_gaap = (facts.get("facts") or {}).get("us-gaap") or {}
        concept_data = us_gaap.get(concept) or {}
        unit_data = (concept_data.get("units") or {}).get(units) or []

        # Filter to annual 10-K filings only (most stable)
        candidates = [
            row for row in unit_data
            if row.get("form") in ("10-K", "10-K/A")
            and row.get("val") is not None
            and row.get("end") is not None
            and row.get("accn") is not None
        ]

        if not candidates and form is None:
            # Fall back to 10-Q if no annual data
            candidates = [
                row for row in unit_data
                if row.get("form") in ("10-Q", "10-Q/A")
                and row.get("val") is not None
                and row.get("end") is not None
            ]

        if not candidates:
            return None

        # Sort by period end date, pick most recent
        candidates.sort(key=lambda r: r.get("end", ""), reverse=True)
        best = candidates[0]
        val = best.get("val")
        return float(val) if val is not None else None
    except Exception:
        return None


def _annual_series(
    facts: dict[str, Any],
    concept: str,
    *,
    units: str = "USD",
    flow: bool = True,
) -> dict[str, float]:
    """Map ``{period_end: value}`` for a concept's annual 10-K frames.

    For flow concepts (income statement, cash flow) only full-year (~365d) periods are
    kept, so a quarterly stub that some issuers embed in a 10-K cannot be mistaken for
    the annual figure. For each period end the most recently filed value wins. This is
    the building block that lets FCF, capex and revenue be read from the SAME fiscal
    year instead of each concept's independent "latest", which mixed periods (e.g. ICE
    abandoned the ``Revenues`` tag in 2017, so dividing 2025 cash flow by 2017 revenue
    produced a bogus 74% margin).
    """
    try:
        us_gaap = (facts.get("facts") or {}).get("us-gaap") or {}
        unit_data = ((us_gaap.get(concept) or {}).get("units") or {}).get(units) or []
        picked: dict[str, tuple[float, str]] = {}
        for row in unit_data:
            if row.get("form") not in ("10-K", "10-K/A"):
                continue
            val, end, start = row.get("val"), row.get("end"), row.get("start")
            if val is None or not end:
                continue
            if flow and start:
                try:
                    if (date.fromisoformat(end) - date.fromisoformat(start)).days < 300:
                        continue  # skip quarterly / partial-year periods
                except ValueError:
                    pass
            recency = str(row.get("filed") or row.get("accn") or "")
            prev = picked.get(end)
            if prev is None or recency >= prev[1]:
                picked[end] = (float(val), recency)
        return {end: v for end, (v, _) in picked.items()}
    except Exception:
        return {}


def _merged_revenue_series(facts: dict[str, Any]) -> dict[str, float]:
    """Annual revenue keyed by period end, preferring the modern
    ``RevenueFromContractWithCustomerExcludingAssessedTax`` tag and back-filling gaps
    with the legacy ``Revenues`` tag.

    Merging by period end (rather than ``x or y`` on whole concepts) is what prevents a
    stale abandoned tag from being paired with current cash flow.
    """
    modern = _annual_series(facts, "RevenueFromContractWithCustomerExcludingAssessedTax")
    legacy = _annual_series(facts, "Revenues")
    merged = dict(legacy)
    merged.update(modern)  # modern tag wins on overlapping period ends
    return merged


def _extract_fundamentals(facts: dict[str, Any], ticker: str) -> dict[str, Any]:
    """Extract financial health inputs from a company-facts payload.

    Maps XBRL concepts to the five fields used by _build_financial_health_inputs:
      - debt_to_equity
      - fcf_margin
      - current_ratio
      - revenue_growth_trend (as a normalized label: "strong"/"moderate"/"flat"/"declining")
    """

    def _get(concept: str, units: str = "USD") -> float | None:
        return _latest_value(facts, concept, units=units)

    # ── Debt to equity ────────────────────────────────────────────────────────
    debt_to_equity: float | None = None
    long_term_debt = _get("LongTermDebt")
    stockholders_equity = _get("StockholdersEquity")
    if long_term_debt is not None and stockholders_equity is not None and stockholders_equity > 0:
        debt_to_equity = round(long_term_debt / stockholders_equity, 4)
    if debt_to_equity is None:
        total_liabilities = _get("Liabilities")
        total_equity = _get("StockholdersEquity")
        if total_liabilities is not None and total_equity is not None and total_equity > 0:
            debt_to_equity = round(total_liabilities / total_equity, 4)

    # ── FCF margin ────────────────────────────────────────────────────────────
    # Read op cash flow, capex and revenue from the SAME fiscal year. Pulling each
    # concept's independent "latest" mixed periods (2025 cash flow ÷ 2017 revenue for
    # names that retired the Revenues tag) and produced impossible margins.
    fcf_margin: float | None = None
    rev_series = _merged_revenue_series(facts)
    # Deposit banks have no meaningful FCF margin (operating cash flow is dominated by
    # loan/deposit/trading-book swings), so suppress it rather than emit a misleading
    # number. Brokers without deposits (e.g. HOOD) are unaffected. Revenue growth below
    # is still computed for banks.
    if not _is_deposit_bank(facts):
        op_cf_series = _annual_series(facts, "NetCashProvidedByUsedInOperatingActivities")
        capex_series = _annual_series(facts, "PaymentsToAcquirePropertyPlantAndEquipment")
        common_ends = sorted(set(op_cf_series) & set(rev_series), reverse=True)
        if common_ends:
            end = common_ends[0]
            op_cf = op_cf_series[end]
            revenue = rev_series[end]
            if revenue and revenue > 0:
                capex = capex_series.get(end)
                fcf = op_cf - capex if capex is not None else op_cf
                fcf_margin = round(fcf / revenue, 4)
    # Guard against the op-cash-flow-as-FCF proxy blowing past revenue for the remaining
    # financials, where operating cash flow can still exceed total net revenue.
    fcf_margin = validate_fcf_margin(fcf_margin)

    # ── Current ratio ─────────────────────────────────────────────────────────
    current_ratio: float | None = None
    current_assets = _get("AssetsCurrent")
    current_liabilities = _get("LiabilitiesCurrent")
    if current_assets is not None and current_liabilities is not None and current_liabilities > 0:
        current_ratio = round(current_assets / current_liabilities, 4)

    # ── Revenue growth trend (numeric YoY rate, e.g. 0.15 = 15% growth) ────
    revenue_growth_trend: float | None = None
    rev_ends = sorted(rev_series, reverse=True)
    if len(rev_ends) >= 2:
        latest_rev = rev_series[rev_ends[0]]
        prior_rev = rev_series[rev_ends[1]]
        if prior_rev > 0:
            revenue_growth_trend = round((latest_rev - prior_rev) / prior_rev, 4)

    has_data = any(v is not None for v in [debt_to_equity, fcf_margin, current_ratio])
    return {
        "debt_to_equity": debt_to_equity,
        "fcf_margin": fcf_margin,
        "current_ratio": current_ratio,
        "revenue_growth_trend": revenue_growth_trend,
        "data_source": "edgar",
        "limited_data": not has_data,
    }


async def fetch_edgar_fundamentals_async(
    tickers: list[str],
    *,
    max_concurrency: int = 4,
) -> dict[str, dict[str, Any]]:
    """Fetch EDGAR fundamentals for a list of tickers asynchronously.

    Returns {ticker: fundamentals_dict}. Tickers with no EDGAR data return empty dicts.
    Rate-limits to ~8 req/sec to avoid EDGAR blocks.
    """
    global _last_edgar_call
    cik_map = await asyncio.to_thread(_load_cik_map_sync)
    results: dict[str, dict[str, Any]] = {}
    sem = asyncio.Semaphore(max_concurrency)

    async def _fetch_one(ticker: str) -> tuple[str, dict[str, Any]]:
        global _last_edgar_call
        cik = cik_map.get(ticker.upper())
        if not cik:
            logger.debug("[EDGAR] No CIK for %s", ticker)
            return (ticker, {})

        async with sem:
            now = time.monotonic()
            wait = _EDGAR_MIN_CALL_INTERVAL - (now - _last_edgar_call)
            if wait > 0:
                await asyncio.sleep(wait)
            _last_edgar_call = time.monotonic()

            url = EDGAR_FACTS_URL.format(cik=cik)
            try:
                async with httpx.AsyncClient(timeout=30.0) as client:
                    resp = await client.get(url, headers=_HEADERS)
                if resp.status_code == 404:
                    logger.debug("[EDGAR] No facts for %s (CIK %s)", ticker, cik)
                    return (ticker, {})
                if resp.status_code != 200:
                    logger.warning("[EDGAR] HTTP %d for %s (CIK %s)", resp.status_code, ticker, cik)
                    return (ticker, {})
                facts = resp.json()
                fundamentals = await asyncio.to_thread(_extract_fundamentals, facts, ticker)
                return (ticker, fundamentals)
            except Exception as exc:
                logger.warning("[EDGAR] Error for %s: %s", ticker, exc)
                return (ticker, {})

    tasks = [_fetch_one(t) for t in tickers]
    for future in asyncio.as_completed(tasks):
        ticker, data = await future
        results[ticker] = data

    coverage = sum(1 for v in results.values() if v.get("debt_to_equity") is not None or v.get("fcf_margin") is not None)
    logger.info("[EDGAR] Fetched fundamentals: %d/%d tickers with usable data", coverage, len(tickers))
    return results
