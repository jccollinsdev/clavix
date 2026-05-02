import re
from app.pipeline.analysis_utils import (
    sanitize_rationale,
    sanitize_public_analysis_text,
    format_rationale,
    _P1_BANNED_WORDS,
    _BANNED_PHRASES_PATTERNS,
    _GENERIC_DRIVERS,
    _PUBLIC_ANALYSIS_REPLACEMENTS,
)

P1D_BANNED_TERMS = [
    "thesis",
    "coverage",
    "sentiment",
    "momentum",
    "provisional",
    "macro headwinds",
    "current read",
    "research",
    "analyst",
    "monitor",
]

P1D_BANNED_IN_PROMPTS = [
    "thesis",
    "coverage",
    "sentiment",
    "momentum",
    "provisional",
    "macro headwinds",
    "current read",
    "research",
    "analyst",
    "monitor",
]

P1D_ACCEPTED_REPLACEMENTS = [
    "rating",
    "risk rating",
    "risk driver",
    "grade",
    "downgrade",
    "upgrade",
    "stable",
    "worsening",
    "improving",
    "limited data",
    "evidence strength",
    "rating changed",
    "news signal",
    "data",
    "track",
]


def test_p1d_sanitize_replaces_banned_terms():
    for term in P1D_BANNED_TERMS:
        text = f"The {term} is unclear."
        cleaned = sanitize_rationale(text)
        assert term.lower() not in cleaned.lower(), (
            f"Banned term '{term}' survived sanitization: '{cleaned}'"
        )


def test_p1d_sanitize_does_not_remove_accepted_terms():
    for term in P1D_ACCEPTED_REPLACEMENTS:
        text = f"This uses {term} correctly."
        cleaned = sanitize_rationale(text)
        assert term.lower() in cleaned.lower() or cleaned.strip() == "", (
            f"Accepted term '{term}' was removed: '{cleaned}'"
        )


def test_p1d_public_analysis_replacements_include_banned_terms():
    pattern_texts = " ".join(p for p, _ in _PUBLIC_ANALYSIS_REPLACEMENTS)
    for term in ["thesis", "provisional", "current read", "coverage", "sentiment", "monitor"]:
        assert term in pattern_texts, (
            f"Banned term '{term}' not found in public analysis replacement patterns"
        )


def test_p1d_banned_words_list_includes_p1d_terms():
    single_word_terms = [t for t in P1D_BANNED_TERMS if " " not in t]
    for term in single_word_terms:
        assert term in _P1_BANNED_WORDS, (
            f"Banned term '{term}' not in _P1_BANNED_WORDS"
        )
    multi_word_terms = [t for t in P1D_BANNED_TERMS if " " in t]
    pattern_texts = " ".join(p for p, _ in _BANNED_PHRASES_PATTERNS)
    for term in multi_word_terms:
        assert term in pattern_texts, (
            f"Multi-word banned term '{term}' not in _BANNED_PHRASES_PATTERNS"
        )


def test_p1d_generic_drivers_have_no_banned_terms():
    for category, drivers in _GENERIC_DRIVERS.items():
        for driver in drivers:
            for term in P1D_BANNED_TERMS:
                assert term.lower() not in driver.lower(), (
                    f"Generic driver '{driver}' contains banned term '{term}'"
                )


def test_p1d_format_rationale_excludes_banned_terms():
    rationale = format_rationale(
        grade="C",
        direction="down",
        raw_text="The thesis is weak due to macro headwinds and coverage is thin.",
        scores={"news_sentiment": 40, "macro_exposure": 35, "position_sizing": 70, "volatility_trend": 60},
        source_count=5,
    )
    for term in P1D_BANNED_TERMS:
        assert term.lower() not in rationale.lower(), (
            f"Banned term '{term}' found in rationale: '{rationale}'"
        )


def test_p1d_sanitize_public_analysis_cleans_banned_terms():
    payload = {
        "summary": "The thesis is provisional and coverage is thin.",
        "long_report": "Analyst research suggests monitoring momentum and current read confirms sentiment.",
        "top_risks": ["Macro headwinds are mounting"],
    }
    sanitized = sanitize_public_analysis_text(payload)
    full_text = str(sanitized).lower()
    for term in P1D_BANNED_TERMS:
        assert term.lower() not in full_text, (
            f"Banned term '{term}' found in sanitized output: '{full_text}'"
        )


def test_p1d_coverage_replaced_with_data():
    result = sanitize_public_analysis_text("Coverage is thin in this cycle.")
    assert "coverage" not in result.lower()
    assert "data" in result.lower() or "limited" in result.lower()


def test_p1d_sentiment_replaced_with_news_signal():
    result = sanitize_public_analysis_text("Sentiment is improving.")
    assert "sentiment" not in result.lower()
    assert "news signal" in result.lower()


def test_p1d_thesis_replaced_with_risk_assessment():
    result = sanitize_public_analysis_text("The thesis is unclear.")
    assert "thesis" not in result.lower()
    assert "risk assessment" in result.lower()


def test_p1d_monitor_replaced_with_track():
    result = sanitize_public_analysis_text("Monitor for changes.")
    assert "monitor" not in result.lower()
    assert "track" in result.lower()


def test_p1d_research_replaced_with_rating():
    result = sanitize_public_analysis_text("Research note says to watch.")
    assert "research" not in result.lower()
    assert "rating" in result.lower()