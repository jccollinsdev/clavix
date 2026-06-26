"""Tickertick full-universe news sweep.

Fetches news from Tickertick for ALL active tickers in the universe,
storing + LLM-enriching articles via the standard pipeline. Designed for
the initial data population after migrating from Finnhub/Google RSS.

Run via: docker exec clavis-backend-1 python -m app.jobs.run tickertick_news_sweep

Rate limit: 5 req/30s = 6.2s per ticker. At 546 tickers this takes ~57 minutes.
The in-process 4h news refresh handles subsequent incremental updates; this is a
one-time or on-demand full sweep.
"""
from __future__ import annotations

import asyncio
import logging
import time
from typing import Any

logger = logging.getLogger(__name__)

# Process in batches to log progress without blocking the full sweep
BATCH_SIZE = 50


async def run() -> dict[str, Any]:
    return await _run_async()


async def _run_async() -> dict[str, Any]:
    from app.services.supabase import get_supabase
    from app.services.ticker_cache_service import list_active_sp500_tickers
    from app.pipeline.tickertick_ingest import ingest_tickertick_for_tickers

    supabase = get_supabase()
    tickers = list_active_sp500_tickers(supabase)
    total = len(tickers)

    logger.info("[TICKERTICK_SWEEP] Starting full-universe sweep: %d tickers", total)
    start_ts = time.time()

    all_results: dict[str, int] = {}
    total_stored = 0
    failed_batches: list[str] = []

    for i in range(0, total, BATCH_SIZE):
        batch = tickers[i : i + BATCH_SIZE]
        batch_num = i // BATCH_SIZE + 1
        logger.info(
            "[TICKERTICK_SWEEP] Batch %d/%d: fetching %d tickers (%s ... %s)",
            batch_num,
            (total + BATCH_SIZE - 1) // BATCH_SIZE,
            len(batch),
            batch[0],
            batch[-1],
        )
        try:
            results = await ingest_tickertick_for_tickers(
                supabase,
                batch,
                n_per_ticker=200,
                max_concurrency=4,
            )
            all_results.update(results)
            batch_stored = sum(results.values())
            total_stored += batch_stored
            logger.info(
                "[TICKERTICK_SWEEP] Batch %d done: %d articles stored (%d tickers got >0)",
                batch_num, batch_stored, sum(1 for v in results.values() if v > 0),
            )
        except Exception as exc:
            logger.error("[TICKERTICK_SWEEP] Batch %d failed: %s", batch_num, exc, exc_info=True)
            failed_batches.extend(batch)

    elapsed = time.time() - start_ts
    tickers_with_articles = sum(1 for v in all_results.values() if v > 0)

    logger.info(
        "[TICKERTICK_SWEEP] Complete in %.1f min. Stored %d articles for %d/%d tickers. Batches failed: %d",
        elapsed / 60,
        total_stored,
        tickers_with_articles,
        total,
        len(failed_batches) // BATCH_SIZE,
    )

    return {
        "status": "completed" if not failed_batches else "partial",
        "items_processed": tickers_with_articles,
        "items_failed": len(failed_batches),
        "metadata": {
            "total_tickers": total,
            "articles_stored": total_stored,
            "elapsed_seconds": round(elapsed),
            "failed_tickers": failed_batches[:25],
        },
    }


async def run_from_env() -> dict:
    return await run()
