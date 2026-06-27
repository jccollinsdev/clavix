"""Builders that feed the morning digest from already-populated, compliant data.

The 2026-06-26 Tickertick migration severed the live news feeds but left four
daily-refreshed sources unused. This module plumbs them into the digest:
- macro_regime_snapshots (FRED factors) + CNBC top macro headlines -> macro readout
- sector_regime_snapshots (ETF day-change) + CNBC sector RSS + holdings' events
  -> per-owned-sector directional briefs
- shared_ticker_events (what_happened / risk_direction) -> event-driven alerts
"""

from __future__ import annotations

import logging
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from .macro_classifier import (
    _fallback_factor_macro,
    _normalize_ticker,
    classify_overnight_macro,
    classify_overnight_macro_from_factors,
    summarize_owned_sectors,
)
from .sector_constants import etf_for_sector, latest_sector_changes

logger = logging.getLogger(__name__)

_TZ = ZoneInfo("America/New_York")

_MACRO_COLS = (
    "as_of_date,regime_state,vix_level,vix_day_change,ust10y_level,ust10y_day_change,"
    "dxy_level,dxy_day_change,wti_level,wti_day_change,spy_close,spy_day_change_pct,"
    "credit_spread_level,rates_signal,credit_signal,data_status"
)

_INVALID_SECTORS = {"", "unknown", "none", "null", "n/a", "unclassified"}

_DIRECTION = {
    "worsening": "Downward pressure",
    "improving": "Upward pressure",
    "neutral": "Mixed/neutral read",
}


def _trim(text: str, limit: int) -> str:
    text = " ".join(str(text or "").split())
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"


def _event_headline(event: dict) -> str:
    return _trim(
        str(event.get("what_happened") or event.get("tldr") or event.get("title") or "").strip(),
        160,
    )


def _within_days(published_at: object, cutoff: date) -> bool:
    raw = str(published_at or "")[:10]
    if not raw:
        return True
    try:
        return date.fromisoformat(raw) >= cutoff
    except Exception:
        return True


# ----------------------------- macro factors -------------------------------

def _latest_macro_snapshot(supabase) -> dict | None:
    try:
        rows = (
            supabase.table("macro_regime_snapshots")
            .select(_MACRO_COLS)
            .order("as_of_date", desc=True)
            .limit(1)
            .execute()
            .data
            or []
        )
    except Exception:
        logger.exception("macro_regime_snapshots read failed")
        return None
    return rows[0] if rows else None


def _snapshot_is_fresh(snapshot: dict | None, *, max_age_days: int = 3) -> bool:
    if not snapshot:
        return False
    raw = str(snapshot.get("as_of_date") or "")[:10]
    try:
        d = date.fromisoformat(raw)
    except Exception:
        return False
    return (datetime.now(_TZ).date() - d).days <= max_age_days


async def _fetch_macro_headlines(limit: int = 8) -> list[dict]:
    try:
        from .rss_ingest import fetch_cnbc_macro_rss

        articles = await fetch_cnbc_macro_rss(limit=limit)
        return [
            a for a in (articles or []) if isinstance(a, dict) and str(a.get("title") or "").strip()
        ]
    except Exception:
        logger.exception("CNBC macro RSS fetch failed")
        return []


# ----------------------------- shared events -------------------------------

def _recent_company_events(
    supabase, tickers: list[str], *, days: int = 7, per_ticker: int = 3
) -> dict[str, list[dict]]:
    norm = sorted({_normalize_ticker(t) for t in tickers if _normalize_ticker(t)})
    if not norm or supabase is None:
        return {}
    try:
        rows = (
            supabase.table("shared_ticker_events")
            .select(
                "ticker,title,tldr,what_happened,what_it_means,risk_direction,published_at,significance,sentiment_score"
            )
            .in_("ticker", norm)
            .order("published_at", desc=True)
            .limit(max(len(norm) * per_ticker * 3, 30))
            .execute()
            .data
            or []
        )
    except Exception:
        logger.exception("shared_ticker_events read failed")
        return {}
    out: dict[str, list[dict]] = {}
    for row in rows:
        ticker = _normalize_ticker(row.get("ticker"))
        if not ticker:
            continue
        bucket = out.setdefault(ticker, [])
        if len(bucket) < per_ticker:
            bucket.append(row)
    return out


def build_sector_by_ticker(supabase, positions: list[dict]) -> dict[str, dict]:
    """ticker -> {sector, etf, etf_change_pct, headlines} for dot-connecting."""
    etf_changes = latest_sector_changes(supabase) if supabase is not None else {}
    events = _recent_company_events(supabase, [p.get("ticker") for p in positions])
    out: dict[str, dict] = {}
    for position in positions:
        ticker = _normalize_ticker(position.get("ticker"))
        if not ticker:
            continue
        sector = str(position.get("sector") or "").strip() or "Unclassified"
        etf = etf_for_sector(sector)
        heads = [h for h in (_event_headline(e) for e in events.get(ticker, [])) if h][:2]
        out[ticker] = {
            "sector": sector,
            "etf": etf,
            "etf_change_pct": etf_changes.get(etf) if etf else None,
            "headlines": heads,
        }
    return out


# ----------------------------- public builders -----------------------------

async def build_factor_macro_context(
    supabase, positions: list[dict], sector_by_ticker: dict[str, dict] | None = None
) -> dict:
    """Macro readout from FRED factors + CNBC headlines, connected to holdings."""
    sector_by_ticker = sector_by_ticker or build_sector_by_ticker(supabase, positions)
    headlines = await _fetch_macro_headlines()
    snapshot = _latest_macro_snapshot(supabase)
    fresh_real = _snapshot_is_fresh(snapshot) and str(
        (snapshot or {}).get("data_status")
    ) == "real_factors"

    if fresh_real:
        return await classify_overnight_macro_from_factors(
            snapshot, headlines, positions, sector_by_ticker
        )
    if headlines:
        # No fresh real factors, but real macro headlines exist: still produce a
        # genuine news-driven macro read instead of a blank section.
        return await classify_overnight_macro(headlines, positions, sector_by_ticker)
    if _snapshot_is_fresh(snapshot):
        # Thin (price-only) but fresh factors beat an empty section.
        return await classify_overnight_macro_from_factors(
            snapshot, headlines, positions, sector_by_ticker
        )
    # Genuinely nothing to say.
    fallback = _fallback_factor_macro(snapshot or {}, [], positions, sector_by_ticker)
    fallback["overnight_macro"]["brief"] = (
        "No major overnight macro moves to flag; rates, oil, and volatility were roughly flat."
    )
    return fallback


async def _fetch_sector_articles(sector_names: list[str], limit_per_sector: int = 6) -> list[dict]:
    if not sector_names:
        return []
    try:
        from .rss_ingest import fetch_cnbc_sector_rss

        return await fetch_cnbc_sector_rss(sector_names, limit_per_sector=limit_per_sector) or []
    except Exception:
        logger.exception("CNBC sector RSS fetch failed")
        return []


async def build_sector_context(
    supabase, positions: list[dict], sector_by_ticker: dict[str, dict] | None = None
) -> dict:
    """Per-owned-sector directional briefs from ETF moves + CNBC + holdings' events."""
    etf_changes = latest_sector_changes(supabase) if supabase is not None else {}
    by_sector: dict[str, dict] = {}
    for position in positions:
        ticker = _normalize_ticker(position.get("ticker"))
        if not ticker:
            continue
        sector = str(position.get("sector") or "").strip()
        if sector.lower() in _INVALID_SECTORS:
            continue
        entry = by_sector.setdefault(
            sector,
            {"sector": sector, "tickers": [], "etf_change_pct": None, "articles": []},
        )
        if ticker not in entry["tickers"]:
            entry["tickers"].append(ticker)

    if not by_sector:
        return {"sector_overview": []}

    for sector, entry in by_sector.items():
        etf = etf_for_sector(sector)
        entry["etf_change_pct"] = etf_changes.get(etf) if etf else None

    # CNBC sector RSS, grouped onto owned sectors by hint.
    sector_articles = await _fetch_sector_articles(list(by_sector.keys()))
    for article in sector_articles:
        if not isinstance(article, dict):
            continue
        hint = str(article.get("sector_hint") or article.get("sector") or "").strip().lower()
        for sector, entry in by_sector.items():
            if hint and (hint in sector.lower() or sector.lower() in hint):
                entry["articles"].append(article)
                break

    # The "why": each holding's most recent company event becomes a note.
    events = _recent_company_events(supabase, [p.get("ticker") for p in positions])
    for entry in by_sector.values():
        for ticker in entry["tickers"]:
            for event in events.get(ticker, [])[:1]:
                headline = _event_headline(event)
                if headline:
                    entry["articles"].append(
                        {
                            "title": f"{ticker}: {headline}",
                            "summary": str(event.get("what_it_means") or event.get("tldr") or ""),
                        }
                    )

    return await summarize_owned_sectors(list(by_sector.values()))


def build_event_watchlist_alerts(
    supabase, tickers: list[str], *, days: int = 5, limit: int = 6
) -> list[str]:
    """Event-driven alerts: 'TICKER — what happened -> Up/Down pressure'."""
    norm = sorted({_normalize_ticker(t) for t in tickers if _normalize_ticker(t)})
    if not norm or supabase is None:
        return []
    try:
        rows = (
            supabase.table("shared_ticker_events")
            .select("ticker,title,tldr,what_happened,risk_direction,published_at,significance")
            .in_("ticker", norm)
            .order("published_at", desc=True)
            .limit(max(limit * 4, 24))
            .execute()
            .data
            or []
        )
    except Exception:
        logger.exception("watchlist alerts read failed")
        return []

    cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).date()
    alerts: list[str] = []
    seen: set[str] = set()
    for row in rows:
        ticker = _normalize_ticker(row.get("ticker"))
        if not ticker or ticker in seen:
            continue
        if not _within_days(row.get("published_at"), cutoff):
            continue
        what = _event_headline(row)
        if not what:
            continue
        direction = _DIRECTION.get(
            str(row.get("risk_direction") or "").strip().lower(), "Mixed/neutral read"
        )
        alerts.append(f"{ticker} — {what} -> {direction}")
        seen.add(ticker)
        if len(alerts) >= limit:
            break
    return alerts
