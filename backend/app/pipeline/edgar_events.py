"""SEC EDGAR 8-K and press-release event signal.

Fetches recent 8-K filings (material corporate events: earnings, guidance,
executive changes, mergers, litigation) from EDGAR's free full-text search API.
Extracts EX-99.1 press-release exhibits and maps them to the shared article
candidate format so they feed into the news sentiment dimension via the standard
LLM enrichment pipeline.

Commercial license: US government public domain, unrestricted commercial use.
User-Agent header is mandatory; missing/generic UAs get rate-limited or blocked.
"""
from __future__ import annotations

import asyncio
import logging
import re
import time
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx

logger = logging.getLogger(__name__)

EDGAR_USER_AGENT = "Clavix support@getclavix.com"
_HEADERS = {"User-Agent": EDGAR_USER_AGENT, "Accept": "application/json"}

# Full-text search for 8-K filings by ticker mention
EDGAR_EFTS_URL = (
    "https://efts.sec.gov/LATEST/search-index?q=%22{ticker}%22"
    "&dateRange=custom&startdt={start}&enddt={end}&forms=8-K&hits.hits._source=period_of_report"
)

# Filing index for a given accession number
EDGAR_FILING_INDEX_URL = "https://www.sec.gov/Archives/edgar/data/{cik}/{acc_nodash}/{acc_nodash}-index.json"

EDGAR_CONTENT_BASE = "https://www.sec.gov/Archives/edgar/data/{cik}/{acc_nodash}/{filename}"

_MIN_CALL_INTERVAL = 0.15  # ~6 req/sec, below EDGAR's 10/s limit
_last_call: float = 0.0


def _acc_nodash(accn: str) -> str:
    return accn.replace("-", "")


async def _get_json(client: httpx.AsyncClient, url: str) -> dict | None:
    global _last_call
    now = time.monotonic()
    wait = _MIN_CALL_INTERVAL - (now - _last_call)
    if wait > 0:
        await asyncio.sleep(wait)
    _last_call = time.monotonic()
    try:
        resp = await client.get(url, headers=_HEADERS, timeout=20.0)
        if resp.status_code == 200:
            return resp.json()
        return None
    except Exception:
        return None


async def _get_text(client: httpx.AsyncClient, url: str) -> str | None:
    global _last_call
    now = time.monotonic()
    wait = _MIN_CALL_INTERVAL - (now - _last_call)
    if wait > 0:
        await asyncio.sleep(wait)
    _last_call = time.monotonic()
    try:
        resp = await client.get(url, headers={**_HEADERS, "Accept": "text/html,text/plain"}, timeout=20.0)
        if resp.status_code == 200:
            return resp.text[:8000]  # cap at 8000 chars for LLM input
        return None
    except Exception:
        return None


def _strip_html(text: str) -> str:
    """Basic HTML tag removal for exhibit text."""
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"&nbsp;", " ", text)
    text = re.sub(r"&amp;", "&", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()[:4000]


async def fetch_edgar_8k_events(
    tickers: list[str],
    cik_map: dict[str, str],
    *,
    lookback_days: int = 7,
) -> list[dict[str, Any]]:
    """Fetch recent 8-K events from EDGAR for a list of tickers.

    Returns a list of article candidates in the shared format (body pre-populated
    from exhibit text or filing summary). Suitable for enrich_and_store_articles_batch.
    """
    end = datetime.now(timezone.utc).date()
    start = end - timedelta(days=lookback_days)
    start_str = start.isoformat()
    end_str = end.isoformat()

    all_articles: list[dict[str, Any]] = []

    async with httpx.AsyncClient(timeout=20.0, follow_redirects=True) as client:
        for ticker in tickers:
            cik = cik_map.get(ticker.upper())
            if not cik:
                continue
            cik_int = str(int(cik))  # numeric CIK for filing archive paths

            search_url = EDGAR_EFTS_URL.format(
                ticker=ticker.upper(),
                start=start_str,
                end=end_str,
            )
            data = await _get_json(client, search_url)
            if not data:
                continue

            hits = (data.get("hits") or {}).get("hits") or []
            for hit in hits[:5]:  # limit to 5 most recent 8-Ks per ticker
                source = hit.get("_source") or {}
                accn = hit.get("_id") or ""
                if not accn:
                    continue

                period = source.get("period_of_report") or end_str
                acc_nodash = _acc_nodash(accn)

                # Fetch the filing index to find EX-99.1 exhibit
                index_url = EDGAR_FILING_INDEX_URL.format(
                    cik=cik_int, acc_nodash=acc_nodash
                )
                index_data = await _get_json(client, index_url)
                if not index_data:
                    # Fallback: use accession number as a signal stub
                    all_articles.append({
                        "id": f"edgar_{accn}",
                        "title": f"SEC 8-K Filing: {ticker.upper()} ({period})",
                        "url": f"https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK={cik}&type=8-K&dateb=&owner=include&count=10",
                        "source_url": f"https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK={cik}&type=8-K",
                        "source": "sec.gov",
                        "published_at": f"{period}T00:00:00+00:00",
                        "summary": f"SEC 8-K material event filing by {ticker.upper()}",
                        "body": f"SEC 8-K material event filing by {ticker.upper()} for period {period}",
                        "ticker": ticker.upper(),
                        "source_type": "edgar_8k",
                    })
                    continue

                # Find EX-99.1 (press release exhibit) or 8-K body document
                documents = index_data.get("directory", {}).get("item", []) or []
                exhibit_file = None
                for doc in documents:
                    doc_type = str(doc.get("type") or "").upper()
                    name = str(doc.get("name") or "")
                    if doc_type in ("EX-99.1", "EX-99.2") and name.endswith((".htm", ".html", ".txt")):
                        exhibit_file = name
                        break
                if not exhibit_file:
                    for doc in documents:
                        name = str(doc.get("name") or "")
                        if name.endswith((".htm", ".html")) and "8-k" in name.lower():
                            exhibit_file = name
                            break

                exhibit_url = None
                body_text = None
                if exhibit_file:
                    exhibit_url = EDGAR_CONTENT_BASE.format(
                        cik=cik_int, acc_nodash=acc_nodash, filename=exhibit_file
                    )
                    raw = await _get_text(client, exhibit_url)
                    if raw:
                        body_text = _strip_html(raw)

                if not body_text:
                    body_text = f"SEC 8-K material event filing by {ticker.upper()} for period {period}"

                all_articles.append({
                    "id": f"edgar_{accn}",
                    "title": f"SEC 8-K: {ticker.upper()} material event ({period})",
                    "url": exhibit_url or f"https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK={cik}&type=8-K",
                    "source_url": exhibit_url or "",
                    "source": "sec.gov",
                    "published_at": f"{period}T00:00:00+00:00",
                    "summary": body_text[:500],
                    "body": body_text,
                    "ticker": ticker.upper(),
                    "source_type": "edgar_8k",
                })

    return all_articles
