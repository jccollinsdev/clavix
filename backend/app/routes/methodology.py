from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request

from ..services.supabase import get_supabase

router = APIRouter()


def get_user_id(request: Request) -> str:
    return request.state.user_id


@router.get("/{ticker}/methodology")
async def get_ticker_methodology(
    ticker: str,
    user_id: str = Depends(get_user_id),
):
    supabase = get_supabase()
    upper = ticker.upper()

    metadata_result = (
        supabase.table("ticker_metadata")
        .select("*")
        .eq("ticker", upper)
        .limit(1)
        .execute()
    )
    metadata = metadata_result.data[0] if metadata_result.data else {}

    snapshot_result = (
        supabase.table("ticker_risk_snapshots")
        .select("*")
        .eq("ticker", upper)
        .order("created_at", desc=True)
        .limit(1)
        .execute()
    )
    snapshot = snapshot_result.data[0] if snapshot_result.data else {}

    articles: list[dict[str, Any]] = []
    try:
        articles_result = (
            supabase.table("shared_ticker_events")
            .select("*")
            .eq("ticker", upper)
            .order("published_at", desc=True)
            .limit(20)
            .execute()
        )
        articles = articles_result.data or []
    except Exception:
        pass

    macro_audit = snapshot.get("audit", {}) if isinstance(snapshot.get("audit"), dict) else {}
    macro_reg = macro_audit.get("macro_regression", {})

    fb = snapshot.get("factor_breakdown") or {}
    if isinstance(fb, str):
        import json
        try:
            fb = json.loads(fb)
        except Exception:
            fb = {}
    ai_dims = fb.get("ai_dimensions", {})

    return {
        "ticker": upper,
        "dimensions": {
            "financial_health": {
                "score": ai_dims.get("financial_health"),
                "label": "Financial Health",
                "inputs": {
                    "debt_to_equity": metadata.get("debt_to_equity"),
                    "fcf_margin": metadata.get("fcf_margin"),
                    "interest_coverage": metadata.get("interest_coverage"),
                    "current_ratio": metadata.get("current_ratio"),
                    "revenue_growth_trend": metadata.get("revenue_growth_trend"),
                    "profitability_profile": metadata.get("profitability_profile"),
                    "leverage_profile": metadata.get("leverage_profile"),
                },
                "sources": ["Finnhub stock/metric"],
            },
            "news_sentiment": {
                "score": ai_dims.get("news_sentiment"),
                "label": "News Sentiment",
                "articles": [
                    {
                        "id": a.get("id"),
                        "title": a.get("title"),
                        "source": a.get("source"),
                        "sentiment_score": a.get("sentiment_score"),
                        "sentiment_reason": a.get("sentiment_reason"),
                        "source_tier": a.get("source_tier"),
                        "recency_weight": a.get("recency_weight"),
                        "source_weight": a.get("source_weight"),
                        "impact_tag": a.get("impact_tag"),
                        "tldr": a.get("tldr"),
                        "published_at": a.get("published_at"),
                    }
                    for a in articles[:15]
                ],
                "article_count": len(articles),
                "sources": ["Google News RSS", "MiniMax LLM"],
            },
            "macro_exposure": {
                "score": ai_dims.get("macro_exposure"),
                "label": "Macro Exposure",
                "regression": macro_reg if macro_reg.get("coefficients") else None,
                "beta_proxy": metadata.get("beta"),
                "macro_sensitivity": metadata.get("macro_sensitivity"),
                "sources": ["Polygon daily bars", "MiniMax LLM"],
            },
            "sector_exposure": {
                "score": ai_dims.get("sector_exposure"),
                "label": "Sector Exposure",
                "inputs": {
                    "sector": metadata.get("sector"),
                    "industry": metadata.get("industry"),
                    "market_cap": metadata.get("market_cap"),
                    "beta": metadata.get("beta"),
                },
                "sources": ["Finnhub stock/profile2"],
            },
            "volatility": {
                "score": ai_dims.get("volatility"),
                "label": "Volatility",
                "inputs": {
                    "beta": metadata.get("beta"),
                    "macro_sensitivity": metadata.get("macro_sensitivity"),
                },
                "sources": ["Polygon aggregate bars", "MiniMax LLM"],
            },
        },
        "composite": {
            "grade": snapshot.get("grade"),
            "score": snapshot.get("safety_score"),
            "methodology_version": snapshot.get("methodology_version"),
        },
    }
