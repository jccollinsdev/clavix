"""Federal Reserve Economic Data (FRED) client via the public, key-free CSV download.

FRED's `fredgraph.csv` endpoint serves full daily series with NO API key required, so
this adds a genuinely real macro factor source at $0 with nothing to provision. Used by
the macro-exposure regression and the daily macro regime snapshot to replace the old
ETF proxies (TLT/UUP/USO/VIXY) with the actual factors they were standing in for.
"""
from __future__ import annotations

import csv
import io
import logging
import time
from datetime import datetime, timedelta, timezone

import requests

logger = logging.getLogger(__name__)

FRED_CSV_URL = "https://fred.stlouisfed.org/graph/fredgraph.csv"

# A single keep-alive session for connection reuse. IMPORTANT: do NOT set a custom
# User-Agent. FRED's Akamai edge silently tarpits requests carrying a custom UA from
# this host (confirmed: "clavix-macro/1.0" and browser UAs read-time-out, the default
# python-requests UA succeeds every time).
_SESSION = requests.Session()

# Canonical real macro series IDs (all daily, all key-free on fredgraph.csv).
SERIES = {
    "spx": "SP500",          # S&P 500 index level (market factor)
    "ust10y": "DGS10",       # 10-Year Treasury constant-maturity yield (%)
    "credit": "BAMLH0A0HYM2",# ICE BofA US High Yield OAS (%) — credit risk factor
    "dxy": "DTWEXBGS",       # Broad trade-weighted USD index
    "vix": "VIXCLS",         # CBOE VIX close
    "wti": "DCOILWTICO",     # WTI crude spot ($/bbl)
}


def fetch_fred_series(
    series_id: str, *, lookback_days: int = 470, timeout: int = 15, retries: int = 4
) -> list[tuple[str, float]]:
    """Return [(YYYY-MM-DD, value), ...] ascending for the series. Empty on total failure.

    Retries with backoff over a pooled session: cold-start / tarpit read-timeouts are
    transient and clear within a couple of attempts. Missing observations (FRED emits an
    empty cell or '.') are skipped so the caller sees only real data points.
    """
    start = (datetime.now(timezone.utc).date() - timedelta(days=lookback_days)).isoformat()
    url = f"{FRED_CSV_URL}?id={series_id}&cosd={start}"
    raw = None
    last_exc: Exception | None = None
    for attempt in range(retries):
        try:
            resp = _SESSION.get(url, timeout=timeout)
            resp.raise_for_status()
            raw = resp.text
            break
        except Exception as exc:  # pragma: no cover - network dependent
            last_exc = exc
            time.sleep(1.5 * (attempt + 1))
    if raw is None:
        logger.warning(
            "FRED fetch failed for %s after %d attempts: %s", series_id, retries, last_exc
        )
        return []

    out: list[tuple[str, float]] = []
    reader = csv.reader(io.StringIO(raw))
    next(reader, None)  # header: observation_date,<SERIES_ID>
    for row in reader:
        if len(row) < 2:
            continue
        day, val = row[0].strip(), row[1].strip()
        if not day or not val or val == ".":
            continue
        try:
            out.append((day, float(val)))
        except ValueError:
            continue
    return out


def latest_observation(series: list[tuple[str, float]]) -> tuple[str, float] | None:
    return series[-1] if series else None
