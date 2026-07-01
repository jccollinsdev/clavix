"""ETF relative-performance computation for the Sector Strength dimension.

ETFs are funds, not companies — their "strength" is how the fund/sector has
performed against the broad market and against peer sectors, not headline
sentiment. This module fetches multi-year monthly closes and computes trailing
returns vs the S&P 500 plus a monthly relative-strength series for the chart.

Source: stockanalysis.com price history (universal, adjusted closes).
"""
from __future__ import annotations

import logging
from typing import Any

import requests

logger = logging.getLogger(__name__)

HISTORY_URL = "https://stockanalysis.com/api/symbol/{kind}/{ticker}/history?range=5Y&period=Monthly"
BROWSER_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0 Safari/537.36"
    ),
    "Accept": "application/json",
}
MARKET_BENCHMARK = "SPY"
# Sector SPDR family used for the "vs other sectors" rank.
SECTOR_PEERS = ["XLK", "XLF", "XLE", "XLV", "XLI", "XLC", "XLY", "XLP", "XLU", "XLRE", "XLB"]


def fetch_monthly_closes(ticker: str, kind: str = "e") -> list[tuple[str, float]]:
    """Return [(YYYY-MM-DD, adjusted_close), ...] ascending. kind: 'e' ETF, 's' stock."""
    try:
        resp = requests.get(
            HISTORY_URL.format(kind=kind, ticker=ticker.upper()),
            timeout=20,
            headers=BROWSER_HEADERS,
        )
    except Exception as exc:
        logger.warning("history fetch failed for %s: %s", ticker, exc)
        return []
    if resp.status_code != 200:
        return []
    try:
        payload = resp.json() or {}
    except ValueError:
        return []
    data = payload.get("data")
    if isinstance(data, dict):
        data = data.get("data")
    if not isinstance(data, list):
        return []
    out: list[tuple[str, float]] = []
    for row in data:
        t = row.get("t")
        close = row.get("a")
        if close is None:
            close = row.get("c")
        try:
            close = float(close)
        except (TypeError, ValueError):
            continue
        if t and close > 0:
            out.append((str(t)[:10], close))
    out.sort(key=lambda r: r[0])
    return out


def _trailing_return_pct(closes: list[tuple[str, float]], months: int) -> float | None:
    if len(closes) < 2:
        return None
    latest = closes[-1][1]
    if len(closes) > months:
        base = closes[-1 - months][1]
    else:
        base = closes[0][1]  # not enough history — use earliest available
    if base <= 0:
        return None
    return round((latest / base - 1.0) * 100.0, 2)


def _relative_series(
    etf: list[tuple[str, float]], spy: list[tuple[str, float]], points: int = 60
) -> list[list[Any]]:
    """Monthly cumulative outperformance vs SPY, both indexed to 100 at the window
    start. Value = ETF growth index − SPY growth index (percentage points)."""
    spy_map = {d: c for d, c in spy}
    aligned = [(d, c, spy_map[d]) for d, c in etf if d in spy_map]
    if len(aligned) < 2:
        return []
    aligned = aligned[-points:]
    base_etf = aligned[0][1]
    base_spy = aligned[0][2]
    if base_etf <= 0 or base_spy <= 0:
        return []
    series: list[list[Any]] = []
    for d, ec, sc in aligned:
        etf_idx = ec / base_etf * 100.0
        spy_idx = sc / base_spy * 100.0
        series.append([d, round(etf_idx - spy_idx, 2)])
    return series


def compute_performance(
    etf_closes: list[tuple[str, float]], spy_closes: list[tuple[str, float]]
) -> dict[str, Any] | None:
    if len(etf_closes) < 2:
        return None
    perf: dict[str, Any] = {"months_available": len(etf_closes)}
    for label, months in (("1y", 12), ("3y", 36), ("5y", 60)):
        etf_ret = _trailing_return_pct(etf_closes, months)
        spy_ret = _trailing_return_pct(spy_closes, months)
        perf[f"ret_{label}"] = etf_ret
        perf[f"spy_{label}"] = spy_ret
        if etf_ret is not None and spy_ret is not None:
            perf[f"rel_{label}"] = round(etf_ret - spy_ret, 2)
        else:
            perf[f"rel_{label}"] = None
    perf["rel_series"] = _relative_series(etf_closes, spy_closes)
    perf["as_of"] = etf_closes[-1][0]
    return perf


def build_all(tickers: list[str]) -> dict[str, dict[str, Any]]:
    """Compute performance for every ticker vs SPY, plus a sector rank for the
    SPDR sector funds. Returns {ticker: performance_dict}."""
    spy_closes = fetch_monthly_closes(MARKET_BENCHMARK, "e")
    out: dict[str, dict[str, Any]] = {}
    for ticker in tickers:
        closes = fetch_monthly_closes(ticker, "e")
        perf = compute_performance(closes, spy_closes)
        if perf:
            out[ticker.upper()] = perf

    # "vs other sectors" — rank each sector SPDR's 1y return within the family.
    sector_returns = [
        (t, out[t]["ret_1y"])
        for t in SECTOR_PEERS
        if t in out and out[t].get("ret_1y") is not None
    ]
    if sector_returns:
        ranked = sorted(sector_returns, key=lambda r: r[1], reverse=True)
        n = len(ranked)
        for rank, (t, _ret) in enumerate(ranked, start=1):
            out[t]["sector_rank"] = rank
            out[t]["sector_peer_count"] = n
    return out
