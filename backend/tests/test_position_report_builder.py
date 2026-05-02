import asyncio

from app.pipeline.position_report_builder import build_position_report


def test_build_position_report_generates_driver_cards(monkeypatch):
    monkeypatch.setattr(
        "app.pipeline.position_report_builder.chatcompletion_text",
        lambda **_kwargs: (
            '{"summary":"Major downside pressure is building.",'
            '"long_report":"Major downside pressure is building.",'
            '"methodology":"Uses event evidence.",'
            '"top_risks":["Margin pressure is rising."],'
            '"watch_items":["Watch for guidance cuts."],'
            '"risk_context":[]}'
        ),
    )

    report = asyncio.run(
        build_position_report(
            {"ticker": "ABBV", "sector": "Healthcare"},
            ["core"],
            [
                {
                    "id": "ev-1",
                    "title": "Earnings beat but guidance cut",
                    "summary": "Revenue beat, but management cut guidance after margin pressure.",
                    "long_analysis": "earnings guidance margin pressure",
                    "source": "Reuters",
                    "source_url": "https://example.com/1",
                    "published_at": "2026-04-24T01:00:00+00:00",
                    "confidence": 0.9,
                    "significance": "major",
                    "risk_direction": "worsening",
                }
            ],
        )
    )

    assert report["driver_cards_state"] == "ready"
    assert report["driver_cards_source"] == "generated"
    assert len(report["driver_cards"]) == 1
    assert report["driver_cards"][0]["theme"] == "earnings_risk"
    assert report["driver_cards"][0]["direction"] == "negative"
    assert report["driver_cards"][0]["source_chips"] == ["Reuters"]
    assert report["driver_cards"][0]["supporting_evidence"][0]["id"] == "ev-1"


def test_build_position_report_uses_insufficient_evidence_fallback():
    report = __import__("asyncio").run(
        build_position_report(
            {"ticker": "ABBV", "sector": "Healthcare"},
            ["core"],
            [],
        )
    )

    assert "not enough recent news" in report["summary"]
    assert "limited-data" in report["long_report"]
    assert report["driver_cards"] == []
    assert report["driver_cards_state"] == "limited"
