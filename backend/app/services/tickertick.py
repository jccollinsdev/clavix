"""Tickertick news API client.

Tickertick is a free news aggregator with a commercially permissive license.
URL: https://api.tickertick.com/feed?q=tt:{TICKER}&n=200
Rate limit: <=5 requests per 30 seconds. Exceeding it triggers a 30-second IP ban.
We pace at 6.2 seconds per request to stay safely under the limit.
"""
from __future__ import annotations

import asyncio
import logging
import time
from datetime import datetime, timezone
from typing import Any

import httpx

logger = logging.getLogger(__name__)

TICKERTICK_BASE_URL = "https://api.tickertick.com/feed"
_TICKERTICK_MIN_CALL_INTERVAL = 6.2  # 5 req/30s safe pacing
_last_call_ts: float = 0.0


def _to_iso(ms_epoch: Any) -> str | None:
    if ms_epoch is None:
        return None
    try:
        return datetime.fromtimestamp(float(ms_epoch) / 1000.0, tz=timezone.utc).isoformat()
    except (TypeError, ValueError, OSError):
        return None


def _parse_article(item: dict[str, Any], ticker: str) -> dict[str, Any]:
    """Map a Tickertick feed item to the shared article candidate format.

    Tickertick's `description` field maps directly to `body` so the downstream
    article scraper is bypassed entirely. The pipeline will use `extraction_status=summary`
    and proceed to LLM enrichment as normal.
    """
    description = str(item.get("description") or "").strip()
    title = str(item.get("title") or "").strip()
    url = str(item.get("url") or "").strip()
    site = str(item.get("site") or "").strip()

    return {
        "id": str(item.get("id") or url),
        "title": title,
        "url": url,
        "source_url": url,
        "source": site,
        "published_at": _to_iso(item.get("time")),
        "summary": description,
        "body": description,
        "ticker": ticker.upper(),
        "source_type": "tickertick",
        "tags": list(item.get("tags") or []),
        "provider_tickers": [str(t).upper() for t in (item.get("tickers") or [])],
    }


async def fetch_tickertick_news(
    tickers: list[str],
    *,
    n: int = 200,
) -> dict[str, list[dict[str, Any]]]:
    """Fetch Tickertick news for a list of tickers with safe rate pacing.

    Returns {ticker: [article_candidate, ...]} where each article has
    `body` pre-populated from the Tickertick description field.
    Articles with no description (< 12 words) are excluded at the caller.
    """
    global _last_call_ts

    results: dict[str, list[dict[str, Any]]] = {}
    if not tickers:
        return results

    async with httpx.AsyncClient(timeout=20.0, follow_redirects=True) as client:
        for idx, ticker in enumerate(tickers):
            # Enforce <=5 req/30s by spacing calls by at least 6.2 seconds
            if idx > 0:
                now = time.monotonic()
                wait = _TICKERTICK_MIN_CALL_INTERVAL - (now - _last_call_ts)
                if wait > 0:
                    await asyncio.sleep(wait)

            try:
                url = f"{TICKERTICK_BASE_URL}?q=tt:{ticker.upper()}&n={n}"
                _last_call_ts = time.monotonic()
                resp = await client.get(
                    url,
                    headers={"User-Agent": "Mozilla/5.0 (compatible; Clavix/1.0)"},
                )

                if resp.status_code == 429:
                    logger.warning("[TICKERTICK] Rate limited on %s, sleeping 35s", ticker)
                    await asyncio.sleep(35)
                    _last_call_ts = time.monotonic()
                    resp = await client.get(
                        url,
                        headers={"User-Agent": "Mozilla/5.0 (compatible; Clavix/1.0)"},
                    )

                if resp.status_code != 200:
                    logger.warning("[TICKERTICK] HTTP %d for %s", resp.status_code, ticker)
                    results[ticker] = []
                    continue

                data = resp.json()
                # Tickertick API returns "stories" key (not "feed")
                feed = data.get("stories") or data.get("feed") or []
                articles = [
                    _parse_article(item, ticker)
                    for item in feed
                    if item.get("title") and item.get("url")
                ]
                results[ticker] = articles
                if idx % 50 == 0 and idx > 0:
                    logger.info("[TICKERTICK] Progress: %d/%d tickers fetched", idx, len(tickers))

            except Exception as exc:
                logger.warning("[TICKERTICK] Error fetching %s: %s", ticker, exc)
                results[ticker] = []

    total = sum(len(v) for v in results.values())
    logger.info("[TICKERTICK] Fetched %d articles for %d/%d tickers", total, len(results), len(tickers))
    return results
