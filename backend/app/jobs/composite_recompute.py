from __future__ import annotations

import logging
import os
import smtplib
import time
from datetime import date, datetime, timedelta, timezone
from email.mime.text import MIMEText
from typing import Any

from app.services.supabase import get_supabase
from app.services.ticker_cache_service import (
    list_active_sp500_tickers,
    refresh_ticker_snapshot,
)

logger = logging.getLogger(__name__)


def _send_job_failure_alert(result: dict) -> None:
    """Fire a failure alert via Sentry and optionally email when recompute has failures.

    Email is sent only when ALERT_EMAIL, SMTP_HOST, SMTP_USER, SMTP_PASS are set.
    Sentry is used when available regardless.
    """
    items_failed = result.get("items_failed", 0)
    if not items_failed:
        return

    # Rate against EVERYTHING we looked at (processed + failed + skipped-fresh), not just
    # processed+failed. Otherwise a day where most tickers were already fresh makes a
    # handful of transient Polygon resets look like a double-digit failure rate.
    processed = result.get("items_processed", 0)
    skipped = result.get("items_skipped", 0)
    failure_rate = items_failed / max(processed + items_failed + skipped, 1)

    # Don't page on transient single-digit network blips. Only escalate when failures are
    # material in absolute or relative terms; otherwise just log and move on.
    abs_threshold = int(os.getenv("RECOMPUTE_ALERT_ABS_THRESHOLD", "25"))
    rate_threshold = float(os.getenv("RECOMPUTE_ALERT_RATE_THRESHOLD", "0.05"))
    if items_failed < abs_threshold and failure_rate < rate_threshold:
        logger.warning(
            "composite_recompute: %d transient failures (%.1f%% of %d) — below alert "
            "threshold, not paging.",
            items_failed, failure_rate * 100, processed + items_failed + skipped,
        )
        return

    subject = (
        f"[Clavix] composite_recompute: {items_failed} failures "
        f"({failure_rate:.0%}) on {date.today().isoformat()}"
    )
    body_lines = [
        subject,
        "",
        f"Processed: {result.get('items_processed', 0)}",
        f"Failed:    {items_failed}",
        f"Skipped:   {result.get('items_skipped', 0)}",
        "",
        "Failed tickers:",
    ]
    for entry in (result.get("metadata") or {}).get("failed", []):
        body_lines.append(f"  {entry.get('ticker')}: {entry.get('error')}")
    body = "\n".join(body_lines)

    # Sentry + Slack via the centralized alerting module (no-ops if unconfigured).
    try:
        from app.services.alerting import send_alert

        send_alert(
            subject,
            level="error",
            context={
                "processed": result.get("items_processed", 0),
                "failed": items_failed,
                "failure_rate": f"{failure_rate:.0%}",
                "first_failed": [
                    e.get("ticker") for e in (result.get("metadata") or {}).get("failed", [])[:10]
                ],
            },
        )
    except Exception:
        pass

    # Email alert (optional — set ALERT_EMAIL + SMTP_HOST + SMTP_USER + SMTP_PASS)
    alert_email = os.getenv("ALERT_EMAIL", "").strip()
    smtp_host = os.getenv("SMTP_HOST", "").strip()
    smtp_user = os.getenv("SMTP_USER", "").strip()
    smtp_pass = os.getenv("SMTP_PASS", "").strip()
    if alert_email and smtp_host and smtp_user and smtp_pass:
        try:
            msg = MIMEText(body)
            msg["Subject"] = subject
            msg["From"] = smtp_user
            msg["To"] = alert_email
            with smtplib.SMTP(smtp_host, int(os.getenv("SMTP_PORT", "587"))) as s:
                s.starttls()
                s.login(smtp_user, smtp_pass)
                s.send_message(msg)
            logger.info("composite_recompute: failure alert email sent to %s", alert_email)
        except Exception as exc:
            logger.warning("composite_recompute: failed to send alert email: %s", exc)

_MAX_RETRIES = 2
_RETRY_BASE_DELAY_SECONDS = 3


DIMENSION_KEYS = (
    "financial_health",
    "news_sentiment",
    "macro_exposure",
    "sector_exposure",
    "volatility",
)
FRESHNESS_HOURS = 24
DEFAULT_BATCH_SIZE = 15
DEFAULT_INTER_BATCH_DELAY_SECONDS = 5


def _coerce_target_date(value: date | str | None) -> date:
    if value is None:
        return date.today()
    if isinstance(value, date):
        return value
    return date.fromisoformat(str(value))


def _parse_timestamp(value: Any) -> datetime | None:
    if not value:
        return None
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc)
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    return None


def snapshot_dimensions_fresh(
    snapshot: dict[str, Any] | None,
    *,
    now: datetime | None = None,
    freshness_hours: int = FRESHNESS_HOURS,
) -> bool:
    if not snapshot:
        return False
    refreshed = snapshot.get("dimension_last_refreshed") or {}
    if not isinstance(refreshed, dict):
        return False
    cutoff = (now or datetime.now(timezone.utc)) - timedelta(hours=freshness_hours)
    for key in DIMENSION_KEYS:
        refreshed_at = _parse_timestamp(refreshed.get(key))
        if refreshed_at is None or refreshed_at < cutoff:
            return False
    return True


def _latest_snapshots_for_date(
    supabase,
    tickers: list[str],
    *,
    snapshot_date: date,
) -> dict[str, dict[str, Any]]:
    if not tickers:
        return {}
    rows = (
        supabase.table("ticker_risk_snapshots")
        .select("ticker,dimension_last_refreshed,analysis_as_of,methodology_version")
        .eq("snapshot_date", snapshot_date.isoformat())
        .in_("ticker", tickers)
        .execute()
        .data
        or []
    )
    latest: dict[str, dict[str, Any]] = {}
    for row in rows:
        ticker = str(row.get("ticker") or "").upper()
        if ticker and ticker not in latest:
            latest[ticker] = row
    return latest


# Upstream snapshots may legitimately lag a few calendar days (weekends/holidays
# have no new market bars), so the guard only fires when inputs are STALE beyond
# this window, not merely "not today".
DEPENDENCY_MAX_STALENESS_DAYS = 4


def _check_upstream_dependencies(
    supabase, snapshot_date: date, *, max_staleness_days: int = DEPENDENCY_MAX_STALENESS_DAYS
) -> tuple[bool, str]:
    """Assert macro + sector snapshot inputs exist and are fresh before recompute.

    Without this, a failed macro/sector snapshot job silently produces composite
    snapshots built on stale inputs but stamped fresh — exactly the silent-corruption
    class the audit flagged. Returns (ok, reason).
    """
    issues: list[str] = []

    def _latest_date(table: str, date_col: str) -> date | None:
        try:
            rows = (
                supabase.table(table)
                .select(date_col)
                .order(date_col, desc=True)
                .limit(1)
                .execute()
                .data
                or []
            )
        except Exception as exc:  # pragma: no cover - network dependent
            issues.append(f"{table}: query failed ({exc})")
            return None
        if not rows:
            issues.append(f"{table}: no rows at all")
            return None
        raw = rows[0].get(date_col)
        try:
            return date.fromisoformat(str(raw)[:10])
        except Exception:
            issues.append(f"{table}: unparseable {date_col}={raw!r}")
            return None

    macro_date = _latest_date("macro_regime_snapshots", "as_of_date")
    if macro_date is not None:
        age = (snapshot_date - macro_date).days
        if age > max_staleness_days:
            issues.append(
                f"macro snapshot stale: latest as_of_date {macro_date} is {age}d "
                f"before target {snapshot_date}"
            )

    sector_date = _latest_date("sector_regime_snapshots", "snapshot_date")
    if sector_date is not None:
        age = (snapshot_date - sector_date).days
        if age > max_staleness_days:
            issues.append(
                f"sector snapshot stale: latest snapshot_date {sector_date} is {age}d "
                f"before target {snapshot_date}"
            )

    return (not issues, "; ".join(issues))


def run(
    *,
    limit: int | None = None,
    batch_size: int = DEFAULT_BATCH_SIZE,
    inter_batch_delay_seconds: int = DEFAULT_INTER_BATCH_DELAY_SECONDS,
    target_date: date | str | None = None,
    force_refresh: bool = False,
) -> dict:
    snapshot_date = _coerce_target_date(target_date)
    supabase = get_supabase()

    # ── Dependency guard ────────────────────────────────────────────────────────
    # Only enforced for "today" runs (historical backfills legitimately have old
    # inputs); bypassable via env for deliberate backfills.
    guard_skipped = os.getenv(
        "COMPOSITE_RECOMPUTE_SKIP_DEPENDENCY_GUARD", ""
    ).lower() in ("1", "true", "yes")
    if not guard_skipped and snapshot_date >= date.today():
        ok, reason = _check_upstream_dependencies(supabase, snapshot_date)
        if not ok:
            logger.critical(
                "composite_recompute ABORTED: upstream dependency check failed: %s", reason
            )
            try:
                from app.services.alerting import send_alert

                send_alert(
                    "composite_recompute aborted: stale upstream inputs",
                    level="critical",
                    context={"reason": reason, "target_date": snapshot_date.isoformat()},
                )
            except Exception:
                pass
            return {
                "status": "failed",
                "items_processed": 0,
                "items_skipped": 0,
                "items_failed": 0,
                "metadata": {
                    "aborted": "dependency_guard",
                    "reason": reason,
                    "target_date": snapshot_date.isoformat(),
                },
            }

    tickers = list_active_sp500_tickers(supabase, limit=limit)
    date_snapshots = _latest_snapshots_for_date(
        supabase,
        tickers,
        snapshot_date=snapshot_date,
    )

    # force_refresh bypasses both the dimension freshness check and the
    # existing-AI-snapshot early-return in refresh_ticker_snapshot, so Polygon
    # bar data and real sector_beta / beta_to_spy are always recomputed.
    effective_job_type = "manual_refresh" if force_refresh else "daily"

    processed = 0
    skipped = 0
    failed: list[dict[str, str]] = []
    batch_size = max(1, int(batch_size))
    concurrency = max(1, int(os.getenv("COMPOSITE_RECOMPUTE_CONCURRENCY", "6")))

    def _process_ticker(ticker: str) -> tuple[str, str, str | None]:
        """Return (outcome, ticker, error); outcome in {processed, skipped, failed}."""
        if not force_refresh and snapshot_dimensions_fresh(date_snapshots.get(ticker)):
            return ("skipped", ticker, None)
        last_exc: Exception | None = None
        for attempt in range(_MAX_RETRIES + 1):
            try:
                refresh_ticker_snapshot(
                    supabase,
                    ticker=ticker,
                    job_type=effective_job_type,
                    snapshot_date=snapshot_date,
                )
                return ("processed", ticker, None)
            except Exception as exc:
                last_exc = exc
                if attempt < _MAX_RETRIES:
                    time.sleep(_RETRY_BASE_DELAY_SECONDS * (2 ** attempt))
        return ("failed", ticker, str(last_exc))

    def _record(outcome: str, ticker: str, error: str | None) -> None:
        nonlocal processed, skipped
        if outcome == "processed":
            processed += 1
        elif outcome == "skipped":
            skipped += 1
        else:
            failed.append({"ticker": ticker, "error": error or "unknown"})
            logger.error("composite_recompute: ticker %s failed: %s", ticker, error)

    if concurrency <= 1:
        for index, ticker in enumerate(tickers):
            _record(*_process_ticker(ticker))
            if (
                inter_batch_delay_seconds > 0
                and (index + 1) % batch_size == 0
                and index + 1 < len(tickers)
            ):
                time.sleep(inter_batch_delay_seconds)
    else:
        # refresh_ticker_snapshot is I/O-bound (Supabase + cached Polygon) and LLM-free,
        # so bounded threads cut wall-clock ~Nx. ThreadPoolExecutor.map yields results to
        # this (main) thread in order, so the counters update single-threaded; the
        # container mem_limit caps blast radius on the 2 GB host.
        from concurrent.futures import ThreadPoolExecutor

        logger.info(
            "composite_recompute: %d tickers at concurrency=%d", len(tickers), concurrency
        )
        with ThreadPoolExecutor(max_workers=concurrency) as executor:
            for outcome, ticker, error in executor.map(_process_ticker, tickers):
                _record(outcome, ticker, error)

    if failed:
        failure_rate = len(failed) / max(len(tickers), 1)
        log_fn = logger.critical if failure_rate >= 0.1 else logger.warning
        log_fn(
            "composite_recompute FINISHED with %d failures / %d tickers (%.0f%%). "
            "First 10 failed: %s",
            len(failed), len(tickers), failure_rate * 100,
            [f["ticker"] for f in failed[:10]],
        )

    # WS-J: a handful of transient Polygon/Supabase resets out of ~546 is a healthy run,
    # not a "partial"/failure. Treat >=95% success as completed (completed-with-errors)
    # so monitoring stops crying wolf; only flag partial/failed below that bar.
    _attempted = processed + len(failed)
    _success_rate = processed / _attempted if _attempted else 1.0
    if not failed:
        _status = "completed"
    elif processed > 0 and _success_rate >= 0.95:
        _status = "completed_with_errors"
    elif processed > 0:
        _status = "partial"
    else:
        _status = "failed"

    result = {
        "status": _status,
        "items_processed": processed,
        "items_skipped": skipped,
        "items_failed": len(failed),
        "metadata": {
            "requested": len(tickers),
            "target_date": snapshot_date.isoformat(),
            "force_refresh": force_refresh,
            "failed": failed[:25],
        },
    }
    _send_job_failure_alert(result)
    return result


def run_from_env() -> dict:
    limit = os.getenv("COMPOSITE_RECOMPUTE_LIMIT")
    target_date = os.getenv("COMPOSITE_RECOMPUTE_TARGET_DATE")
    force_refresh = os.getenv("COMPOSITE_RECOMPUTE_FORCE_REFRESH", "").lower() in (
        "1", "true", "yes",
    )
    return run(
        limit=int(limit) if limit else None,
        target_date=target_date or None,
        force_refresh=force_refresh,
    )
