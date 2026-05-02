from app.pipeline.analysis_utils import (
    score_to_grade,
    grade_direction,
    grade_to_risk_level,
    sanitize_rationale,
    format_rationale,
    evidence_strength,
    clamp_score,
)


def test_score_to_grade():
    assert score_to_grade(90) == "A"
    assert score_to_grade(80) == "A"
    assert score_to_grade(79.9) == "B"
    assert score_to_grade(70) == "B"
    assert score_to_grade(65) == "B"
    assert score_to_grade(64.9) == "C"
    assert score_to_grade(55) == "C"
    assert score_to_grade(50) == "C"
    assert score_to_grade(49.9) == "D"
    assert score_to_grade(40) == "D"
    assert score_to_grade(35) == "D"
    assert score_to_grade(34.9) == "F"
    assert score_to_grade(20) == "F"
    assert score_to_grade(0) == "F"
    assert score_to_grade(-5) == "F"


def test_grade_direction():
    assert grade_direction(70, 60) == "up"
    assert grade_direction(60, 70) == "down"
    assert grade_direction(60, 60) == "flat"
    assert grade_direction(60, 58) == "flat"
    assert grade_direction(60, 62) == "flat"
    assert grade_direction(None, 50) == "flat"
    assert grade_direction(50, None) == "flat"
    assert grade_direction(None, None) == "flat"


def test_clamp_score_no_floor():
    assert clamp_score(90, 0) == 90
    assert clamp_score(50, 0) == 50
    assert clamp_score(20, 0) == 20
    assert clamp_score(0, 0) == 0
    assert clamp_score(-5, 0) == 0
    assert clamp_score(105, 0) == 100
    assert clamp_score(None, 0) == 0


def test_clamp_score_default_on_invalid():
    assert clamp_score(None, 50) == 50
    assert clamp_score("abc", 0) == 0


def test_sanitize_rationale_banned_phrases():
    assert "thesis" not in sanitize_rationale("The thesis is clear.")
    assert "positive momentum" not in sanitize_rationale("Positive momentum drives gains.")
    assert "macro headwinds" not in sanitize_rationale("Macro headwinds ahead.")
    assert "provisional" not in sanitize_rationale("This is provisional data.")
    assert "current read" not in sanitize_rationale("The current read is elevated.")
    assert "coverage" not in sanitize_rationale("Limited coverage available.")
    assert "monitor" not in sanitize_rationale("Monitor this position.")


def test_sanitize_rationale_length_limit():
    long_text = " ".join(["word"] * 100)
    result = sanitize_rationale(long_text)
    assert len(result) <= 280
    assert result.endswith(".")


def test_sanitize_rationale_empty():
    assert sanitize_rationale("") == ""
    assert sanitize_rationale("   ") == ""


def test_stale_grade_regression():
    assert score_to_grade(32.5) == "F", "score 32.5 must map to F, not D (stale clamp_score floor bug)"
    assert score_to_grade(33.8) == "F", "score 33.8 must map to F, not D"
    assert score_to_grade(34.9) == "F", "score 34.9 must map to F"
    assert score_to_grade(35) == "D", "score 35 is the D boundary"
    assert score_to_grade(49.9) == "D", "score 49.9 must map to D, not C (old 50-floor bug)"


# --- P1-A: Credit-rating rationale format contract tests ---


def test_grade_to_risk_level():
    assert grade_to_risk_level("A") == "Low Risk"
    assert grade_to_risk_level("B") == "Moderate Risk"
    assert grade_to_risk_level("C") == "Elevated Risk"
    assert grade_to_risk_level("D") == "High Risk"
    assert grade_to_risk_level("F") == "Severe Risk"
    assert grade_to_risk_level("unknown") == "Elevated Risk"


def test_evidence_strength():
    assert evidence_strength(0) == "thin"
    assert evidence_strength(1) == "thin"
    assert evidence_strength(2) == "thin"
    assert evidence_strength(3) == "moderate"
    assert evidence_strength(5) == "moderate"
    assert evidence_strength(6) == "strong"
    assert evidence_strength(10) == "strong"


def test_format_rationale_header_structure():
    result = format_rationale("C", "down", "Earnings miss on revenue weakness")
    lines = result.strip().split("\n")
    assert len(lines) >= 1

    header = lines[0]
    assert header.startswith("C —")
    assert "Elevated Risk" in header
    assert "↑ worsening" in header


def test_format_rationale_direction_arrows():
    improving = format_rationale("B", "up", "Strong earnings")
    worsening = format_rationale("D", "down", "Weak revenue momentum")
    stable = format_rationale("A", "flat", "Stable profile")

    assert "↓ improving" in improving
    assert "↑ worsening" in worsening
    assert "→ stable" in stable


def test_format_rationale_max_two_drivers():
    long_text = "Driver one is about earnings.\nDriver two is about macro.\nDriver three is about volatility."
    result = format_rationale("C", "flat", long_text)
    lines = [l for l in result.strip().split("\n") if l.strip()]
    assert len(lines) <= 3, f"Expected max 3 lines (1 header + 2 drivers), got {len(lines)}: {lines}"


def test_format_rationale_driver_max_60_chars():
    very_long_driver = "A" * 100
    result = format_rationale("C", "flat", very_long_driver)
    for line in result.strip().split("\n")[1:]:
        assert len(line) <= 60, f"Driver line exceeds 60 chars: '{line}'"


def test_format_rationale_total_max_length():
    text = "\n".join(["This is driver " + str(i) for i in range(5)])
    result = format_rationale("D", "down", text)
    assert len(result) <= 200, f"Total rationale exceeds 200 chars: {len(result)}"


def test_format_rationale_no_banned_words():
    banned = ["may", "could", "would", "suggests", "indicates", "sentiment",
              "momentum", "thesis", "coverage", "provisional"]
    result = format_rationale(
        "C", "flat",
        "Negative company-specific news\nMacro pressure on the sector"
    )
    result_lower = result.lower()
    for word in banned:
        assert word not in result_lower, f"Banned word '{word}' found in: {result}"


def test_format_rationale_grade_matches_header():
    for grade, expected in [("A", "Low Risk"), ("B", "Moderate Risk"),
                             ("C", "Elevated Risk"), ("D", "High Risk"), ("F", "Severe Risk")]:
        result = format_rationale(grade, "flat", "Some driver")
        assert f"{grade} — {expected}" in result, f"Expected '{grade} — {expected}' in: {result}"


def test_format_rationale_fallback_when_no_drivers():
    result = format_rationale("C", "flat", None, source_count=1)
    assert "C — Elevated Risk" in result
    assert "→ stable" in result
    lines = [l for l in result.strip().split("\n") if l.strip()]
    assert len(lines) >= 2


def test_format_rationale_thin_evidence_fallback():
    result = format_rationale("D", "flat", "", source_count=0)
    assert "Limited data" in result
    assert "fundamentals" in result.lower()


def test_format_rationale_extracts_drivers_from_newlines():
    text = "Some header line\nFirst driver\nSecond driver\nThird driver (should be dropped)"
    result = format_rationale("C", "flat", text)
    lines = result.strip().split("\n")
    assert len(lines) <= 3


def test_format_rationale_extracts_drivers_from_sentences():
    text = "Negative news is the primary risk. Macro pressure adds downside."
    result = format_rationale("D", "down", text)
    assert "D — High Risk" in result
    assert "↑ worsening" in result


def test_format_rationale_generic_drivers_by_grade():
    result_f = format_rationale("F", "down", None, scores={"news_sentiment": 20, "macro_exposure": 30, "position_sizing": 40, "volatility_trend": 30})
    assert "F — Severe Risk" in result_f
    assert "↑ worsening" in result_f

    result_a = format_rationale("A", "up", None, scores={"news_sentiment": 90, "macro_exposure": 80, "position_sizing": 85, "volatility_trend": 85})
    assert "A — Low Risk" in result_a
    assert "↓ improving" in result_a


def test_format_rationale_direction_none_defaults_stable():
    result = format_rationale("B", None, "Strong fundamentals")
    assert "→ stable" in result


def test_sanitize_p1_banned_words():
    assert "may" not in sanitize_rationale("This may change things.")
    assert "could" not in sanitize_rationale("Risk could increase.")
    assert "would" not in sanitize_rationale("This would affect the rating.")
    assert "suggests" not in sanitize_rationale("This suggests growth.")
    assert "indicates" not in sanitize_rationale("Data indicates a shift.")


def test_format_rationale_sanitizes_banned_words_in_drivers():
    result = format_rationale(
        "D", "down",
        "The thesis suggests this momentum could shift. The coverage may be provisional."
    )
    result_lower = result.lower()
    assert "thesis" not in result_lower
    assert "momentum" not in result_lower
    assert "coverage" not in result_lower
    assert "provisional" not in result_lower