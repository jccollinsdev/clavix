"""Regression tests for the 2026-06-30 pre-launch fixes:

1. Only fully-enriched articles (brief + risk-signal score + key implications)
   are surfaced to the app.
2. Driver cards never show two opposing cards for the same theme.
"""
from __future__ import annotations

from app.pipeline.analysis_utils import article_has_full_enrichment
from app.pipeline.position_report_builder import _build_driver_cards


def _complete_article(**overrides):
    row = {
        "tldr": "Company beat revenue estimates and raised guidance.",
        "what_it_means": "Estimates likely revise upward.",
        "sentiment_score": 72,
        "key_implications": ["Guidance raised", "Margins expanding"],
    }
    row.update(overrides)
    return row


class TestArticleDisplayGate:
    def test_complete_article_passes(self):
        assert article_has_full_enrichment(_complete_article()) is True

    def test_missing_brief_hidden(self):
        assert article_has_full_enrichment(
            _complete_article(tldr=None, what_it_means=None)
        ) is False

    def test_missing_sentiment_score_hidden(self):
        # This is the "risk signal score won't show" class of article.
        assert article_has_full_enrichment(
            _complete_article(sentiment_score=None)
        ) is False

    def test_missing_key_implications_hidden(self):
        assert article_has_full_enrichment(
            _complete_article(key_implications=[])
        ) is False

    def test_what_it_means_alone_counts_as_brief(self):
        assert article_has_full_enrichment(
            _complete_article(tldr=None)
        ) is True

    def test_json_encoded_key_implications_tolerated(self):
        assert article_has_full_enrichment(
            _complete_article(key_implications='["Guidance raised"]')
        ) is True

    def test_headline_only_row_hidden(self):
        row = {
            "tldr": None,
            "what_it_means": None,
            "sentiment_score": None,
            "key_implications": [],
            "analysis_status": "headline_only",
        }
        assert article_has_full_enrichment(row) is False


class TestNoOpposingDriverCards:
    def test_same_theme_opposing_directions_collapse_to_one(self):
        # Two events on the same regulatory theme with opposite directions.
        events = [
            {
                "id": "e1",
                "title": "Regulator drops probe into the company",
                "summary": "The SEC closed its inquiry, removing a legal overhang for the company.",
                "scenario_summary": "The SEC closed its inquiry, removing a legal overhang and reducing the risk premium.",
                "source": "Reuters",
                "source_url": "https://example.com/e1",
                "published_at": "2026-06-29T12:00:00+00:00",
                "created_at": "2026-06-29T12:00:00+00:00",
                "confidence": 0.9,
                "significance": "major",
                "risk_direction": "improving",
            },
            {
                "id": "e2",
                "title": "New regulatory lawsuit filed against the company",
                "summary": "A fresh lawsuit alleges regulatory violations, raising legal cost exposure for the company.",
                "scenario_summary": "A fresh lawsuit alleges regulatory violations, raising legal cost exposure.",
                "source": "Bloomberg",
                "source_url": "https://example.com/e2",
                "published_at": "2026-06-28T12:00:00+00:00",
                "created_at": "2026-06-28T12:00:00+00:00",
                "confidence": 0.6,
                "significance": "minor",
                "risk_direction": "worsening",
            },
        ]
        cards, state, _src = _build_driver_cards({"status": "ready"}, event_analyses=events)
        themes = [c["theme"] for c in cards]
        # The regulatory theme must appear at most once — no self-contradiction.
        assert themes.count("regulatory_risk") <= 1
