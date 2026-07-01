"""Backfill company/fund "About" descriptions from stockanalysis.com.

Powers the About section on the ticker detail screen (stocks: business summary;
ETFs already get their description from the etf_holdings job). One-time backfill
plus a periodic refresh keep the text current. Idempotent: skips tickers that
already have a description unless force=True.
"""
from __future__ import annotations

import html
import logging
import re
import time
from datetime import datetime
from typing import Any

import requests

from app.services.supabase import get_supabase

logger = logging.getLogger(__name__)

# The /profile endpoint returns the FULL business summary (1,000-2,000 chars).
# The older /overview endpoint truncates it to ~550 chars with a trailing "…",
# which is what made the About section clip mid-sentence even after "Read more".
PROFILE_URL = "https://stockanalysis.com/api/symbol/s/{ticker}/profile"
OVERVIEW_URL = "https://stockanalysis.com/api/symbol/s/{ticker}/overview"
BROWSER_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0 Safari/537.36"
    ),
    "Accept": "application/json",
}
REQUEST_SPACING_SECONDS = 0.35

_TAG_RE = re.compile(r"<[^>]+>")
_WS_RE = re.compile(r"[ \t]+")


def _clean_description(raw: Any) -> str:
    """Strip the HTML the /profile description is wrapped in (<p>…</p>) and
    normalise whitespace into plain paragraphs the app can render."""
    text = str(raw or "")
    if not text.strip():
        return ""
    # Turn block/br boundaries into newlines before dropping the rest of the tags.
    text = re.sub(r"(?i)</p\s*>", "\n\n", text)
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = _TAG_RE.sub("", text)
    text = html.unescape(text)
    text = _WS_RE.sub(" ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    lines = [line.strip() for line in text.split("\n")]
    return "\n".join(lines).strip()


def _fetch_json(url: str) -> dict[str, Any] | None:
    try:
        resp = requests.get(url, timeout=20, headers=BROWSER_HEADERS)
    except Exception as exc:
        logger.debug("fetch failed for %s: %s", url, exc)
        return None
    if resp.status_code != 200:
        return None
    try:
        return (resp.json() or {}).get("data") or {}
    except ValueError:
        return None


def _fetch_description(ticker: str) -> str | None:
    # Prefer the full-length /profile description; fall back to the truncated
    # /overview only if the profile endpoint has nothing.
    data = _fetch_json(PROFILE_URL.format(ticker=ticker.upper()))
    desc = _clean_description((data or {}).get("description")) if data else ""
    if not desc:
        data = _fetch_json(OVERVIEW_URL.format(ticker=ticker.upper()))
        desc = _clean_description((data or {}).get("description")) if data else ""
    return desc or None


def run(*, force: bool = False, limit: int | None = None) -> dict[str, Any]:
    supabase = get_supabase()
    query = (
        supabase.table("ticker_metadata")
        .select("ticker,asset_class,description")
        .neq("asset_class", "etf")
    )
    rows = query.execute().data or []
    targets = [
        str(r.get("ticker") or "").upper()
        for r in rows
        if r.get("ticker") and (force or not (r.get("description") or "").strip())
    ]
    targets = sorted(set(targets))
    if limit:
        targets = targets[:limit]

    updated = 0
    missed = 0
    for i, ticker in enumerate(targets):
        desc = _fetch_description(ticker)
        if desc:
            try:
                supabase.table("ticker_metadata").update(
                    {
                        "description": desc,
                        "description_source": "stockanalysis",
                        "description_updated_at": datetime.utcnow().isoformat(),
                    }
                ).eq("ticker", ticker).execute()
                updated += 1
            except Exception as exc:
                logger.warning("description update failed for %s: %s", ticker, exc)
                missed += 1
        else:
            missed += 1
        if (i + 1) % 50 == 0:
            logger.info("[DESC_BACKFILL] %d/%d done (%d updated)", i + 1, len(targets), updated)
        time.sleep(REQUEST_SPACING_SECONDS)

    return {
        "status": "completed",
        "items_processed": len(targets),
        "items_updated": updated,
        "items_missed": missed,
    }


def run_from_env() -> dict[str, Any]:
    return run()
