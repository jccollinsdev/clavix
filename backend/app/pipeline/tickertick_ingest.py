"""Tickertick news ingestion pipeline.

Fetches articles from Tickertick API, filters via the existing candidate_ranker,
and stores + LLM-enriches via enrich_and_store_articles_batch. No article scraping
is performed: Tickertick's description field is used as the article body directly.

This module replaces the Finnhub company-news + Google RSS path for the active-ticker
news refresh job, eliminating those non-commercial data source compliance violations.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Any

logger = logging.getLogger(__name__)

# Minimum description word count to qualify for LLM enrichment.
# Matches the 12-word threshold used in enrich_and_store_article for summary status.
_MIN_DESCRIPTION_WORDS = 12


async def ingest_tickertick_for_tickers(
    supabase,
    tickers: list[str],
    *,
    n_per_ticker: int = 200,
    max_concurrency: int = 4,
) -> dict[str, int]:
    """Ingest Tickertick articles for a batch of tickers.

    Fetches from Tickertick API (serially, rate-limited), filters via candidate_ranker,
    then stores + LLM-enriches via the shared enrich_and_store_articles_batch path.
    Tickertick's `description` field is mapped to `body` so the downstream scraper
    is bypassed and every article gets LLM-derived sentiment/TLDR/implications.

    Returns {ticker: articles_stored}.
    """
    from ..services.tickertick import fetch_tickertick_news
    from ..services.news_enrichment import enrich_and_store_articles_batch
    from ..services.candidate_ranker import rank_and_filter_candidates

    if not tickers:
        return {}

    per_ticker = await fetch_tickertick_news(tickers, n=n_per_ticker)

    all_candidates: list[dict[str, Any]] = []
    for t in tickers:
        articles = per_ticker.get(t) or []
        usable = [
            a for a in articles
            if len(str(a.get("body") or "").split()) >= _MIN_DESCRIPTION_WORDS
        ]
        all_candidates.extend(usable)

    if not all_candidates:
        logger.info("[TICKERTICK_INGEST] No usable candidates for %d tickers", len(tickers))
        return {}

    # Use a lower skip threshold than Finnhub since Tickertick articles are pre-tagged
    # to the ticker and less likely to be noise
    filtered = rank_and_filter_candidates(all_candidates, skip_score_below=10.0)
    if not filtered:
        return {}

    logger.info(
        "[TICKERTICK_INGEST] %d candidates → %d after filter for %d tickers",
        len(all_candidates),
        len(filtered),
        len(tickers),
    )

    stored = await enrich_and_store_articles_batch(
        supabase,
        filtered,
        max_concurrency=max_concurrency,
        skip_existing=True,
    )

    results: dict[str, int] = {}
    ticker_set = {t.upper() for t in tickers}
    for article in stored:
        t = str(article.get("ticker") or "").strip().upper()
        if t in ticker_set:
            results[t] = results.get(t, 0) + 1

    stored_count = sum(results.values())
    logger.info(
        "[TICKERTICK_INGEST] Stored %d articles across %d tickers",
        stored_count,
        len(results),
    )
    return results
