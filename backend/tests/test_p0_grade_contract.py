from app.pipeline.analysis_utils import score_to_grade, grade_direction, sanitize_rationale, clamp_score


def test_score_to_grade():
    # Academic A+/A/A- ladder (high score = lower risk).
    assert score_to_grade(95) == "A+"
    assert score_to_grade(90) == "A+"
    assert score_to_grade(89.9) == "A"
    assert score_to_grade(85) == "A"
    assert score_to_grade(84.9) == "A-"
    assert score_to_grade(80) == "A-"
    assert score_to_grade(79.9) == "B+"
    assert score_to_grade(75) == "B+"
    assert score_to_grade(74.9) == "B"
    assert score_to_grade(70) == "B"
    assert score_to_grade(69.9) == "B-"
    assert score_to_grade(65) == "B-"
    assert score_to_grade(64.9) == "C+"
    assert score_to_grade(60) == "C+"
    assert score_to_grade(59.9) == "C"
    assert score_to_grade(55) == "C"
    assert score_to_grade(54.9) == "C-"
    assert score_to_grade(50) == "C-"
    assert score_to_grade(49.9) == "D+"
    assert score_to_grade(45) == "D+"
    assert score_to_grade(44.9) == "D"
    assert score_to_grade(40) == "D"
    assert score_to_grade(39.9) == "D-"
    assert score_to_grade(35) == "D-"
    assert score_to_grade(34.9) == "F"
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
    # Academic scale: F < 35; D- 35-39; D 40-44; D+ 45-49.
    assert score_to_grade(32.5) == "F", "score 32.5 must map to F"
    assert score_to_grade(33.8) == "F", "score 33.8 must map to F"
    assert score_to_grade(34.9) == "F", "score 34.9 must map to F"
    assert score_to_grade(35) == "D-", "score 35 is the D- boundary"
    assert score_to_grade(39.9) == "D-", "score 39.9 must map to D-"
    assert score_to_grade(40) == "D", "score 40 is the D boundary"
    assert score_to_grade(49.9) == "D+", "score 49.9 must map to D+"