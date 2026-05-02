from __future__ import annotations

from ..pipeline.analysis_utils import sanitize_public_analysis_text


def _stringify_details(details: object) -> dict[str, str]:
    if not isinstance(details, dict):
        return {}

    cleaned: dict[str, str] = {}
    for key, value in details.items():
        if value is None:
            continue
        if isinstance(value, str):
            text = value.strip()
        else:
            text = str(value)
        if text:
            cleaned[str(key)] = text
    return cleaned


def enrich_alert_row(alert: dict | None) -> dict:
    row = dict(alert or {})
    alert_type = str(row.get("type") or "").strip().lower()
    ticker = str(row.get("position_ticker") or "").strip().upper()
    previous_grade = str(row.get("previous_grade") or "").strip().upper()
    new_grade = str(row.get("new_grade") or "").strip().upper()

    change_reason = str(row.get("change_reason") or "").strip()
    if not change_reason:
        if alert_type == "grade_change" and previous_grade and new_grade:
            change_reason = (
                f"{ticker} moved from {previous_grade} to {new_grade} after the latest analysis."
                if ticker
                else f"Grade moved from {previous_grade} to {new_grade} after the latest analysis."
            )
        elif alert_type == "portfolio_grade_change" and previous_grade and new_grade:
            change_reason = (
                f"Portfolio risk moved from {previous_grade} to {new_grade}."
            )
        elif alert_type == "safety_deterioration":
            change_reason = "Safety score dropped sharply in the latest analysis run."
        elif alert_type == "major_event":
            change_reason = row.get("message") or "A major event was detected."
        elif alert_type == "concentration_danger":
            change_reason = "Concentration risk crossed the warning threshold."
        elif alert_type == "cluster_risk":
            change_reason = "Multiple holdings now share the same risk cluster."
        elif alert_type == "digest_ready":
            change_reason = (
                "The latest Morning Rating was compiled from the most recent analysis run."
            )
        else:
            change_reason = (
                row.get("message") or "Alert generated from the latest analysis run."
            )

    details = _stringify_details(row.get("change_details"))
    if not details:
        fallback_details = {
            "position_ticker": ticker,
            "previous_grade": previous_grade,
            "new_grade": new_grade,
            "message": str(row.get("message") or "").strip(),
            "analysis_run_id": str(row.get("analysis_run_id") or "").strip(),
        }
        details = {key: value for key, value in fallback_details.items() if value}
    if alert_type == "digest_ready":
        details["message"] = "Your latest Morning Rating is ready."

    message = str(row.get("message") or "").strip()
    if alert_type == "digest_ready":
        message = "Your latest Morning Rating is ready."
    row["message"] = sanitize_public_analysis_text(message)
    row["change_reason"] = sanitize_public_analysis_text(change_reason)
    row["change_details"] = sanitize_public_analysis_text(details)
    return row


def enrich_alert_rows(alerts: list[dict] | None) -> list[dict]:
    return [enrich_alert_row(alert) for alert in (alerts or [])]
