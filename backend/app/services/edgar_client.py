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
    fcf_margin: float | None = None
    op_cf = _get("NetCashProvidedByUsedInOperatingActivities")
    capex_raw = _get("PaymentsToAcquirePropertyPlantAndEquipment")
    revenues = _get("Revenues") or _get("RevenueFromContractWithCustomerExcludingAssessedTax")
    if op_cf is not None and capex_raw is not None and revenues is not None and revenues > 0:
        fcf = op_cf - capex_raw
        fcf_margin = round(fcf / revenues, 4)
    elif op_cf is not None and revenues is not None and revenues > 0:
        fcf_margin = round(op_cf / revenues, 4)

    # ── Current ratio ─────────────────────────────────────────────────────────
    current_ratio: float | None = None
    current_assets = _get("AssetsCurrent")
    current_liabilities = _get("LiabilitiesCurrent")
    if current_assets is not None and current_liabilities is not None and current_liabilities > 0:
        current_ratio = round(current_assets / current_liabilities, 4)

    # ── Revenue growth trend ──────────────────────────────────────────────────
    revenue_growth_trend: str | None = None
    if revenues is not None:
        try:
            us_gaap = (facts.get("facts") or {}).get("us-gaap") or {}
            rev_data = us_gaap.get("Revenues") or us_gaap.get("RevenueFromContractWithCustomerExcludingAssessedTax") or {}
            annual_rows = sorted(
                [
                    r for r in (rev_data.get("units") or {}).get("USD", [])
                    if r.get("form") in ("10-K", "10-K/A") and r.get("val") and r.get("end")
                ],
                key=lambda r: r["end"],
                reverse=True,
            )
            if len(annual_rows) >= 2:
                latest_rev = float(annual_rows[0]["val"])
                prior_rev = float(annual_rows[1]["val"])
                if prior_rev > 0:
                    yoy_growth = (latest_rev - prior_rev) / prior_rev
                    if yoy_growth > 0.10:
                        revenue_growth_trend = "strong"
                    elif yoy_growth > 0.03:
                        revenue_growth_trend = "moderate"
                    elif yoy_growth > -0.02:
                        revenue_growth_trend = "flat"
                    else:
                        revenue_growth_trend = "declining"
        except Exception:
            pass

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
