"""
Re-enrich shared_ticker_events rows that are missing key content fields.

Targets articles where:
  - key_implications is NULL or empty []
  - AND tldr is present (meaning the LLM was called before key_implications
    was added to the schema, so implications were never generated)
  - AND body has real content (not paywalled/navigation/failed)

Also targets articles where:
  - tldr is NULL but body has real content (LLM call simply didn't complete)

Usage (on VPS):
  docker exec clavis-backend-1 python -m app.scripts.backfill_news_enrichment
  docker exec clavis-backend-1 python -m app.scripts.backfill_news_enrichment --dry-run
  docker exec clavis-backend-1 python -m app.scripts.backfill_news_enrichment --limit 20
"""
from __future__ import annotations

import argparse
import asyncio
import logging
import sys

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

_BAD_BODY_PREFIXES = ("[Paywalled]", "[No body extracted]", "[Blocked]", "[Navigation only]")


def _needs_enrichment(row: dict) -> bool:
    body = str(row.get("body") or "")
    if any(body.startswith(prefix) for prefix in _BAD_BODY_PREFIXES):
        return False
    if len(body.split()) < 40:
        return False
    tldr = str(row.get("tldr") or "").strip()
    ki = row.get("key_implications")
    ki_missing = ki is None or (isinstance(ki, list) and len(ki) == 0)
    return not tldr or ki_missing


async def run(*, dry_run: bool = False, limit: int | None = None) -> None:
    from app.services.supabase import get_supabase
    from app.services.news_enrichment import enrich_and_store_article

    supabase = get_supabase()

    query = (
        supabase.table("shared_ticker_events")
        .select(
            "id,ticker,title,summary,source,source_url,published_at,"
            "body,tldr,what_it_means,key_implications,sentiment_score,"
            "sentiment_reason,impact_tag,extraction_status,event_type"
        )
        .order("published_at", desc=True)
    )
    if limit:
        query = query.limit(limit * 4)  # fetch extra to account for filtering
    rows = query.execute().data or []

    candidates = [r for r in rows if _needs_enrichment(r)]
    if limit:
        candidates = candidates[:limit]

    logger.info("Found %d articles needing enrichment (of %d fetched)", len(candidates), len(rows))

    if dry_run:
        for row in candidates[:10]:
            tldr = str(row.get("tldr") or "")[:60]
            ki = row.get("key_implications")
            logger.info(
                "  [DRY RUN] %s | %s | tldr=%r ki_count=%s",
                row.get("ticker"),
                str(row.get("title") or "")[:50],
                tldr or "(missing)",
                len(ki) if isinstance(ki, list) else "null",
            )
        return

    success = 0
    failed = 0
    for i, row in enumerate(candidates):
        ticker = str(row.get("ticker") or "").upper()
        title = str(row.get("title") or "")[:60]
        try:
            article = {
                "ticker": ticker,
                "title": row.get("title"),
                "summary": row.get("summary"),
                "source": row.get("source"),
                "url": row.get("source_url"),
                "source_url": row.get("source_url"),
                "published_at": row.get("published_at"),
                "body": row.get("body"),
                "event_type": row.get("event_type"),
            }
            result = await enrich_and_store_article(supabase, article, skip_existing=False)
            if result:
                success += 1
                logger.info("[%d/%d] ✓ %s | %s", i + 1, len(candidates), ticker, title)
            else:
                logger.warning("[%d/%d] – skipped %s | %s", i + 1, len(candidates), ticker, title)
        except Exception as exc:
            failed += 1
            logger.error("[%d/%d] ✗ %s | %s — %s", i + 1, len(candidates), ticker, title, exc)

        # Gentle rate limiting — avoid hammering Minimax
        await asyncio.sleep(0.5)

    logger.info("Done: %d enriched, %d failed of %d candidates", success, failed, len(candidates))


def main() -> None:
    parser = argparse.ArgumentParser(description="Backfill missing news enrichment fields")
    parser.add_argument("--dry-run", action="store_true", help="Print candidates without re-enriching")
    parser.add_argument("--limit", type=int, default=None, help="Max articles to process")
    args = parser.parse_args()
    asyncio.run(run(dry_run=args.dry_run, limit=args.limit))


if __name__ == "__main__":
    main()
