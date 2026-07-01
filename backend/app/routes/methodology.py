from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, Request

from ..pipeline.analysis_utils import article_has_full_enrichment
from ..services.personalisation import attach_latest_personalisation
from ..services.supabase import get_supabase
from ..services.ticker_cache_service import (
    _coerce_float,
    _etf_sector_strength_score,
    _shared_risk_dimensions,
    get_latest_risk_snapshot_history_map,
    get_latest_risk_snapshot_map,
)

router = APIRouter()


def get_user_id(request: Request) -> str:
    return request.state.user_id


def _parse_iso_datetime(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None


def _isoformat_or_none(value: Any) -> str | None:
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc).isoformat()
    if value in {None, ""}:
        return None
    return str(value)


def _latest_sector_medians(supabase, sector: str | None) -> dict[str, dict[str, Any]]:
    if not sector:
        return {}
    rows = (
        supabase.table("sector_medians")
        .select("sector,metric,median,p25,p75,n_tickers,as_of")
        .eq("sector", sector)
        .order("as_of", desc=True)
        .limit(100)
        .execute()
        .data
        or []
    )
    medians: dict[str, dict[str, Any]] = {}
    for row in rows:
        metric = row.get("metric")
        if metric and metric not in medians:
            medians[metric] = row
    return medians


def _peer_comparisons(supabase, ticker: str) -> list[dict[str, Any]]:
    rows = (
        supabase.table("peer_groups")
        .select("peer_ticker,similarity,computed_at")
        .eq("ticker", ticker)
        .order("similarity", desc=True)
        .limit(10)
        .execute()
        .data
        or []
    )
    return [
        {
            "ticker": row.get("peer_ticker"),
            "similarity": row.get("similarity"),
            "computed_at": row.get("computed_at"),
        }
        for row in rows
        if row.get("peer_ticker") != ticker
    ]


def _article_histogram(articles: list[dict[str, Any]], days: int = 14) -> list[dict[str, Any]]:
    now = datetime.now(timezone.utc)
    counts = {
        (now - timedelta(days=offset)).date().isoformat(): 0
        for offset in range(days - 1, -1, -1)
    }
    for article in articles:
        published = _parse_iso_datetime(article.get("published_at"))
        if not published:
            continue
        key = published.date().isoformat()
        if key in counts:
            counts[key] += 1
    return [{"date": key, "count": value} for key, value in counts.items()]


def _sentiment_distribution(articles: list[dict[str, Any]]) -> list[dict[str, Any]]:
    counts = {"positive": 0, "neutral": 0, "negative": 0}
    for article in articles:
        score = article.get("sentiment_score")
        if score is None:
            continue
        try:
            numeric = float(score)
        except (TypeError, ValueError):
            continue
        if numeric >= 60:
            counts["positive"] += 1
        elif numeric <= 40:
            counts["negative"] += 1
        else:
            counts["neutral"] += 1
    return [{"bucket": key, "count": value} for key, value in counts.items()]


def _factor_exposures(
    macro_inputs: dict[str, Any],
    macro_regression: dict[str, Any],
) -> dict[str, Any]:
    exposures = macro_inputs.get("factor_exposures")
    if isinstance(exposures, dict) and exposures:
        return exposures
    legacy = macro_inputs.get("coefficients") or macro_regression.get("coefficients") or {}
    if not isinstance(legacy, dict):
        return {}
    mapped = {
        "beta_10y": legacy.get("tnx"),
        "beta_dxy": legacy.get("dxy"),
        "beta_wti": legacy.get("wti"),
        "beta_vix": legacy.get("vix"),
        "beta_spy": legacy.get("spy"),
    }
    return {key: value for key, value in mapped.items() if value is not None}


def _etf_scored_holdings(supabase, upper: str, limit: int = 25) -> list[dict[str, Any]]:
    """Top constituents with weight + Clavix score, for the Holdings Quality chart."""
    date_rows = (
        supabase.table("etf_holdings")
        .select("as_of")
        .eq("etf_ticker", upper)
        .order("as_of", desc=True)
        .limit(1)
        .execute()
        .data
        or []
    )
    if not date_rows:
        return []
    as_of = date_rows[0].get("as_of")
    rows = (
        supabase.table("etf_holdings")
        .select("holding_ticker,weight_pct,rank")
        .eq("etf_ticker", upper)
        .eq("as_of", as_of)
        .order("rank")
        .limit(limit)
        .execute()
        .data
        or []
    )
    tickers = [str(r.get("holding_ticker") or "").upper() for r in rows if r.get("holding_ticker")]
    score_map: dict[str, float] = {}
    if tickers:
        snaps = get_latest_risk_snapshot_map(supabase, tickers)
        for t, snap in snaps.items():
            s = _coerce_float(snap.get("safety_score"))
            if s is None:
                s = _coerce_float(snap.get("composite_score"))
            if s is not None:
                score_map[t] = round(s, 1)
    out = []
    for r in rows:
        t = str(r.get("holding_ticker") or "").upper()
        out.append(
            {
                "ticker": t,
                "weight_pct": round(_coerce_float(r.get("weight_pct")) or 0.0, 3),
                "score": score_map.get(t),
            }
        )
    return out


def _etf_profile_bundle(supabase, upper: str) -> dict[str, Any] | None:
    """Fetch the fund profile + scored holdings for an ETF. Read live from
    etf_profiles/etf_holdings so the ETF screens do not depend on a recompute."""
    rows = (
        supabase.table("etf_profiles")
        .select("*")
        .eq("ticker", upper)
        .limit(1)
        .execute()
        .data
        or []
    )
    if not rows:
        return None
    profile = rows[0]
    perf = profile.get("performance") if isinstance(profile.get("performance"), dict) else None
    holdings = _etf_scored_holdings(supabase, upper)
    scored = [h for h in holdings if h.get("score") is not None]
    return {
        "theme": profile.get("theme"),
        "category": profile.get("category"),
        "benchmark": profile.get("benchmark"),
        "total_holdings": profile.get("total_holdings"),
        "top10_weight_pct": _coerce_float(profile.get("top10_weight_pct")),
        "aum": _coerce_float(profile.get("aum")),
        "pe_ratio": _coerce_float(profile.get("pe_ratio")),
        "sectors": profile.get("sectors"),
        "countries": profile.get("countries"),
        "performance": perf,
        "sector_strength_score": _etf_sector_strength_score(perf) if perf else None,
        "holdings": holdings,
        "holdings_shown": len(holdings),
        "holdings_scored_count": len(scored),
        "holdings_as_of": _isoformat_or_none(profile.get("holdings_as_of")),
    }


def _build_methodology_response(supabase, upper: str, user_id: str) -> dict[str, Any]:
    """All synchronous DB work for the methodology endpoint.

    Called via asyncio.to_thread so it does not block the event loop.
    """
    import json

    metadata_result = (
        supabase.table("ticker_metadata")
        .select("*")
        .eq("ticker", upper)
        .limit(1)
        .execute()
    )
    metadata = metadata_result.data[0] if metadata_result.data else {}
    sector = metadata.get("sector")
    sector_medians = _latest_sector_medians(supabase, sector)
    peers = _peer_comparisons(supabase, upper)

    snapshot = (
        get_latest_risk_snapshot_history_map(supabase, [upper], per_ticker=1).get(upper, [{}])[0]
    )

    factor_breakdown = snapshot.get("factor_breakdown") or {}
    if isinstance(factor_breakdown, str):
        try:
            factor_breakdown = json.loads(factor_breakdown)
        except Exception:
            factor_breakdown = {}

    dimension_inputs = snapshot.get("dimension_inputs") or {}
    if isinstance(dimension_inputs, str):
        try:
            dimension_inputs = json.loads(dimension_inputs)
        except Exception:
            dimension_inputs = {}

    risk_dims = _shared_risk_dimensions(snapshot)

    articles_result = (
        supabase.table("shared_ticker_events")
        .select("*")
        .eq("ticker", upper)
        .order("published_at", desc=True)
        .limit(50)
        .execute()
    )
    articles = articles_result.data or []

    now = datetime.now(timezone.utc)
    seven_day_articles = [
        a for a in articles
        if (pub := _parse_iso_datetime(a.get("published_at"))) and now - pub <= timedelta(days=7)
    ]
    fourteen_day_articles = [
        a for a in articles
        if (pub := _parse_iso_datetime(a.get("published_at"))) and now - pub <= timedelta(days=14)
    ]

    # Only surface fully-enriched articles (brief + risk-signal score + key
    # implications). Incomplete/paywalled/headline-only rows render as empty cards
    # in-app, so they are hidden entirely (2026-06-30). Prefer the last 7 days, then
    # widen the window so a thin recent week still shows real, complete articles.
    complete_7d = [a for a in seven_day_articles if article_has_full_enrichment(a)]
    complete_14d = [a for a in fourteen_day_articles if article_has_full_enrichment(a)]
    complete_all = [a for a in articles if article_has_full_enrichment(a)]
    display_articles = complete_7d or complete_14d or complete_all

    news_inputs = dimension_inputs.get("news_sentiment") or {}
    macro_inputs = dimension_inputs.get("macro_exposure") or {}
    sector_inputs = dimension_inputs.get("sector_exposure") or {}
    volatility_inputs = dimension_inputs.get("volatility") or {}
    financial_inputs = dimension_inputs.get("financial_health") or {}
    macro_regression = factor_breakdown.get("macro_regression") or {}

    is_etf = str(metadata.get("asset_class") or "").lower() == "etf"
    etf_bundle = _etf_profile_bundle(supabase, upper) if is_etf else None

    def _limited_data_flag(payload: dict[str, Any]) -> bool:
        return bool(payload.get("limited_data") or payload.get("limited"))

    def _limited_data_reason(payload: dict[str, Any]) -> str | None:
        return (
            payload.get("limited_reason")
            or payload.get("limited_data_reason")
            or payload.get("reason")
        )

    factor_exposures = _factor_exposures(macro_inputs, macro_regression)

    if news_inputs.get("weighted_score") is None:
        weighted_total = 0.0
        total_weight = 0.0
        for article in display_articles:
            sentiment_score = article.get("sentiment_score")
            if sentiment_score is None:
                continue
            recency_weight = float(article.get("recency_weight") or 1.0)
            source_weight = float(article.get("source_weight") or 1.0)
            weight = recency_weight * source_weight
            weighted_total += float(sentiment_score) * weight
            total_weight += weight
        if total_weight > 0:
            news_inputs["weighted_score"] = round(weighted_total / total_weight, 1)

    if not sector_inputs.get("sector_etf") and metadata.get("sector"):
        sector_inputs = {
            "sector": metadata.get("sector"),
            "sector_etf": None,
            "sector_beta": None,
            "sector_momentum_30d": None,
            "sector_breadth": None,
            "narrative": None,
            # Preserve ETF concentration fields through this sector-fallback (sector
            # ETFs like XLK have both a metadata sector AND concentration data).
            "dimension_label": sector_inputs.get("dimension_label"),
            "holdings_count": sector_inputs.get("holdings_count"),
            "top_holding_weight_pct": sector_inputs.get("top_holding_weight_pct"),
            "top_10_weight_pct": sector_inputs.get("top_10_weight_pct"),
            "concentration_score": sector_inputs.get("concentration_score"),
        }

    article_payloads = [
        {
            "id": article.get("id"),
            "title": article.get("title"),
            "source": article.get("source"),
            "published_at": article.get("published_at"),
            "source_tier": article.get("source_tier"),
            "recency_weight": article.get("recency_weight"),
            "sentiment_score": article.get("sentiment_score"),
            "sentiment_reason": article.get("sentiment_reason"),
            "impact_tag": article.get("impact_tag"),
            "tldr": article.get("tldr"),
            "what_it_means": article.get("what_it_means"),
            "key_implications": article.get("key_implications") or [],
            "source_url": (
                article.get("canonical_url")
                or article.get("source_url")
                or article.get("url")
            ),
        }
        for article in display_articles[:15]
    ]
    article_payloads = attach_latest_personalisation(
        supabase,
        user_id=user_id,
        articles=article_payloads,
    )

    return {
        "ticker": upper,
        "dimensions": {
            "financial_health": {
                "score": risk_dims.get("financial_health"),
                "limited_data": _limited_data_flag(financial_inputs),
                "limited_reason": _limited_data_reason(financial_inputs),
                "debt_to_equity": financial_inputs.get("debt_to_equity"),
                "fcf_margin": financial_inputs.get("fcf_margin"),
                "interest_coverage": financial_inputs.get("interest_coverage"),
                "current_ratio": financial_inputs.get("current_ratio"),
                "revenue_growth_trend": financial_inputs.get("revenue_growth_trend"),
                "profitability_trend": financial_inputs.get("profitability_trend"),
                "as_of_date": financial_inputs.get("as_of_date") or _isoformat_or_none(metadata.get("updated_at")),
                "data_source": financial_inputs.get("data_source")
                or metadata.get("fundamentals_source")
                or "edgar",
                "peer_comparisons": peers,
                "sector_median_comparison": {
                    metric: sector_medians.get(metric)
                    for metric in (
                        "debt_to_equity",
                        "fcf_margin",
                        "interest_coverage",
                        "current_ratio",
                    )
                    if sector_medians.get(metric)
                },
                # ETF Holdings Quality: constituent-weighted holdings, scored. Present
                # only for funds; equities leave these null. Holdings/count read live
                # from etf_profiles so the chart is fresh regardless of recompute.
                "dimension_label": "Holdings Quality" if etf_bundle else financial_inputs.get("dimension_label"),
                "holdings_count": (etf_bundle or {}).get("holdings_shown")
                if etf_bundle else financial_inputs.get("holdings_count"),
                "holdings_scored_count": (etf_bundle or {}).get("holdings_scored_count")
                if etf_bundle else financial_inputs.get("holdings_scored_count"),
                "holdings_weight_covered_pct": financial_inputs.get("holdings_weight_covered_pct"),
                "holdings_quality_score": financial_inputs.get("holdings_quality_score"),
                "top_holding_weight_pct": financial_inputs.get("top_holding_weight_pct"),
                "top_10_weight_pct": (etf_bundle or {}).get("top10_weight_pct")
                if etf_bundle else financial_inputs.get("top_10_weight_pct"),
                "total_holdings": (etf_bundle or {}).get("total_holdings"),
                "holdings": (etf_bundle or {}).get("holdings") if etf_bundle else financial_inputs.get("holdings"),
            },
            "news_sentiment": {
                "score": risk_dims.get("news_sentiment"),
                "limited_data": (etf_bundle.get("sector_strength_score") is None) if etf_bundle else _limited_data_flag(news_inputs),
                "limited_reason": _limited_data_reason(news_inputs),
                "article_count_7d": (
                    news_inputs.get("article_count_7d")
                    if news_inputs.get("article_count_7d") is not None
                    else len(seven_day_articles)
                ),
                "volume_signal": bool(news_inputs.get("volume_signal")),
                "weighted_score": news_inputs.get("weighted_score"),
                # ETFs do not ingest news — Sector Strength is performance-based.
                "articles": [] if etf_bundle else article_payloads,
                "article_histogram_14d": [] if etf_bundle else _article_histogram(fourteen_day_articles),
                "sentiment_distribution": [] if etf_bundle else _sentiment_distribution(fourteen_day_articles),
                # ETF Sector Strength: what the fund tracks + performance vs market/sectors.
                "dimension_label": "Sector Strength" if etf_bundle else None,
                "theme": (etf_bundle or {}).get("theme"),
                "category": (etf_bundle or {}).get("category"),
                "benchmark": (etf_bundle or {}).get("benchmark"),
                "sectors": (etf_bundle or {}).get("sectors"),
                "performance": (etf_bundle or {}).get("performance"),
                "sector_strength_score": (etf_bundle or {}).get("sector_strength_score"),
            },
            "macro_exposure": {
                "score": risk_dims.get("macro_exposure"),
                "r_squared": (
                    macro_inputs.get("r_squared")
                    if macro_inputs.get("r_squared") is not None
                    else macro_regression.get("r_squared")
                ),
                "trading_days_used": (
                    macro_inputs.get("trading_days_used")
                    if macro_inputs.get("trading_days_used") is not None
                    else macro_regression.get("trading_days_used")
                ),
                "limited_data": bool(
                    macro_inputs.get("limited_data")
                    if macro_inputs.get("limited_data") is not None
                    else macro_regression.get("limited_data")
                ),
                "limited_reason": _limited_data_reason(macro_inputs),
                "as_of_date": macro_inputs.get("as_of_date") or macro_regression.get("as_of_date"),
                "coefficients": macro_inputs.get("coefficients") or macro_regression.get("coefficients") or {},
                "contributions": macro_inputs.get("contributions") or macro_regression.get("contributions") or {},
                "macro_daily_vol": macro_inputs.get("macro_daily_vol") or macro_regression.get("macro_daily_vol"),
                "top_factor": macro_inputs.get("top_factor") or macro_regression.get("top_factor"),
                "factor_exposures": factor_exposures,
                "current_factor_levels": macro_inputs.get("current_factor_levels") or {},
                "factor_levels": macro_inputs.get("current_factor_levels") or {},
                "narrative": macro_inputs.get("narrative"),
            },
            "sector_exposure": {
                "score": risk_dims.get("sector_exposure"),
                "limited_data": _limited_data_flag(sector_inputs),
                "limited_reason": _limited_data_reason(sector_inputs),
                "sector": sector_inputs.get("sector") or metadata.get("sector"),
                "sector_etf": sector_inputs.get("sector_etf"),
                "sector_beta": sector_inputs.get("sector_beta"),
                "sector_momentum_30d": sector_inputs.get("sector_momentum_30d"),
                "sector_breadth": sector_inputs.get("sector_breadth"),
                "relative_strength_30d": sector_inputs.get("relative_strength_30d"),
                "relative_strength_90d": sector_inputs.get("relative_strength_90d"),
                "correlation_to_sector": sector_inputs.get("correlation_to_sector"),
                "sector_change_90d": sector_inputs.get("sector_change_90d"),
                # ETF Concentration: top-holding weight breakdown + sector/geography
                # mix + full holdings table. Present only for funds.
                "dimension_label": "Concentration" if etf_bundle else sector_inputs.get("dimension_label"),
                "holdings_count": sector_inputs.get("holdings_count"),
                "top_holding_weight_pct": sector_inputs.get("top_holding_weight_pct"),
                "top_10_weight_pct": (etf_bundle or {}).get("top10_weight_pct")
                if etf_bundle else sector_inputs.get("top_10_weight_pct"),
                "concentration_score": sector_inputs.get("concentration_score"),
                "total_holdings": (etf_bundle or {}).get("total_holdings"),
                "sectors": (etf_bundle or {}).get("sectors"),
                "countries": (etf_bundle or {}).get("countries"),
                "holdings": (etf_bundle or {}).get("holdings"),
                "narrative": sector_inputs.get("narrative"),
                "peer_comparisons": peers,
                "sector_median_comparison": {
                    metric: sector_medians.get(metric)
                    for metric in ("pe_ratio", "beta", "volatility_proxy")
                    if sector_medians.get(metric)
                },
            },
            "volatility": {
                "score": risk_dims.get("volatility"),
                "limited_data": _limited_data_flag(volatility_inputs),
                "limited_reason": _limited_data_reason(volatility_inputs),
                "realized_vol_30d": volatility_inputs.get("realized_vol_30d"),
                "realized_vol_90d": volatility_inputs.get("realized_vol_90d"),
                "vol_ratio": volatility_inputs.get("vol_ratio"),
                "max_drawdown_252d": volatility_inputs.get("max_drawdown_252d"),
                "beta_to_spy": volatility_inputs.get("beta_to_spy"),
                "price_analytics": volatility_inputs.get("price_analytics") or {},
                "iv_rank": None,
                "implied_volatility": None,
                "iv_source": None,
                "factor_levels": {
                    "realized_vol_30d": volatility_inputs.get("realized_vol_30d"),
                    "realized_vol_90d": volatility_inputs.get("realized_vol_90d"),
                    "vol_ratio": volatility_inputs.get("vol_ratio"),
                },
                "as_of_date": volatility_inputs.get("as_of_date"),
            },
        },
        "composite": {
            "score": snapshot.get("composite_score") or snapshot.get("safety_score"),
            "grade": snapshot.get("grade"),
            "methodology_version": snapshot.get("methodology_version"),
        },
        # About section: business summary (stocks) / fund overview (ETFs), plus the
        # fund's structured profile for the ETF About + Sector Strength screens.
        "profile": {
            "is_etf": is_etf,
            "name": metadata.get("company_name"),
            "description": metadata.get("description"),
            "sector": metadata.get("sector"),
            "industry": metadata.get("industry"),
            "theme": (etf_bundle or {}).get("theme"),
            "category": (etf_bundle or {}).get("category"),
            "benchmark": (etf_bundle or {}).get("benchmark"),
            "total_holdings": (etf_bundle or {}).get("total_holdings"),
            "aum": (etf_bundle or {}).get("aum"),
            "pe_ratio": (etf_bundle or {}).get("pe_ratio"),
            "sectors": (etf_bundle or {}).get("sectors"),
            "countries": (etf_bundle or {}).get("countries"),
            "performance": (etf_bundle or {}).get("performance"),
        },
    }


@router.get("/{ticker}/methodology")
async def get_ticker_methodology(
    ticker: str,
    user_id: str = Depends(get_user_id),
):
    """Return cached methodology data for a ticker.

    Returns only what is already stored in ticker_risk_snapshots and
    shared_ticker_events — no live Polygon API calls are made. If a
    dimension's cached inputs are absent the field is returned as null
    rather than blocking on a slow computation.
    """
    supabase = get_supabase()
    upper = ticker.upper()
    return await asyncio.to_thread(_build_methodology_response, supabase, upper, user_id)
