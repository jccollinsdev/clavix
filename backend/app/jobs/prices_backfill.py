"""One-time / occasional price-history backfill for the active universe.

Why: the per-ticker recompute reads daily closes from the `prices` table
(persisted-first) and only falls back to rate-limited Polygon aggs when a ticker
has < ~60 stored days. Tickers thin on history therefore drag the recompute back
to the Polygon throttle. This job backfills history efficiently using Polygon's
GROUPED-DAILY endpoint (one request returns the whole market for a date), so a few
months of history for all 546 tickers costs ~1 call per trading day instead of one
call per ticker.

Idempotent: existing (ticker, date) closes are skipped, so it is safe to re-run.

Invoke: python -m app.jobs.run prices_history_backfill
Env: PRICES_BACKFILL_DAYS (calendar days back, default 200).
"""
from __future__ import annotations

import logging
import os
import time
from datetime import datetime, timedelta, timezone

from app.services.polygon import fetch_grouped_daily
from app.services.supabase import get_supabase
from app.services.ticker_cache_service import list_active_sp500_tickers

logger = logging.getLogger(__name__)

_INSERT_BATCH = 500


def _existing_ticker_days(supabase, tickers: set[str], since_iso: str) -> set[tuple[str, str]]:
    """Set of (ticker, YYYY-MM-DD) already present in prices since `since_iso`."""
    seen: set[tuple[str, str]] = set()
    page = 0
    page_size = 1000
    while page <= 200:
        rows = (
            supabase.table("prices")
            .select("ticker,recorded_at")
            .gte("recorded_at", since_iso)
            .range(page * page_size, page * page_size + page_size - 1)
            .execute()
            .data
            or []
        )
        if not rows:
            break
        for r in rows:
            t = str(r.get("ticker") or "").upper()
            ra = str(r.get("recorded_at") or "")[:10]
            if t in tickers and ra:
                seen.add((t, ra))
        if len(rows) < page_size:
            break
        page += 1
    return seen


def run(*, days_back: int | None = None) -> dict:
    supabase = get_supabase()
    days_back = days_back or int(os.getenv("PRICES_BACKFILL_DAYS", "200"))
    universe = {t.upper() for t in list_active_sp500_tickers(supabase)}
    if not universe:
        return {"status": "failed", "items_failed": 1, "metadata": {"error": "no universe"}}

    today = datetime.now(timezone.utc).date()
    since_iso = (today - timedelta(days=days_back + 5)).isoformat()
    existing = _existing_ticker_days(supabase, universe, since_iso)
    logger.info(
        "prices_backfill: %d universe tickers, %d existing (ticker,day) pairs in window",
        len(universe), len(existing),
    )

    pending: list[dict] = []
    inserted = 0
    trading_days = 0
    empty_days = 0

    # Self-pace to ~Polygon's free 5/min (this job bypasses the global limiter).
    call_spacing = float(os.getenv("PRICES_BACKFILL_CALL_SPACING", "12"))
    first_call = True

    for offset in range(1, days_back + 1):
        day = today - timedelta(days=offset)
        if day.weekday() >= 5:  # skip weekends (no grouped data)
            continue
        day_iso = day.isoformat()
        if not first_call:
            time.sleep(call_spacing)
        first_call = False
        results = fetch_grouped_daily(day_iso)
        if not results:
            empty_days += 1
            continue
        trading_days += 1
        recorded_at = f"{day_iso}T00:00:00+00:00"
        for item in results:
            ticker = str(item.get("T") or "").upper()
            close = item.get("c")
            if ticker not in universe or close is None:
                continue
            if (ticker, day_iso) in existing:
                continue
            existing.add((ticker, day_iso))
            pending.append({"ticker": ticker, "price": float(close), "recorded_at": recorded_at})
        # Flush in batches to bound memory on the 2 GB host.
        while len(pending) >= _INSERT_BATCH:
            chunk, pending = pending[:_INSERT_BATCH], pending[_INSERT_BATCH:]
            try:
                supabase.table("prices").insert(chunk).execute()
                inserted += len(chunk)
            except Exception as exc:
                logger.warning("prices_backfill: insert batch failed: %s", exc)

    if pending:
        try:
            supabase.table("prices").insert(pending).execute()
            inserted += len(pending)
        except Exception as exc:
            logger.warning("prices_backfill: final insert failed: %s", exc)

    logger.info(
        "prices_backfill: inserted %d closes across %d trading days (%d empty days)",
        inserted, trading_days, empty_days,
    )
    return {
        "status": "completed",
        "items_processed": inserted,
        "metadata": {
            "trading_days": trading_days,
            "empty_days": empty_days,
            "universe": len(universe),
            "days_back": days_back,
        },
    }


def run_from_env() -> dict:
    return run()
