"""Daily end-of-day price capture for the full active universe.

Historically the `prices` table only stayed fresh for the handful of tickers held by
active users (refreshed on-demand during digests). The broad universe went stale
(no bar in 30 days for ~93% of tickers), which starved reference prices, charts, and
the 14-day backfill. This job captures one daily close per active ticker from Polygon
equity aggregates (entitled on the free tier; options snapshots are not) and writes it
to `prices`, skipping tickers that already have a bar recorded today.

Invoke: python -m app.jobs.run daily_eod_price_capture
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone

from app.services.supabase import get_supabase

logger = logging.getLogger(__name__)


def _today_utc_date() -> str:
    return datetime.now(timezone.utc).date().isoformat()


def _load_active_tickers(supabase) -> list[str]:
    rows = (
        supabase.table("ticker_universe")
        .select("ticker")
        .eq("is_active", True)
        .execute()
        .data
        or []
    )
    return sorted(
        {str(r.get("ticker") or "").strip().upper() for r in rows if r.get("ticker")}
    )


def _tickers_with_bar_today(supabase, today: str) -> set[str]:
    """Tickers that already have a price row recorded today (paginated)."""
    have: set[str] = set()
    page = 0
    page_size = 1000
    while page <= 100:
        rows = (
            supabase.table("prices")
            .select("ticker")
            .gte("recorded_at", f"{today}T00:00:00+00:00")
            .range(page * page_size, page * page_size + page_size - 1)
            .execute()
            .data
            or []
        )
        if not rows:
            break
        for r in rows:
            t = str(r.get("ticker") or "").strip().upper()
            if t:
                have.add(t)
        if len(rows) < page_size:
            break
        page += 1
    return have


def run() -> dict:
    from app.services.polygon import fetch_aggs

    supabase = get_supabase()
    today = _today_utc_date()
    tickers = _load_active_tickers(supabase)
    already = _tickers_with_bar_today(supabase, today)
    pending = [t for t in tickers if t not in already]

    processed = 0
    failed = 0
    skipped = len(already)

    for ticker in pending:
        try:
            bars = fetch_aggs(ticker, days=7)
            if not bars:
                failed += 1
                continue
            last = bars[-1]
            close = last.get("c")
            ts = last.get("t")
            if close is None or ts is None:
                failed += 1
                continue
            recorded_at = (
                datetime.fromtimestamp(ts / 1000, tz=timezone.utc)
                if isinstance(ts, (int, float))
                else datetime.now(timezone.utc)
            )
            supabase.table("prices").insert(
                {
                    "ticker": ticker,
                    "price": close,
                    "recorded_at": recorded_at.isoformat(),
                }
            ).execute()
            processed += 1
        except Exception as exc:  # noqa: BLE001
            failed += 1
            logger.warning("[EOD_PRICE] capture failed for %s: %s", ticker, exc)

    logger.info(
        "[EOD_PRICE] processed=%d skipped(existing)=%d failed=%d of %d active tickers",
        processed,
        skipped,
        failed,
        len(tickers),
    )
    return {
        "status": "completed",
        "items_processed": processed,
        "items_skipped": skipped,
        "items_failed": failed,
        "metadata": {"universe": len(tickers), "captured": processed, "date": today},
    }


def run_from_env() -> dict:
    return run()
