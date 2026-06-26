"""Operational + data-integrity monitor.

Two historically-silent failure classes motivated this job:
  1. Jobs that quietly stop (weekly_fundamentals_sweep never ran; two dailies failed for
     days as unknown_job) with no cadence alert.
  2. Dimensions that read fresh/non-null while their source tables are empty or stale, or
     whose distribution collapses to a near-constant (degenerate macro, A-grade pile-up).

There is no external paging channel wired up, so "alerting" here = emit prominent WARN
logs and finish this job_run with status='failed' when any critical issue is found, so the
failure is visible in job_runs (and to this same cadence check on the next run).

Invoke: python -m app.jobs.run daily_ops_monitor
"""
from __future__ import annotations

import logging
import statistics
from datetime import date, datetime, timezone, timedelta

from app.services.alerting import ping_heartbeat, send_alert
from app.services.supabase import get_supabase

logger = logging.getLogger(__name__)

# Expected cadence (hours) for each scheduled job. Exceeding it == stale.
JOB_CADENCE_HOURS: dict[str, float] = {
    "daily_macro_snapshot": 30,
    "daily_sector_snapshot": 30,
    "daily_composite_recompute_universe": 30,
    "daily_portfolio_rollup_per_user": 30,
    "daily_earnings_calendar_refresh": 30,
    "daily_eod_price_capture": 30,
    "daily_ops_monitor": 30,  # self-check: a skipped monitor run is itself an issue
    "event_fundamentals_pull": 30,
    "active_ticker_news_refresh": 8,  # 4h interval; alert if no run in 8h
    "weekly_peer_groups_recompute": 24 * 8,
    "weekly_sector_medians_recompute": 24 * 8,
    "weekly_volatility_recompute": 24 * 8,
    "weekly_universe_audit": 24 * 8,
    "weekly_fundamentals_sweep": 24 * 8,
    "monthly_macro_regression_refresh": 24 * 32,
    "monthly_etf_holdings_refresh": 24 * 32,
}


def _latest_run_per_job(supabase) -> dict[str, str]:
    """Most recent started_at per job_id from the last ~2000 job_runs rows."""
    latest: dict[str, str] = {}
    rows = (
        supabase.table("job_runs")
        .select("job_id,started_at")
        .order("started_at", desc=True)
        .limit(2000)
        .execute()
        .data
        or []
    )
    for r in rows:
        jid = str(r.get("job_id") or "")
        ts = str(r.get("started_at") or "")
        if jid and jid not in latest and ts:
            latest[jid] = ts
    return latest


def _parse_ts(value: str):
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except Exception:
        return None


def _latest_snapshot_date(supabase) -> str | None:
    rows = (
        supabase.table("ticker_risk_snapshots")
        .select("snapshot_date")
        .order("snapshot_date", desc=True)
        .limit(1)
        .execute()
        .data
        or []
    )
    return str(rows[0]["snapshot_date"]) if rows else None


def _snapshots_for_date(supabase, snapshot_date: str) -> list[dict]:
    return (
        supabase.table("ticker_risk_snapshots")
        .select(
            "ticker,snapshot_date,financial_health,news_sentiment_dim,"
            "macro_exposure_dim,sector_exposure,volatility,safety_score"
        )
        .eq("snapshot_date", snapshot_date)
        .limit(2000)
        .execute()
        .data
        or []
    )


def _news_source_touched_recently(supabase, cutoff: datetime) -> bool:
    rows = (
        supabase.table("shared_ticker_events")
        .select("id")
        .gte("created_at", cutoff.isoformat())
        .limit(1)
        .execute()
        .data
        or []
    )
    return bool(rows)


def _latest_macro_status(supabase) -> tuple[str | None, str | None]:
    rows = (
        supabase.table("macro_regime_snapshots")
        .select("as_of_date,data_status")
        .order("as_of_date", desc=True)
        .limit(1)
        .execute()
        .data
        or []
    )
    if not rows:
        return None, None
    return rows[0].get("data_status"), rows[0].get("as_of_date")


def run() -> dict:
    supabase = get_supabase()
    issues: list[str] = []
    warnings: list[str] = []
    now = datetime.now(timezone.utc)

    # ── 1. Cadence ──────────────────────────────────────────────────────────────
    latest = _latest_run_per_job(supabase)
    for job_id, max_hours in JOB_CADENCE_HOURS.items():
        ts = latest.get(job_id)
        if not ts:
            warnings.append(f"cadence: {job_id} has no job_runs history")
            continue
        parsed = _parse_ts(ts)
        if not parsed:
            continue
        age_h = (now - parsed).total_seconds() / 3600.0
        if age_h > max_hours:
            issues.append(
                f"cadence: {job_id} last ran {age_h:.1f}h ago (limit {max_hours:.0f}h)"
            )

    # ── 2. Recompute completeness + distribution collapse ───────────────────────
    # Check the LATEST snapshot batch, not "today": between UTC midnight and the
    # daily recompute, today has no rows yet — a literal-today check false-alarms
    # every morning. Instead require the most recent batch to be both full and fresh.
    latest_date = _latest_snapshot_date(supabase)
    snaps = _snapshots_for_date(supabase, latest_date) if latest_date else []
    n = len(snaps)
    if not latest_date:
        issues.append("completeness: no ticker_risk_snapshots exist at all")
    else:
        try:
            age_days = (now.date() - date.fromisoformat(latest_date[:10])).days
        except Exception:
            age_days = 0
        if n < 540:
            issues.append(
                f"completeness: latest batch {latest_date} has only {n} snapshots (expected ~546)"
            )
        if age_days > 2:
            issues.append(
                f"completeness: latest snapshot batch is {age_days}d stale ({latest_date})"
            )

    if n:
        dims = {
            "financial_health": [],
            "news_sentiment_dim": [],
            "macro_exposure_dim": [],
            "sector_exposure": [],
            "volatility": [],
        }
        for row in snaps:
            for d in dims:
                v = row.get(d)
                if v is not None:
                    dims[d].append(float(v))
        for d, vals in dims.items():
            non_null = len(vals)
            null_pct = 100.0 * (1 - non_null / n) if n else 0.0
            if null_pct > 25.0:
                warnings.append(f"coverage: {d} NULL for {null_pct:.0f}% of today's snapshots")
            if non_null >= 20:
                sd = statistics.pstdev(vals)
                distinct = len(set(round(v) for v in vals))
                # A near-constant dimension is degenerate (caught the macro collapse).
                if sd < 1.5 or distinct < 4:
                    warnings.append(
                        f"distribution: {d} looks collapsed (stddev={sd:.2f}, distinct={distinct})"
                    )

    # ── 3. News enrichment coverage ─────────────────────────────────────────────
    cutoff = (now - timedelta(days=7)).isoformat()
    usable = _usable_counts(supabase, cutoff)
    if usable:
        below10 = sum(1 for c in usable.values() if c < 10)
        warnings.append(
            f"news: {below10} active tickers below 10 usable fresh articles "
            f"({len(usable)} tickers measured)"
        )

    # ── 4. Source-vs-snapshot consistency ───────────────────────────────────────
    # A dimension that reads non-null across most of the universe while its source
    # table has gone cold is a freshness lie in the making. Catch the divergence.
    news_non_null = sum(1 for row in snaps if row.get("news_sentiment_dim") is not None)
    try:
        news_fresh = _news_source_touched_recently(supabase, now - timedelta(hours=24))
    except Exception:
        news_fresh = True  # never false-alarm on a query hiccup
    if news_non_null > 500 and not news_fresh:
        issues.append(
            "consistency: news dimension non-null on >500 tickers but shared_ticker_events "
            "has no rows ingested in 24h (stale source stamped fresh)"
        )

    try:
        macro_status, macro_as_of = _latest_macro_status(supabase)
    except Exception:
        macro_status, macro_as_of = None, None
    if macro_as_of:
        try:
            macro_age = (now.date() - date.fromisoformat(str(macro_as_of)[:10])).days
        except Exception:
            macro_age = 0
        if macro_age > 4:
            issues.append(f"consistency: macro snapshot stale ({macro_age}d old, {macro_as_of})")
    if macro_status == "price_only":
        warnings.append(
            "consistency: macro snapshot is price_only (proxy levels, no real factor regression)"
        )

    # ── verdict ─────────────────────────────────────────────────────────────────
    for w in warnings:
        logger.warning("[OPS_MONITOR] %s", w)
    for i in issues:
        logger.error("[OPS_MONITOR] CRITICAL %s", i)

    status = "failed" if issues else "completed"

    # External alert only on CRITICAL issues (warnings would page on every run and
    # train the operator to ignore them). Heartbeat fires every run so the monitor's
    # OWN silence is what a dead-man's switch catches.
    if issues:
        send_alert(
            f"ops_monitor: {len(issues)} critical issue(s)",
            level="error",
            context={
                "issues": issues[:10],
                "warnings": warnings[:10],
                "checked_at": now.isoformat(),
            },
        )
    ping_heartbeat(failed=bool(issues))

    return {
        "status": status,
        "items_processed": len(JOB_CADENCE_HOURS),
        "items_failed": len(issues),
        "metadata": {"issues": issues, "warnings": warnings},
    }


def _usable_counts(supabase, cutoff: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    page = 0
    page_size = 1000
    while page <= 50:
        try:
            rows = (
                supabase.table("shared_ticker_events")
                .select("ticker")
                .gte("published_at", cutoff)
                .not_.is_("sentiment_score", "null")
                .range(page * page_size, page * page_size + page_size - 1)
                .execute()
                .data
                or []
            )
        except Exception:
            break
        if not rows:
            break
        for r in rows:
            t = str(r.get("ticker") or "").strip().upper()
            if t:
                counts[t] = counts.get(t, 0) + 1
        if len(rows) < page_size:
            break
        page += 1
    return counts


def run_from_env() -> dict:
    return run()
