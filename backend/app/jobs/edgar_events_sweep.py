"""SEC EDGAR 8-K events daily sweep.

Fetches recent 8-K press releases from EDGAR for all active tickers
and ingests them into shared_ticker_events via the standard LLM enrichment pipeline.

8-K filings are high-signal material events (earnings, guidance, executive changes,
mergers/acquisitions, litigation, debt issuance). They complement the Tickertick
news feed which covers financial journalism but may miss same-day SEC disclosures.

Run: docker exec clavis-backend-1 python -m app.jobs.run edgar_events_sweep
"""
from __future__ import annotations

import asyncio
import logging
import time
from typing import Any

logger = logging.getLogger(__name__)


async def run() -> dict[str, Any]:
    return await _run_async()


async def _run_async() -> dict[str, Any]:
    from app.services.supabase import get_supabase
    from app.services.edgar_client import get_cik, _load_cik_map_sync
    from app.pipeline.edgar_events import fetch_edgar_8k_events
    from app.services.news_enrichment import enrich_and_store_articles_batch
    from app.services.ticker_cache_service import list_active_sp500_tickers

    supabase = get_supabase()
    tickers = list_active_sp500_tickers(supabase)
    total = len(tickers)

    cik_map = _load_cik_map_sync()

    logger.info("[EDGAR_EVENTS] Starting 8-K sweep for %d tickers", total)
    start_ts = time.time()

    BATCH_SIZE = 100
    total_stored = 0

    for i in range(0, total, BATCH_SIZE):
        batch = tickers[i : i + BATCH_SIZE]
        logger.info("[EDGAR_EVENTS] Batch %d: %d tickers", i // BATCH_SIZE + 1, len(batch))
        try:
            articles = await fetch_edgar_8k_events(batch, cik_map, lookback_days=10)
            if articles:
                stored = await enrich_and_store_articles_batch(
                    supabase,
                    articles,
                    max_concurrency=4,
                    skip_existing=True,
                )
                batch_stored = len(stored)
                total_stored += batch_stored
                logger.info("[EDGAR_EVENTS] Stored %d articles for batch %d", batch_stored, i // BATCH_SIZE + 1)
        except Exception as exc:
            logger.error("[EDGAR_EVENTS] Batch %d failed: %s", i // BATCH_SIZE + 1, exc, exc_info=True)

    elapsed = time.time() - start_ts
    logger.info("[EDGAR_EVENTS] Done in %.1f min. Stored %d 8-K events.", elapsed / 60, total_stored)
    return {
        "status": "completed",
        "items_processed": total_stored,
        "metadata": {"total_tickers": total, "elapsed_seconds": round(elapsed)},
    }


async def run_from_env() -> dict:
    return await run()
