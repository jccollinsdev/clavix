"""Pre-generate polished "Key drivers" cards for the whole ticker universe.

The ticker-detail request path builds driver cards live from `shared_ticker_events`
for any name the user does not hold. That live text is raw event copy (often vague
or jargon-y). This job runs the same card builder PLUS an LLM polish pass that
rewrites each card into a specific, plain-English title/summary and corrects the
theme/direction, then caches the result in `analysis_cache` (kind
`shared_driver_cards`, keyed by ticker). `build_ticker_analysis_detail` reads that
cache before falling back to a live build, so users see the clean cards.

Idempotent and re-runnable. Held positions get their polish inline during recompute
(`build_position_report`); this job covers everything else.
"""
from __future__ import annotations

import logging
from typing import Any

from app.services.supabase import get_supabase
from app.services.ticker_cache_service import (
    SHARED_DRIVER_CARDS_CACHE_KIND,
    _build_event_analyses_from_news_rows,
)
from app.pipeline.position_report_builder import (
    _build_driver_cards,
    polish_driver_cards,
)

logger = logging.getLogger(__name__)

EVENTS_PER_TICKER = 20


def _utcnow_iso() -> str:
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).isoformat()


def _store(supabase, ticker: str, payload: dict[str, Any]) -> None:
    supabase.table("analysis_cache").upsert(
        {
            "kind": SHARED_DRIVER_CARDS_CACHE_KIND,
            "cache_key": ticker.upper(),
            "payload": payload,
            "updated_at": _utcnow_iso(),
        },
        on_conflict="kind,cache_key",
    ).execute()


def _refresh_one(supabase, ticker: str, company_name: str = "") -> str:
    """Returns 'cards' if polished cards were written, 'empty' if no cards, or
    'error' on failure."""
    event_rows = (
        supabase.table("shared_ticker_events")
        .select("*")
        .eq("ticker", ticker)
        .order("published_at", desc=True)
        .limit(EVENTS_PER_TICKER)
        .execute()
        .data
        or []
    )
    if not event_rows:
        _store(supabase, ticker, {"driver_cards": [], "driver_cards_state": "empty"})
        return "empty"

    event_analyses = _build_event_analyses_from_news_rows(
        event_rows, ticker=ticker, position_id=f"virtual:{ticker}"
    )
    cards, state, _source = _build_driver_cards(
        {
            "ticker": ticker,
            "status": "ready",
            "analysis_state": "ready",
            "coverage_state": "substantive",
            "source_count": len(event_rows),
        },
        event_analyses=event_analyses,
        related_articles=[],
        alerts=[],
    )
    if not cards:
        _store(
            supabase, ticker, {"driver_cards": [], "driver_cards_state": state}
        )
        return "empty"

    cards = polish_driver_cards(cards, ticker=ticker, company_name=company_name)
    _store(
        supabase,
        ticker,
        {"driver_cards": cards, "driver_cards_state": "ready"},
    )
    return "cards"


def run(
    *,
    limit: int | None = None,
    tickers: list[str] | None = None,
    include_etfs: bool = False,
) -> dict[str, Any]:
    supabase = get_supabase()

    if tickers:
        targets = [(t.upper(), "") for t in tickers]
    else:
        rows = (
            supabase.table("ticker_metadata")
            .select("ticker,asset_class,company_name")
            .execute()
            .data
            or []
        )
        targets = [
            (
                str(r.get("ticker") or "").upper(),
                str(r.get("company_name") or ""),
            )
            for r in rows
            if r.get("ticker")
            and (include_etfs or str(r.get("asset_class") or "").lower() != "etf")
        ]
        targets = sorted(set(targets))
    if limit:
        targets = targets[:limit]

    written = 0
    empty = 0
    errors = 0
    for i, (ticker, company_name) in enumerate(targets):
        try:
            outcome = _refresh_one(supabase, ticker, company_name)
            if outcome == "cards":
                written += 1
            elif outcome == "empty":
                empty += 1
        except Exception as exc:  # never let one ticker abort the sweep
            errors += 1
            logger.warning("[DRIVER_CARDS_REFRESH] %s failed: %s", ticker, exc)
        if (i + 1) % 25 == 0:
            logger.info(
                "[DRIVER_CARDS_REFRESH] %d/%d (%d with cards, %d empty, %d err)",
                i + 1,
                len(targets),
                written,
                empty,
                errors,
            )

    return {
        "status": "completed",
        "items_processed": len(targets),
        "items_with_cards": written,
        "items_empty": empty,
        "items_error": errors,
    }


def run_from_env() -> dict[str, Any]:
    return run()
