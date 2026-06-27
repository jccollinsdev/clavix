"""Read-side helper for upcoming earnings dates.

The `earnings_calendar` table is populated daily by jobs/earnings_calendar.py
and already surfaces as EARN chips on the Today screen. This factors the query
out so the morning digest compiler can cite real, dated catalysts instead of a
vague "upcoming earnings".
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

logger = logging.getLogger(__name__)


def _today_iso() -> str:
    return datetime.now(timezone.utc).date().isoformat()


def fetch_upcoming(supabase, tickers: list[str], *, days: int = 14) -> list[dict]:
    """Return upcoming earnings rows for held tickers within `days`.

    Each row: {ticker, report_date, time_of_day, est_eps, est_revenue}. Sorted
    by report_date ascending. Empty list on any error or no data.
    """
    held = sorted({str(t or "").upper() for t in (tickers or []) if str(t or "").strip()})
    if not held or supabase is None:
        return []
    today = _today_iso()
    horizon = (datetime.now(timezone.utc).date() + timedelta(days=days)).isoformat()
    try:
        rows = (
            supabase.table("earnings_calendar")
            .select("ticker,report_date,time_of_day,est_eps,est_revenue,fiscal_period,source")
            .in_("ticker", held)
            .gte("report_date", today)
            .lte("report_date", horizon)
            .order("report_date")
            .limit(12)
            .execute()
            .data
            or []
        )
    except Exception:
        logger.exception("earnings_calendar fetch_upcoming failed")
        return []
    return rows


_MONTHS = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]


def format_earnings_line(row: dict) -> str:
    """One human line, e.g. 'SMCI: Jul 30 (after close), est EPS 0.62'."""
    ticker = str(row.get("ticker") or "").upper()
    date_text = _format_date(row.get("report_date"))
    tod = str(row.get("time_of_day") or "").strip().lower()
    when = {
        "amc": "after close",
        "after": "after close",
        "after_market": "after close",
        "bmo": "before open",
        "before": "before open",
        "pre_market": "before open",
    }.get(tod, "")
    parts = [f"{ticker}: {date_text}"]
    if when:
        parts[0] += f" ({when})"
    est_eps = row.get("est_eps")
    if est_eps not in (None, ""):
        parts.append(f"est EPS {est_eps}")
    return ", ".join(parts)


def _format_date(value) -> str:
    raw = str(value or "").strip()
    if not raw:
        return "date TBA"
    try:
        d = datetime.fromisoformat(raw[:10]).date()
        return f"{_MONTHS[d.month - 1]} {d.day}"
    except Exception:
        return raw
