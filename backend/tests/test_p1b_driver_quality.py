from app.pipeline.analysis_utils import (
    score_to_grade,
    grade_direction,
    grade_to_risk_level,
    format_rationale,
    evidence_strength,
    _is_garbled_driver,
    _sanitize_driver_text,
)


def test_evidence_strength_grades():
    assert evidence_strength(0) == "thin"
    assert evidence_strength(1) == "thin"
    assert evidence_strength(2) == "thin"
    assert evidence_strength(3) == "moderate"
    assert evidence_strength(5) == "moderate"
    assert evidence_strength(6) == "strong"


def test_garbled_driver_detection():
    assert _is_garbled_driver("Balanced risk factors") is True
    assert _is_garbled_driver("No dominant risk driver") is True
    assert _is_garbled_driver("No single force dominates") is True
    assert _is_garbled_driver("Nothing urgent") is True
    assert _is_garbled_driver("Risk factors are balanced") is True
    assert _is_garbled_driver("Earnings miss on revenue weakness") is False
    assert _is_garbled_driver("High rate sensitivity") is False
    assert _is_garbled_driver("Valuation stretched vs earnings") is False
    assert _is_garbled_driver("Concentration amplifies downside") is False
    assert _is_garbled_driver("Macro pressure on the sector") is False
    assert _is_garbled_driver("Limited data — fundamentals dominate") is False
    assert _is_garbled_driver("") is True
    assert _is_garbled_driver("ab") is True


def test_sanitize_driver_strips_banned():
    assert "thesis" not in _sanitize_driver_text("The thesis is clear and coverage may change")
    assert "momentum" not in _sanitize_driver_text("Positive momentum drives gains")
    assert "provisional" not in _sanitize_driver_text("This is provisional data")
    assert "coverage" not in _sanitize_driver_text("Limited coverage available")


def test_thin_evidence_forces_fallback():
    result = format_rationale("CCC", "flat", "Risk factors are balanced", source_count=0)
    assert "Limited data" in result
    assert "CCC — High Risk" in result
    assert "balanced" not in result.lower()


def test_garbled_drivers_replaced_with_generic():
    result = format_rationale("B", "flat", "Balanced risk factors", source_count=3)
    lines = [l for l in result.strip().split("\n") if l.strip()]
    assert len(lines) >= 2
    for line in lines[1:]:
        assert not _is_garbled_driver(line), f"Garbled driver still present: {line}"


def test_generic_filler_banned_in_output():
    fillers = [
        "Mixed signals across sectors",
        "Market uncertainty ahead",
        "Ongoing volatility persists",
        "Could impact performance",
    ]
    for filler in fillers:
        result = format_rationale("B", "flat", filler, source_count=3)
        result_lower = result.lower()
        assert "mixed signals" not in result_lower, f"Filler found in: {result}"
        assert "market uncertainty" not in result_lower, f"Filler found in: {result}"
        assert "could impact" not in result_lower, f"Filler found in: {result}"


def test_concrete_drivers_pass_through():
    result = format_rationale("CCC", "down", "Earnings miss on revenue weakness\nSector rotation into defensives", source_count=5)
    assert "CCC — High Risk" in result
    assert "Earnings miss" in result
    assert "Sector rotation" in result


def test_thin_evidence_label_in_output():
    result = format_rationale("B", "flat", None, source_count=1)
    assert "B — Elevated Risk" in result


def test_format_rationale_max_2_drivers_enforced():
    result = format_rationale("CCC", "down", "Driver 1\nDriver 2\nDriver 3\nDriver 4", source_count=5)
    lines = [l for l in result.strip().split("\n") if l.strip()]
    assert len(lines) <= 3


def test_evidence_strength_consistency_with_format():
    for sc in [0, 1, 2, 3, 5, 6, 10]:
        ev = evidence_strength(sc)
        assert ev in ("thin", "moderate", "strong"), f"Invalid strength for {sc}: {ev}"
        if sc <= 2:
            assert ev == "thin"
        elif sc <= 5:
            assert ev == "moderate"
        else:
            assert ev == "strong"


def test_risk_level_mapping_complete():
    levels = {
        "AAA": "Treasury-Grade",
        "AA": "Investment-Grade Safe",
        "A": "Solid",
        "BBB": "Stable, Watch Points",
        "BB": "Mixed Signals",
        "B": "Elevated Risk",
        "CCC": "High Risk",
        "CC": "Severe Risk",
        "C": "Distressed",
        "F": "Failure Mode",
    }
    for grade, expected in levels.items():
        assert grade_to_risk_level(grade) == expected