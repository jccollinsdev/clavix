"""Compliance regression guards.

Production runs USE_TICKERTICK=true. In that mode the digest / analysis paths must NOT
touch free, non-commercial feeds (Google News RSS, CNBC RSS, Finnhub market-news).
Company news must come from the Tickertick-backed shared_ticker_events pool instead.
These tests fail loudly if a future change reintroduces a free feed into the live path.
"""
import inspect

from app.routes import digest as digest_route
from app.pipeline import scheduler


def test_digest_default_is_tickertick():
    # The module default must keep free feeds off in production.
    from app.services.news_enrichment import USE_TICKERTICK

    assert USE_TICKERTICK is True


def test_digest_macro_sector_rss_is_gated_behind_use_tickertick():
    src = inspect.getsource(digest_route)
    # The free-feed calls must be guarded by `not USE_TICKERTICK`.
    assert "if not USE_TICKERTICK:" in src
    # and the gate must precede the macro RSS call.
    gate_idx = src.index("if not USE_TICKERTICK:")
    macro_idx = src.index("fetch_cnbc_macro_rss(limit=12)")
    assert gate_idx < macro_idx


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
