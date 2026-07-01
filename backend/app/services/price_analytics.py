"""Client-parity price analytics.

Pure functions that turn a daily (date, close) series into the same display
metrics the iOS ticker screens compute client-side (drawdown window, daily-move
distribution, 52-week range, up/down capture, correlation, relative strength).

The iOS layer (PriceSeriesAnalytics in FinancialHealthAuditView.swift) computes
these on the fly from /prices so they are always fresh. Mirroring the exact same
formulas here lets the backend store server-authoritative copies in
ticker_risk_snapshots.dimension_inputs, so alerts / screening / the morning
digest / the methodology API all read one consistent set of numbers.

Everything is close-based (no OHLCV required) so it works for every ticker that
has a daily close history the moment recompute runs.
"""

from __future__ import annotations

import math
from datetime import date
from typing import Any, Optional

# A daily point is a (calendar-date, close) pair, ordered oldest -> newest.
Point = tuple[date, float]


def _daily_returns(points: list[Point]) -> list[tuple[date, float]]:
    """(date, return) for each day vs the prior close. Prices are > 0 so no skips."""
    out: list[tuple[date, float]] = []
    for i in range(1, len(points)):
        prev = points[i - 1][1]
        if prev <= 0:
            continue
        out.append((points[i][0], (points[i][1] - prev) / prev))
    return out


def _returns_by_day(points: list[Point]) -> dict[date, float]:
    return {d: r for d, r in _daily_returns(points)}


def drawdown_window(
    points: list[Point], *, trailing: int = 252
) -> Optional[dict[str, Any]]:
    """Deepest peak-to-trough fall within the trailing window.

    Mirrors PriceSeriesAnalytics.drawdownWindow: track the running peak, record the
    worst (close - peak)/peak, then report the peak that preceded that trough.
    """
    if len(points) < 3:
        return None
    series = points[-trailing:] if len(points) > trailing else points
    running_peak = series[0][1]
    running_peak_idx = 0
    worst = 0.0
    best_trough = 0
    best_peak_for_trough = 0
    for i, (_d, close) in enumerate(series):
        if close > running_peak:
            running_peak = close
            running_peak_idx = i
        if running_peak > 0:
            dd = (close - running_peak) / running_peak
            if dd < worst:
                worst = dd
                best_trough = i
                best_peak_for_trough = running_peak_idx
    if worst >= 0:
        return None
    peak_idx = best_peak_for_trough
    trough_idx = best_trough
    peak_close = series[peak_idx][1]
    recovered = any(close >= peak_close for _d, close in series[trough_idx:])
    return {
        "peak_date": series[peak_idx][0].isoformat(),
        "peak_close": round(peak_close, 4),
        "trough_date": series[trough_idx][0].isoformat(),
        "trough_close": round(series[trough_idx][1], 4),
        "drawdown_pct": round(worst, 4),  # negative fraction
        "recovered": recovered,
    }


# 7 buckets: <-5%, -5..-3, -3..-1, -1..+1, +1..+3, +3..+5, >+5%.
_BUCKETS: list[tuple[str, bool, bool]] = [
    ("<-5%", True, False),
    ("-5:-3", True, False),
    ("-3:-1", True, False),
    ("-1:+1", False, True),
    ("+1:+3", False, False),
    ("+3:+5", False, False),
    (">+5%", False, False),
]


def _bucket_index(r: float) -> int:
    if r <= -0.05:
        return 0
    if r <= -0.03:
        return 1
    if r <= -0.01:
        return 2
    if r < 0.01:
        return 3
    if r < 0.03:
        return 4
    if r < 0.05:
        return 5
    return 6


def return_distribution(
    points: list[Point], *, trailing: int = 252
) -> Optional[dict[str, Any]]:
    """Histogram of daily % moves + worst/best day over the trailing window."""
    rets = [r for _d, r in _daily_returns(points[-(trailing + 1):])]
    if not rets:
        return None
    counts = [0] * 7
    for r in rets:
        counts[_bucket_index(r)] += 1
    buckets = [
        {"label": lbl, "count": counts[i], "negative": neg, "center": ctr}
        for i, (lbl, neg, ctr) in enumerate(_BUCKETS)
    ]
    return {
        "buckets": buckets,
        "worst_day": round(min(rets), 4),
        "best_day": round(max(rets), 4),
        "days": len(rets),
    }


def range_52w(points: list[Point], *, trailing: int = 252) -> Optional[dict[str, Any]]:
    series = points[-trailing:] if len(points) > trailing else points
    closes = [c for _d, c in series]
    if not closes:
        return None
    low = min(closes)
    high = max(closes)
    last = closes[-1]
    if high <= low:
        return None
    return {
        "low": round(low, 4),
        "high": round(high, 4),
        "last": round(last, 4),
        "fraction": round((last - low) / (high - low), 4),
    }


def capture(
    points: list[Point], benchmark: list[Point], *, trailing: int = 252
) -> Optional[dict[str, Any]]:
    """Up/down capture vs a benchmark, on days common to both series.

    up_capture = sum(asset returns on up-market days) / sum(market returns on up days).
    """
    a = _returns_by_day(points[-(trailing + 1):])
    b = _returns_by_day(benchmark[-(trailing + 1):])
    common = set(a) & set(b)
    if len(common) < 20:
        return None
    up_a = up_b = down_a = down_b = 0.0
    up_n = down_n = 0
    for day in common:
        ar = a[day]
        br = b[day]
        if br > 0:
            up_a += ar
            up_b += br
            up_n += 1
        elif br < 0:
            down_a += ar
            down_b += br
            down_n += 1
    if up_b == 0 or down_b == 0 or up_n == 0 or down_n == 0:
        return None
    return {
        "up_capture": round(up_a / up_b, 4),
        "down_capture": round(down_a / down_b, 4),
        "up_days": up_n,
        "down_days": down_n,
    }


def correlation(
    points: list[Point], other: list[Point], *, trailing: int = 120
) -> Optional[float]:
    """Pearson correlation of daily returns between two aligned series."""
    a = _returns_by_day(points[-(trailing + 1):])
    b = _returns_by_day(other[-(trailing + 1):])
    common = list(set(a) & set(b))
    if len(common) < 20:
        return None
    xs = [a[d] for d in common]
    ys = [b[d] for d in common]
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    num = dx = dy = 0.0
    for i in range(len(xs)):
        a0 = xs[i] - mx
        b0 = ys[i] - my
        num += a0 * b0
        dx += a0 * a0
        dy += b0 * b0
    if dx <= 0 or dy <= 0:
        return None
    return num / (math.sqrt(dx) * math.sqrt(dy))


def percent_change(points: list[Point], *, days: int) -> Optional[float]:
    series = points[-(days + 1):]
    if len(series) < 2:
        return None
    first = series[0][1]
    last = series[-1][1]
    if first <= 0:
        return None
    return (last - first) / first
