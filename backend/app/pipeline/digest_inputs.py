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


def _sectors_from_metadata(supabase, tickers: list[str]) -> dict[str, str]:
    norm = sorted({_normalize_ticker(t) for t in tickers if _normalize_ticker(t)})
    if not norm or supabase is None:
        return {}
    try:
        rows = (
            supabase.table("ticker_metadata")
            .select("ticker,sector")
            .in_("ticker", norm)
            .execute()
            .data
            or []
        )
    except Exception:
        logger.exception("ticker_metadata sector read failed")
        return {}
    return {
        _normalize_ticker(r.get("ticker")): str(r.get("sector") or "").strip()
        for r in rows
        if _normalize_ticker(r.get("ticker"))
    }


def _position_sector_map(supabase, positions: list[dict]) -> dict[str, str]:
    """ticker -> sector, using the position's own field first, then ticker_metadata.

    position_payloads from the analysis pipeline often lack `sector`, so we fall
    back to ticker_metadata (which is where the canonical GICS sector lives).
    """
    out: dict[str, str] = {}
    missing: list[str] = []
    for position in positions:
        ticker = _normalize_ticker(position.get("ticker"))
        if not ticker:
            continue
        sector = str(position.get("sector") or "").strip()
        if sector and sector.lower() not in _INVALID_SECTORS:
            out[ticker] = sector
        else:
            missing.append(ticker)
    if missing:
        meta = _sectors_from_metadata(supabase, missing)
        for ticker in missing:
            sector = meta.get(ticker, "")
            out[ticker] = (
                sector if sector and sector.lower() not in _INVALID_SECTORS else "Unclassified"
            )
    return out


def build_sector_by_ticker(supabase, positions: list[dict]) -> dict[str, dict]:
    """ticker -> {sector, etf, etf_change_pct, headlines} for dot-connecting."""
    etf_changes = latest_sector_changes(supabase) if supabase is not None else {}
    sector_map = _position_sector_map(supabase, positions)
    events = _recent_company_events(supabase, [p.get("ticker") for p in positions])
    out: dict[str, dict] = {}
    for position in positions:
        ticker = _normalize_ticker(position.get("ticker"))
        if not ticker:
            continue
        sector = sector_map.get(ticker, "Unclassified")
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
    sector_map = _position_sector_map(supabase, positions)
    by_sector: dict[str, dict] = {}
    for position in positions:
        ticker = _normalize_ticker(position.get("ticker"))
        if not ticker:
            continue
        sector = sector_map.get(ticker, "Unclassified")
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


_GRADE_ORD = {
    "A+": 13, "A": 12, "A-": 11, "B+": 10, "B": 9, "B-": 8,
    "C+": 7, "C": 6, "C-": 5, "D+": 4, "D": 3, "D-": 2, "F": 1,
    "AAA": 13, "AA": 12, "BBB": 8, "BB": 6, "CCC": 2, "CC": 1,
}


def _grade_ord(grade: object) -> int:
    return _GRADE_ORD.get(str(grade or "").strip().upper(), 6)


def _num(value: object) -> float | None:
    try:
        return None if value is None else float(value)
    except (TypeError, ValueError):
        return None


async def build_position_impacts(
    supabase,
    positions: list[dict],
    macro_context: dict | None = None,
    sector_by_ticker: dict[str, dict] | None = None,
    sector_context: dict | None = None,
) -> list[dict]:
    """Per-ticker 'what's moving my stock' notes: macro + sector + company news.

    One focused LLM call per holding (batched calls return empty on the reasoning
    model). Falls back to a deterministic factor/sector line if a call fails.
    """
    from .macro_classifier import _impact_for_factor, analyze_position_note

    sector_by_ticker = sector_by_ticker or build_sector_by_ticker(supabase, positions)
    macro = (macro_context or {}).get("overnight_macro") or {}
    macro_brief = macro.get("brief")
    macro_headlines = macro.get("headlines") or []
    snapshot = _latest_macro_snapshot(supabase) or {}
    events = _recent_company_events(
        supabase, [p.get("ticker") for p in positions], per_ticker=4
    )
    sector_briefs = {
        str(s.get("sector") or "").strip().lower(): s.get("brief")
        for s in ((sector_context or {}).get("sector_overview") or [])
    }

    impacts: list[dict] = []
    for position in positions:
        ticker = _normalize_ticker(position.get("ticker"))
        if not ticker:
            continue
        sec = sector_by_ticker.get(ticker) or {}
        sector_name = sec.get("sector")
        company_news = [h for h in (_event_headline(e) for e in events.get(ticker, [])) if h]
        sbrief = sector_briefs.get(str(sector_name or "").strip().lower())
        note = await analyze_position_note(
            ticker,
            sector_name,
            sec.get("etf_change_pct"),
            sbrief,
            macro_brief,
            macro_headlines,
            company_news,
        )
        if note and note.get("impact_summary"):
            impacts.append(note)
            continue
        summary, relevance = _impact_for_factor(
            ticker, sector_name or "", _num(sec.get("etf_change_pct")), snapshot
        )
        impacts.append(
            {"ticker": ticker, "macro_relevance": relevance, "impact_summary": summary}
        )
    return impacts


def _short_reason(text: str, limit: int = 120) -> str:
    t = " ".join(str(text or "").split())
    # First sentence, but skip ". " before index 30 so abbreviations like
    # "U.S." or "Inc." don't truncate the reason to a fragment.
    start = 0
    while True:
        idx = t.find(". ", start)
        if idx == -1:
            break
        if idx >= 30:
            t = t[:idx]
            break
        start = idx + 2
    if len(t) > limit:
        t = t[:limit].rsplit(" ", 1)[0] + "…"
    return t.rstrip(".")


def build_what_to_watch(
    supabase,
    positions: list[dict],
    earnings: list[dict] | None,
    sector_by_ticker: dict[str, dict] | None = None,
    position_impacts: list[dict] | None = None,
) -> list[dict]:
    """Actionable watch items. Direction comes from the per-ticker position note
    (supports = up -> consider trimming; contradicts = down -> research before
    you hold); the reason is that note's lead sentence. Plus dated earnings.
    """
    sector_by_ticker = sector_by_ticker or {}
    imp_by_ticker = {
        _normalize_ticker(i.get("ticker")): i
        for i in (position_impacts or [])
        if _normalize_ticker(i.get("ticker"))
    }

    earnings_items: list[dict] = []
    try:
        from ..services.earnings_calendar import format_earnings_line
    except Exception:
        format_earnings_line = None
    for row in (earnings or [])[:2]:
        ticker = _normalize_ticker(row.get("ticker"))
        line = format_earnings_line(row) if format_earnings_line else None
        if ticker and line:
            earnings_items.append(
                {"catalyst": f"{line} — watch the print.", "impacted_positions": [ticker], "urgency": "medium"}
            )

    concerning: list[dict] = []
    positive: list[dict] = []
    for position in positions:
        ticker = _normalize_ticker(position.get("ticker"))
        if not ticker:
            continue
        imp = imp_by_ticker.get(ticker) or {}
        rel = str(imp.get("macro_relevance") or "").lower()
        reason = _short_reason(imp.get("impact_summary"))
        grade = position.get("grade")
        prev = position.get("previous_grade")
        graded = bool(str(prev or "").strip()) and bool(str(grade or "").strip())
        grade_down = graded and _grade_ord(prev) > _grade_ord(grade)
        grade_up = graded and _grade_ord(grade) > _grade_ord(prev)
        if not reason:
            continue
        if rel == "contradicts" or grade_down:
            concerning.append(
                {
                    "catalyst": f"{ticker}: {reason}. Dig in and decide whether it changes your thesis before you keep holding.",
                    "impacted_positions": [ticker],
                    "urgency": "high" if grade_down else "medium",
                    "_rank": 0 if grade_down else 1,
                }
            )
        elif rel == "supports" or grade_up:
            positive.append(
                {
                    "catalyst": f"{ticker}: {reason}. If you're sitting on gains here, consider whether to trim.",
                    "impacted_positions": [ticker],
                    "urgency": "low",
                    "_rank": 0 if grade_up else 1,
                }
            )

    concerning.sort(key=lambda x: x.pop("_rank", 1))
    positive.sort(key=lambda x: x.pop("_rank", 1))
    items = earnings_items + concerning[:3] + positive[:2]
    if not items:
        items = [
            {
                "catalyst": "No dated catalysts or notable moves today; nothing urgent to watch.",
                "impacted_positions": [],
                "urgency": "low",
            }
        ]
    return items[:6]


def _event_is_material(row: dict) -> bool:
    """An alert is a thing that HAPPENED with a clear bullish or bearish read.
    A neutral event is NOT an alert no matter how 'major' it is tagged: that is
    exactly how routine valuation/DCF write-ups ("our calculation of intrinsic
    value", "the acquirer's multiple") sneak in. So we require a direction."""
    direction = str(row.get("risk_direction") or "").strip().lower()
    return direction in ("improving", "worsening")


def _event_alert_text(row: dict, ticker: str) -> str | None:
    """Statement + interpretation: 'what happened. what it means.'"""
    happened = _trim(
        str(row.get("what_happened") or row.get("tldr") or row.get("title") or "").strip(),
        150,
    )
    if not happened:
        return None
    means = _trim(str(row.get("what_it_means") or "").strip(), 150)
    if means and means.lower().rstrip(".").strip() in happened.lower():
        means = ""  # don't echo the headline back as its own interpretation
    body = happened
    if means:
        if body and body[-1] not in ".!?":
            body += "."
        body = f"{body} {means}"
    if not body.upper().startswith(ticker.upper()):
        body = f"{ticker}: {body}"
    if body and body[-1] not in ".!?":
        body += "."
    return body


def build_event_watchlist_alerts(
    supabase, tickers: list[str], *, days: int = 5, limit: int = 6
) -> list[str]:
    """Event-driven alerts: only real, material events, written as
    'TICKER: what happened. what it means.' Returns [] when nothing happened."""
    norm = sorted({_normalize_ticker(t) for t in tickers if _normalize_ticker(t)})
    if not norm or supabase is None:
        return []
    try:
        rows = (
            supabase.table("shared_ticker_events")
            .select(
                "ticker,title,tldr,what_happened,what_it_means,"
                "risk_direction,published_at,significance"
            )
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

    # Pick the single most meaningful recent MATERIAL event per ticker. A clear
    # direction outranks a major-but-neutral event; newer breaks ties.
    def _score(row: dict, order_idx: int) -> tuple:
        direction = str(row.get("risk_direction") or "").strip().lower()
        sig = str(row.get("significance") or "").strip().lower()
        return (
            1 if direction in ("worsening", "improving") else 0,
            1 if sig in ("major", "high") else 0,
            -order_idx,  # newer first as a tiebreak
        )

    best: dict[str, tuple] = {}
    for idx, row in enumerate(rows):
        ticker = _normalize_ticker(row.get("ticker"))
        if not ticker or not _within_days(row.get("published_at"), cutoff):
            continue
        if not _event_is_material(row):
            continue
        if not _event_alert_text(row, ticker):
            continue
        score = _score(row, idx)
        if ticker not in best or score > best[ticker][0]:
            best[ticker] = (score, row)

    ranked = sorted(best.values(), key=lambda sr: sr[0], reverse=True)
    alerts: list[str] = []
    for _score_val, row in ranked[:limit]:
        ticker = _normalize_ticker(row.get("ticker"))
        text = _event_alert_text(row, ticker)
        if text:
            alerts.append(text)
    return alerts


def _grade_band(grade: object) -> str:
    """First letter of a grade = its whole-letter band (A+/A/A- -> A)."""
    g = str(grade or "").strip().upper()
    return g[0] if g else ""


def _is_academic_grade(grade: object) -> bool:
    """True only for grades unambiguously on the new academic ladder: a +/-
    modifier, or the D tier (the old AAA/BBB/CCC ladder had neither). Bare
    A/B/C/F exist on BOTH ladders, so during and right after the grade-vocabulary
    migration we refuse to compare them: an old 'BBB' read against a new 'B-'
    would otherwise look like a downgrade that never happened."""
    g = str(grade or "").strip().upper()
    return ("+" in g) or ("-" in g) or g.startswith("D")


def build_grade_change_alerts(positions: list[dict] | None) -> list[str]:
    """Watchlist alert when a holding's overall grade (the roll-up of the five
    dimension metrics) crosses a WHOLE letter band vs the prior snapshot. We
    only fire on a full-band move (B -> A, B -> C) so day-to-day grade flicker
    inside a band (B+ -> B) never spams an alert, and only when BOTH grades are
    unambiguously academic so a vocabulary mismatch never reads as a real move."""
    alerts: list[str] = []
    for position in positions or []:
        ticker = _normalize_ticker(position.get("ticker"))
        grade = str(position.get("grade") or "").strip()
        prev = str(position.get("previous_grade") or "").strip()
        if not ticker or not grade or not prev:
            continue
        if not (_is_academic_grade(grade) and _is_academic_grade(prev)):
            continue
        if _grade_band(grade) == _grade_band(prev):
            continue
        if _grade_ord(grade) > _grade_ord(prev):
            alerts.append(
                f"{ticker}: risk grade upgraded a full letter from {prev} to {grade} as its "
                f"overall profile strengthened. A constructive shift worth a closer look."
            )
        elif _grade_ord(grade) < _grade_ord(prev):
            alerts.append(
                f"{ticker}: risk grade slipped a full letter from {prev} to {grade} as its "
                f"overall profile weakened. Worth reviewing whether your thesis still holds."
            )
    return alerts


def _alert_lead_ticker(text: str) -> str:
    head = str(text or "").strip()
    for sep in (":", " — ", " "):
        if sep in head:
            head = head.split(sep, 1)[0]
            break
    return head.strip().upper()


def merge_watchlist_alerts(
    grade_alerts: list[str] | None,
    news_alerts: list[str] | None,
    *,
    limit: int = 6,
) -> list[str]:
    """Combine grade-band changes (most material, listed first) with news
    events, one alert per ticker."""
    out: list[str] = []
    seen: set[str] = set()
    for text in list(grade_alerts or []) + list(news_alerts or []):
        t = str(text or "").strip()
        if not t:
            continue
        ticker = _alert_lead_ticker(t)
        if ticker and ticker in seen:
            continue
        if ticker:
            seen.add(ticker)
        out.append(t)
        if len(out) >= limit:
            break
    return out
