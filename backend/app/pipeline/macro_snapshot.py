"""Daily macro factor snapshot job.

Captures daily levels of the REAL macro factors that CLAVIX_TRUTH §6 uses for the
Macro Exposure dimension and the digest "Overnight Macro" prose, pulled key-free
from FRED (replaces the old TLT/UUP/USO/VIXY ETF proxies):

- DGS10        → 10-Year Treasury yield (%)
- BAMLH0A0HYM2 → ICE BofA US High Yield OAS (%), the credit-risk factor
- DTWEXBGS     → broad trade-weighted USD index
- VIXCLS       → CBOE VIX close
- DCOILWTICO   → WTI crude spot ($/bbl)
- SP500        → S&P 500 index level (market reference)

Writes one row per (as_of_date) into `macro_regime_snapshots` with
data_status='real_factors'. Falls back to a price-only row from Polygon SPY/VIX
proxies only if FRED is unavailable.

Usage:
    from app.pipeline.macro_snapshot import refresh_macro_snapshot
    refresh_macro_snapshot()
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from ..services.fred import SERIES as FRED_SERIES, fetch_fred_series
from ..services.polygon import fetch_aggs
from ..services.supabase import get_supabase

logger = logging.getLogger(__name__)


def _fred_level_and_change(
    series_id: str,
) -> tuple[float | None, float | None, float | None, str | None]:
    """Return (latest_level, day_level_change, day_pct_change, observation_date)."""
    series = fetch_fred_series(series_id, lookback_days=20)
    if not series:
        return (None, None, None, None)
    obs_date, level = series[-1]
    prev = series[-2][1] if len(series) >= 2 else level
    try:
        amount = float(level) - float(prev)
        pct = (amount / float(prev)) * 100.0 if prev else None
    except (TypeError, ValueError):
        amount, pct = None, None
    return (float(level), amount, pct, obs_date)


def _regime_from_signals(spy_pct: float | None, vix_close: float | None) -> str:
    """Cheap heuristic regime label until a richer classifier ships."""
    if spy_pct is None or vix_close is None:
        return "unknown"
    if vix_close > 25 and spy_pct < -1.0:
        return "risk_off"
    if vix_close < 15 and spy_pct >= 0:
        return "risk_on"
    return "neutral"


def _rates_signal(change: float | None) -> str | None:
    if change is None:
        return None
    if change > 0.03:
        return "rising"
    if change < -0.03:
        return "falling"
    return "stable"


def _credit_signal(day_change: float | None) -> str | None:
    """Map the day-over-day HY OAS move to the allowed enum (widening == tightening)."""
    if day_change is None:
        return None
    if day_change > 0.05:
        return "tightening"
    if day_change < -0.05:
        return "easing"
    return "stable"


def refresh_macro_snapshot() -> bool:
    """Pull real FRED macro levels and upsert today's `macro_regime_snapshots` row."""
    supabase = get_supabase()

    values: dict[str, tuple[float | None, float | None, float | None, str | None]] = {}
    snapshot_date: str | None = None
    for code in ("spx", "ust10y", "credit", "dxy", "vix", "wti"):
        try:
            level, amount, pct, dt = _fred_level_and_change(FRED_SERIES[code])
            values[code] = (level, amount, pct, dt)
            if dt and snapshot_date is None and code in ("spx", "ust10y"):
                snapshot_date = dt
        except Exception:
            logger.exception("Failed to pull FRED series for %s", code)
            values[code] = (None, None, None, None)

    # Require the two anchor factors (market + rates) to call this real.
    have_real = values.get("spx", (None,))[0] is not None and values.get("ust10y", (None,))[0] is not None
    if not have_real:
        return _refresh_macro_snapshot_price_only(supabase)

    snapshot_date = snapshot_date or datetime.now(timezone.utc).date().isoformat()
    spy_pct = values["spx"][2]
    vix_close = values["vix"][0]
    regime = _regime_from_signals(spy_pct, vix_close)
    if regime == "unknown":  # not an allowed regime_state enum value
        regime = "neutral"

    row = {
        "as_of_date":         snapshot_date,
        "regime_state":       regime,
        "vix_level":          values["vix"][0],
        "vix_day_change":     values["vix"][1],
        "ust10y_level":       values["ust10y"][0],
        "ust10y_day_change":  values["ust10y"][1],
        "dxy_level":          values["dxy"][0],
        "dxy_day_change":     values["dxy"][1],
        "wti_level":          values["wti"][0],
        "wti_day_change":     values["wti"][1],
        "spy_close":          values["spx"][0],
        "spy_day_change_pct": values["spx"][2],
        "credit_spread_level": values["credit"][0],
        "rates_signal":       _rates_signal(values["ust10y"][1]),
        "credit_signal":      _credit_signal(values["credit"][1]),
        "generated_at":       datetime.now(timezone.utc).isoformat(),
        "data_status":        "real_factors",
    }

    existing = (
        supabase.table("macro_regime_snapshots")
        .select("id")
        .eq("as_of_date", snapshot_date)
        .limit(1)
        .execute()
        .data
    )
    try:
        if existing:
            supabase.table("macro_regime_snapshots") \
                .update(row) \
                .eq("id", existing[0]["id"]) \
                .execute()
        else:
            supabase.table("macro_regime_snapshots").insert(row).execute()
    except Exception:
        logger.exception("Failed to write macro snapshot for %s", snapshot_date)
        return False
    logger.info("refresh_macro_snapshot wrote REAL row for %s (regime=%s)", snapshot_date, regime)
    return True


def _polygon_close_change(ticker: str) -> tuple[float | None, float | None, float | None, str | None]:
    bars = fetch_aggs(ticker, days=7) or []
    if not bars:
        return (None, None, None, None)
    latest = bars[-1]
    prior = bars[-2] if len(bars) >= 2 else bars[-1]
    close, prev_close = latest.get("c"), prior.get("c")
    try:
        amount = float(close) - float(prev_close)
        pct = (amount / float(prev_close)) * 100.0 if prev_close else None
    except (TypeError, ValueError):
        amount, pct = None, None
    ts = latest.get("t")
    dt = (
        datetime.fromtimestamp(ts / 1000, tz=timezone.utc).date().isoformat()
        if isinstance(ts, int)
        else datetime.now(timezone.utc).date().isoformat()
    )
    return (close, amount, pct, dt)


def _refresh_macro_snapshot_price_only(supabase) -> bool:
    """Fallback when FRED is unreachable: a price-only row from Polygon SPY/VIX."""
    spy_close, _spy_amt, spy_pct, dt = _polygon_close_change("SPY")
    vix_close, vix_amt, _vix_pct, _ = _polygon_close_change("VIXY")
    if dt is None:
        logger.warning("Macro snapshot: FRED and Polygon both unavailable; aborting")
        return False
    row = {
        "as_of_date":         dt,
        "regime_state":       _regime_from_signals(spy_pct, vix_close),
        "vix_level":          vix_close,
        "vix_day_change":     vix_amt,
        "spy_close":          spy_close,
        "spy_day_change_pct": spy_pct,
        "generated_at":       datetime.now(timezone.utc).isoformat(),
        "data_status":        "price_only",
    }
    try:
        existing = (
            supabase.table("macro_regime_snapshots")
            .select("id").eq("as_of_date", dt).limit(1).execute().data
        )
        if existing:
            supabase.table("macro_regime_snapshots").update(row).eq("id", existing[0]["id"]).execute()
        else:
            supabase.table("macro_regime_snapshots").insert(row).execute()
    except Exception:
        logger.exception("Failed to write price-only macro snapshot for %s", dt)
        return False
    logger.warning("refresh_macro_snapshot wrote PRICE-ONLY row for %s (FRED unavailable)", dt)
    return True
