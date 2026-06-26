"""SEC EDGAR fundamentals sweep — weekly refresh of financial health inputs.

Replaces the Finnhub-based fundamentals_sweep with EDGAR XBRL data, which is:
- Commercially licensed (US government public domain, unrestricted commercial use)
- Primary source (as-reported 10-K/10-Q filings, not aggregated third-party data)
- Free, no rate-limit issues for our 546-ticker universe

For tickers where EDGAR has no data (rare in S&P 500), falls back to existing
Finnhub data already in ticker_metadata rather than blanking the field.

Run via: docker exec clavis-backend-1 python -m app.jobs.run edgar_fundamentals_sweep

MANDATORY: User-Agent must be descriptive with contact email or EDGAR blocks the IP.
"""
from __future__ import annotations

import asyncio
import logging
import time
from typing import Any

logger = logging.getLogger(__name__)

BATCH_SIZE = 50


def run() -> dict[str, Any]:
    return asyncio.run(_run_async())


async def _run_async() -> dict[str, Any]:
    from app.services.supabase import get_supabase
    from app.services.edgar_client import fetch_edgar_fundamentals_async
    from app.services.ticker_cache_service import list_active_sp500_tickers

    supabase = get_supabase()
    tickers = list_active_sp500_tickers(supabase)
    total = len(tickers)

    logger.info("[EDGAR_SWEEP] Starting fundamentals sweep for %d tickers", total)
    start_ts = time.time()

    updated = 0
    skipped = 0
    failed = 0

    for i in range(0, total, BATCH_SIZE):
        batch = tickers[i : i + BATCH_SIZE]
        logger.info("[EDGAR_SWEEP] Batch %d/%d: %d tickers",
                    i // BATCH_SIZE + 1, (total + BATCH_SIZE - 1) // BATCH_SIZE, len(batch))
        try:
            results = await fetch_edgar_fundamentals_async(batch, max_concurrency=4)

            for ticker, fundamentals in results.items():
                if not fundamentals or fundamentals.get("limited_data"):
                    skipped += 1
                    continue
                try:
                    update_payload: dict[str, Any] = {}
                    for field in ("debt_to_equity", "fcf_margin", "current_ratio", "revenue_growth_trend"):
                        val = fundamentals.get(field)
                        if val is not None:
                            update_payload[field] = val

                    if not update_payload:
                        skipped += 1
                        continue

                    update_payload["fundamentals_updated_at"] = (
                        __import__("datetime").datetime.now(
                            __import__("datetime").timezone.utc
                        ).isoformat()
                    )
                    update_payload["fundamentals_source"] = "edgar"

                    supabase.table("ticker_metadata").update(update_payload).eq(
                        "ticker", ticker
                    ).execute()
                    updated += 1
                except Exception as exc:
                    logger.warning("[EDGAR_SWEEP] Failed to upsert %s: %s", ticker, exc)
                    failed += 1
        except Exception as exc:
            logger.error("[EDGAR_SWEEP] Batch failed: %s", exc, exc_info=True)
            failed += len(batch)

    elapsed = time.time() - start_ts
    logger.info(
        "[EDGAR_SWEEP] Done in %.1f min. updated=%d skipped=%d failed=%d",
        elapsed / 60, updated, skipped, failed,
    )
    return {
        "status": "completed" if failed == 0 else "partial",
        "items_processed": updated,
        "items_skipped": skipped,
        "items_failed": failed,
        "metadata": {"total_tickers": total, "elapsed_seconds": round(elapsed)},
    }


def run_from_env() -> dict:
    return run()
