"""Compliance regression guards.

Production runs USE_TICKERTICK=true. COMPANY news must come from the
Tickertick-backed shared_ticker_events pool, never from free company feeds
(Google News RSS, Finnhub company news).

Policy update (2026-06-27, product decision): the MACRO and SECTOR sections of
the digest may use FRED factor snapshots plus CNBC macro/sector *headlines* for
higher-level context. That headline use is intentional and is routed through the
digest_inputs builders, not through per-company free feeds. These tests guard the
remaining hard line: company news stays compliant.
"""
import inspect

from app.routes import digest as digest_route
from app.pipeline import scheduler


def test_digest_default_is_tickertick():
    # The module default must keep free COMPANY feeds off in production.
    from app.services.news_enrichment import USE_TICKERTICK

    assert USE_TICKERTICK is True


def test_digest_macro_sector_use_factor_and_headline_builders():
    src = inspect.getsource(digest_route)
    # Macro and sector context are built from the compliant digest_inputs
    # builders (FRED factor snapshots + CNBC macro/sector headlines), not from
    # per-company free feeds.
    assert "build_factor_macro_context" in src
    assert "build_sector_context" in src
    # The digest route must NOT pull free-feed COMPANY news.
    assert "fetch_google_company_rss" not in src
    assert "fetch_company_news" not in src


def test_analysis_path_has_tickertick_company_news_branch():
    src = inspect.getsource(scheduler)
    # The compliant company-news loader exists and is used in the analysis path.
    assert "_load_company_articles_from_shared_events" in src
    assert "elif USE_TICKERTICK:" in src


def test_universe_news_ingest_routes_through_tickertick():
    from app.services import news_enrichment

    src = inspect.getsource(news_enrichment.ingest_and_enrich_ticker_news)
    # Tickertick must be the first/primary branch; the Google fallback only lives in
    # the USE_TICKERTICK=false legacy block below it.
    assert "if USE_TICKERTICK:" in src
    assert src.index("if USE_TICKERTICK:") < src.index("Legacy Finnhub + Google RSS path")
