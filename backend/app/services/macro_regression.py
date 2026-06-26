"""Per-ticker macro-exposure regression against REAL macro factors from FRED.

Replaces the previous ETF-proxy basket (TLT/UUP/USO/VIXY) with the actual factors
they stood in for, pulled key-free from FRED:

    spy    -> SP500          (market)        daily % return
    ust10y -> DGS10          (10Y yield)     daily level change (pp)
    credit -> BAMLH0A0HYM2   (HY OAS)        daily level change (pp)
    dxy    -> DTWEXBGS       (broad USD)     daily % return
    vix    -> VIXCLS         (VIX)           daily level change

The macro-exposure SCORE is unit-aware: each factor's contribution to the stock's
daily-return volatility is |beta_i| * stdev(factor_i_change), which is in stock-return
units and therefore comparable across factors. Summed in quadrature this gives the
macro-driven component of the stock's daily vol; more macro-driven vol == more exposed
== lower (worse) macro score. R-squared is reported for honesty but the consumer
(risk_scorer) only trusts the regression score when R-squared >= 0.10.
"""
from __future__ import annotations

import logging
import math
import time
from datetime import datetime, timezone
from typing import Any

logger = logging.getLogger(__name__)

# factor_key -> (FRED series id, change mode). pct for price-like series, diff for
# rate/level-like series where the absolute change is the meaningful signal.
FRED_FACTORS: dict[str, tuple[str, str]] = {
    "spy": ("SP500", "pct"),
    "ust10y": ("DGS10", "diff"),
    "credit": ("BAMLH0A0HYM2", "diff"),
    "dxy": ("DTWEXBGS", "pct"),
    "vix": ("VIXCLS", "diff"),
}
FACTOR_ORDER = ["spy", "ust10y", "credit", "dxy", "vix"]

# Back-compat export: the recompute caller still fetches SPY bars (Polygon) for the
# volatility dimension's beta_to_spy. Macro factors themselves now come from FRED, so
# only SPY needs a Polygon fetch.
FACTOR_TICKERS = {"spy": "SPY"}

_REQUIRED_TRADING_DAYS = 60
_TRAILING_DAYS = 252

# A stock whose daily return is ~2.5%/day macro-explained is at maximum macro exposure
# (score 0); zero macro-driven vol is score 100.
_MACRO_VOL_REFERENCE = 0.025

_FRED_TTL_SECONDS = 6 * 3600
_FRED_CACHE: dict[str, Any] = {"ts": 0.0, "changes": None, "levels": None}


# ── numeric helpers (pure-Python; no numpy dependency) ───────────────────────
def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _stdev(values: list[float]) -> float:
    n = len(values)
    if n < 2:
        return 0.0
    m = _mean(values)
    return math.sqrt(sum((v - m) ** 2 for v in values) / n)


def _solve_linear(A: list[list[float]], b: list[float]) -> list[float]:
    """Gaussian elimination with partial pivoting."""
    n = len(A)
    aug = [A[i][:] + [b[i]] for i in range(n)]
    for col in range(n):
        max_row = max(range(col, n), key=lambda r: abs(aug[r][col]))
        if abs(aug[max_row][col]) < 1e-12:
            continue
        aug[col], aug[max_row] = aug[max_row], aug[col]
        pivot = aug[col][col]
        for j in range(col, n + 1):
            aug[col][j] /= pivot
        for row in range(n):
            if row != col:
                factor = aug[row][col]
                for j in range(col, n + 1):
                    aug[row][j] -= factor * aug[col][j]
    return [aug[i][n] for i in range(n)]


def _ols(X: list[list[float]], y: list[float]) -> tuple[list[float], float]:
    """Centered OLS via normal equations. Returns (coefficients, r_squared)."""
    n = len(y)
    if n < 5 or not X:
        return ([0.0] * len(X[0]) if X else []), 0.0
    p = len(X[0])
    XtX = [[0.0] * p for _ in range(p)]
    Xty = [0.0] * p
    mean_y = _mean(y)
    means_x = [_mean([X[i][j] for i in range(n)]) for j in range(p)]
    for i in range(n):
        for j in range(p):
            x_cent = X[i][j] - means_x[j]
            Xty[j] += x_cent * (y[i] - mean_y)
            for k in range(p):
                XtX[j][k] += x_cent * (X[i][k] - means_x[k])
    beta = _solve_linear(XtX, Xty)
    ss_res = 0.0
    ss_tot = 0.0
    for i in range(n):
        pred = mean_y + sum(beta[j] * (X[i][j] - means_x[j]) for j in range(p))
        ss_res += (y[i] - pred) ** 2
        ss_tot += (y[i] - mean_y) ** 2
    r_sq = 1.0 - (ss_res / ss_tot) if ss_tot > 0 else 0.0
    return beta, max(0.0, min(1.0, r_sq))


# ── series construction ──────────────────────────────────────────────────────
def _iso_day(t: Any) -> str:
    """Normalize a bar timestamp (Polygon epoch-ms or ISO string) to YYYY-MM-DD."""
    if isinstance(t, (int, float)):
        return datetime.fromtimestamp(t / 1000, tz=timezone.utc).strftime("%Y-%m-%d")
    s = str(t)
    if s.isdigit():
        return datetime.fromtimestamp(int(s) / 1000, tz=timezone.utc).strftime("%Y-%m-%d")
    return s[:10]


def _ticker_returns_by_day(ticker_bars: list[dict]) -> list[tuple[str, float]]:
    by_day: dict[str, float] = {}
    for bar in ticker_bars or []:
        close = bar.get("c")
        ts = bar.get("t")
        if close is None or ts is None:
            continue
        try:
            by_day[_iso_day(ts)] = float(close)
        except (TypeError, ValueError):
            continue
    days = sorted(by_day)
    returns: list[tuple[str, float]] = []
    for i in range(1, len(days)):
        prev = by_day[days[i - 1]]
        curr = by_day[days[i]]
        if prev > 0:
            returns.append((days[i], (curr - prev) / prev))
    return returns


def _series_changes(series: list[tuple[str, float]], mode: str) -> list[tuple[str, float]]:
    out: list[tuple[str, float]] = []
    for i in range(1, len(series)):
        d1, v1 = series[i]
        _, v0 = series[i - 1]
        if mode == "pct":
            if v0 == 0:
                continue
            out.append((d1, (v1 - v0) / v0))
        else:  # diff
            out.append((d1, v1 - v0))
    return out


def _load_fred_factors() -> tuple[dict[str, list[tuple[str, float]]] | None, dict[str, float]]:
    """Return (changes_by_factor, latest_levels). changes is None if FRED is unavailable.

    Cached process-wide so a 546-ticker recompute fetches FRED once, not per ticker.
    """
    now = time.monotonic()
    if _FRED_CACHE["changes"] is not None and now - _FRED_CACHE["ts"] < _FRED_TTL_SECONDS:
        return _FRED_CACHE["changes"], _FRED_CACHE["levels"]
    try:
        from app.services.fred import fetch_fred_series
    except Exception:
        return None, {}
    changes: dict[str, list[tuple[str, float]]] = {}
    levels: dict[str, float] = {}
    for key, (series_id, mode) in FRED_FACTORS.items():
        series = fetch_fred_series(series_id)
        if series:
            levels[key] = series[-1][1]
        changes[key] = _series_changes(series, mode)
    if any(len(changes.get(k, [])) < _REQUIRED_TRADING_DAYS for k in FACTOR_ORDER):
        logger.warning(
            "FRED factor data incomplete: %s",
            {k: len(changes.get(k, [])) for k in FACTOR_ORDER},
        )
        return None, levels
    _FRED_CACHE.update({"ts": now, "changes": changes, "levels": levels})
    return changes, levels


# ── public API ───────────────────────────────────────────────────────────────
def run_macro_regression(
    ticker: str,
    ticker_bars: list[dict],
    factor_bars_map: dict[str, list[dict]] | None = None,  # kept for back-compat; unused
    *,
    as_of_date: str | None = None,
) -> dict[str, Any]:
    if as_of_date is None:
        as_of_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    ticker_returns = _ticker_returns_by_day(ticker_bars)
    if len(ticker_returns) < _REQUIRED_TRADING_DAYS:
        return {
            "limited_data": True,
            "trading_days_available": len(ticker_returns),
            "as_of_date": as_of_date,
            "message": "Insufficient trading days for regression",
            "data_source": "fred",
        }

    factor_changes, factor_levels = _load_fred_factors()
    if not factor_changes:
        return {
            "limited_data": True,
            "trading_days_available": len(ticker_returns),
            "as_of_date": as_of_date,
            "message": "FRED macro factor data unavailable",
            "data_source": "fred",
        }

    ticker_map = {d: v for d, v in ticker_returns}
    factor_maps = {k: {d: v for d, v in factor_changes[k]} for k in FACTOR_ORDER}
    common = sorted(
        set(ticker_map).intersection(*(set(factor_maps[k]) for k in FACTOR_ORDER))
    )[-_TRAILING_DAYS:]
    if len(common) < _REQUIRED_TRADING_DAYS:
        return {
            "limited_data": True,
            "trading_days_available": len(common),
            "as_of_date": as_of_date,
            "message": "Insufficient aligned trading days across factors",
            "data_source": "fred",
        }

    X = [[factor_maps[k][d] for k in FACTOR_ORDER] for d in common]
    y = [ticker_map[d] for d in common]
    beta, r_sq = _ols(X, y)
    coefficients = {FACTOR_ORDER[i]: round(beta[i], 6) for i in range(len(FACTOR_ORDER))}

    # Unit-aware sensitivity: each factor's contribution to the stock's daily-return
    # vol, summed in quadrature -> macro-driven daily vol -> 0..100 exposure score.
    contributions: dict[str, float] = {}
    for i, k in enumerate(FACTOR_ORDER):
        col = [row[i] for row in X]
        contributions[k] = round(abs(beta[i]) * _stdev(col), 6)
    macro_vol = math.sqrt(sum(c * c for c in contributions.values()))
    sensitivity_score = round(
        max(0.0, min(100.0, 100.0 * (1.0 - min(1.0, macro_vol / _MACRO_VOL_REFERENCE)))), 1
    )
    top_factor = max(contributions, key=contributions.get) if contributions else None

    return {
        "limited_data": False,
        "coefficients": coefficients,
        "contributions": contributions,
        "macro_daily_vol": round(macro_vol, 6),
        "r_squared": round(r_sq, 4),
        "sensitivity_score": sensitivity_score,
        "top_factor": top_factor,
        "trading_days_used": len(common),
        "as_of_date": as_of_date,
        "data_source": "fred",
        "current_factor_levels": factor_levels,
        "factor_series": {k: sid for k, (sid, _mode) in FRED_FACTORS.items()},
    }


def macro_regression_to_audit_jsonb(result: dict[str, Any]) -> dict[str, Any]:
    return {
        "macro_regression": {
            "coefficients": result.get("coefficients", {}),
            "contributions": result.get("contributions", {}),
            "r_squared": result.get("r_squared"),
            "sensitivity_score": result.get("sensitivity_score"),
            "top_factor": result.get("top_factor"),
            "macro_daily_vol": result.get("macro_daily_vol"),
            "as_of_date": result.get("as_of_date"),
            "trading_days_used": result.get("trading_days_used", 0),
            "limited_data": result.get("limited_data", False),
            "data_source": result.get("data_source", "fred"),
            "factor_series": result.get(
                "factor_series", {k: sid for k, (sid, _m) in FRED_FACTORS.items()}
            ),
            "current_factor_levels": result.get("current_factor_levels", {}),
        }
    }
