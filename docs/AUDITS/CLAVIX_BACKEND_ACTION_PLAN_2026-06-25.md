# Clavix Backend Improvement Action Plan

Date: 2026-06-25. Source: the skeptic audit (`CLAVIX_SKEPTIC_AUDIT_2026-06-25.md`) plus a
7-domain assessment workflow and an adversarial critique pass. This plan is the critique-corrected
synthesis: items the critique proved were already shipped are dropped, and the gaps it found
(recompute scaling wall, two partially-shipped tasks, monitor self-blindness) are added.

Context that drives prioritization: free Polygon/Finnhub tiers, a single 2 GB host, 2 beta users,
pre-launch, ~$68/mo. So "now" = cheap, high-blast-radius, free, and unblocks the north star (every
ticker carries five real dimensions and 10 enriched articles, always). Paid-data spend is deferred
with a documented breakeven, because the one genuinely-fake dimension (macro) can be made real for
$0 with FRED.

Two honest corrections to yesterday's task list, both verified in code:
- The "scrub banned vocabulary" task updated the contract doc but NOT the client strings: "Thin
  data" / "provisional" still ship from `ticker_cache_service.py` (lines 3230, 3246, and others).
- The "per-ticker rotation guarantee" task shipped a stateless neediest-first sort
  (`scheduler.py:5613`), not a persistent cursor. It mitigates starvation but does not guarantee it.

---

## P0: This week (cheap, high blast-radius, free)

1. **Stop production data loss (highest ROI).** Replace `rsync -az --delete` in
   `deploy-prod.yml` with explicit excludes, and capture the current VPS git SHA to a `last_stable`
   marker before sync so a failed health gate can roll back. Pair with enabling DigitalOcean weekly
   snapshots (~$1-2/mo) and confirming the Supabase PITR window. Rationale: the 06-24 deploy already
   erased a production-only pipeline; this is an active, realized data-loss hole, not hypothetical.

2. **Wire real external alerting + a dead-man's switch.** In `ops_monitor.py`, on `status='failed'`
   call `sentry_sdk.capture_message(level='error')` (reuse the pattern already in
   `composite_recompute.py`) and POST to a free Slack incoming webhook. Add a Sentry cron monitor so
   the absence of an ops_monitor check-in alerts: today the monitor can silently fail and nothing
   notices. Without this, every other monitoring investment is dead weight.

3. **Recompute dependency guard.** Before `daily_composite_recompute_universe` writes, assert today's
   `daily_macro_snapshot` and `daily_sector_snapshot` rows exist and succeeded; abort + alert
   otherwise. Today a failed macro snapshot silently produces snapshots with stale inputs stamped
   fresh. A few lines, prevents a whole class of silent corruption.

4. **OOM insurance on the 2 GB box.** Add `mem_limit` + a swap cap in `docker-compose.yml`. Do NOT
   blindly add `uvicorn --workers 2` first: the batch jobs run as separate `docker exec` processes
   (not in the web worker), so workers do not unblock them, and a second worker doubles the API
   memory footprint on a 2 GB box, making OOM more likely. Verify headroom before adding workers.

5. **Finish the two partially-shipped items.** (a) Scrub the surviving client strings
   ("Thin data" -> "Limited data", drop "provisional"/"sources reviewed") in `ticker_cache_service.py`.
   (b) Persist a rotation cursor in a `job_config` row and log per-ticker usable counts to job_runs
   metadata so ops_monitor can assert "<5% of tickers below the 10-article floor".

6. **Thin regression smoke-suite for the just-fixed honesty bugs.** Tests that would have caught the
   exact regressions/false-completions seen here: NULL news must not stamp
   `dimension_last_refreshed`; macro R-squared < 0.10 must take the beta fallback; ops_monitor flags
   no-history / stale-run / distribution-collapse. Pulled into P0 because "completed" just proved it
   does not equal "shipped".

---

## P1: Next (make a fake dimension real, fix the scaling wall, converge coverage)

7. **FRED macro (the marquee free win).** Pull `DGS10` (10Y yield), `BAMLH0A0HYM2` (HY OAS), and a
   real DXY series from FRED (free, unlimited, daily) into `macro_regime_snapshots`, then refit the
   252-day regression in `jobs/macro_regression.py` with the real factor trio instead of the
   TLT/UUP/USO/VIXY ETF proxies. Converts the one genuinely-degenerate dimension (R-squared 0.019)
   into a real signal at $0. Caveat: sell it as "real factors", not "guaranteed high R-squared".

8. **The recompute scaling wall (the critique's headline omission).** `composite_recompute.py:185`
   is a flat sequential loop calling `refresh_ticker_snapshot()` one ticker at a time, each doing
   ~15-20 sequential Supabase round-trips. THIS is the 110-140 min runtime and the OOM-mid-run risk,
   not Polygon rate limits, so no paid tier fixes it. Free fix: batch/`asyncio.gather` the per-ticker
   Supabase hops and run the outer loop with bounded concurrency. Biggest engineering lever on the
   board and currently unaddressed.

9. **Converge news to 10 enriched per ticker.** Headline-only body recovery (retry with backoff +
   UA rotation, evaluate jina.ai free reader for blocked domains), a nightly TLDR/key_implications
   backfill targeting fresh success-extracted rows with gaps, and ingestion-time dedup
   (normalized-URL + headline fuzzy match) with per-tier source-quality gating before spending the
   article budget.

10. **Monitoring depth (after FRED).** Source-vs-snapshot consistency monitor (a dimension non-null
    on >500 tickers must have a source table touched in 24h; macro must not be `price_only`); a
    per-ticker coverage SLO table written daily; ops_monitor every 4h with a cron exit-code callback
    so hangs surface within 4h instead of a day; structured job metrics (duration, throughput,
    failure categories) with per-job SLOs.

11. **Provider-degradation detection.** Centralize provider rate-limiting (backoff + circuit breaker)
    and alert when a Finnhub/Polygon sweep returns < 100 successful tickers. The recurring live
    incidents (Finnhub 429, Polygon auth cascade) are exactly this, undetected.

12. **Quality-weighted dimension averaging (strictly AFTER FRED).** Weight each dimension by signal
    confidence (financial by input completeness, news by article count, macro by R-squared) to break
    the residual A-grade clustering. Must follow FRED, or it just down-weights a fake macro instead
    of fixing it. Low user impact pre-launch, so it sits behind the scaling wall.

---

## P2: Later (deferred with reason, paid, or scale-gated)

13. **Deep-analysis tier + earnings-shock detection.** Async low-priority `what_happened` /
    `scenario_summary` for the ~5-10% major-event articles; a post-market job flagging >5% EPS/rev
    surprises or guidance cuts as a new alert type.

14. **Paid data, gated on ~15 Pro subs.** Polygon Professional (real options IV, higher limits) is
    ~$250/mo and deeper Finnhub ~$40/mo; an 18x data-cost jump is unjustified at 2 users. Document
    the breakeven in CLAVIX_TRUTH and keep `ENABLE_INTRADAY_SNAPSHOTS` false until then. A secondary
    fundamentals/news provider (AlphaVantage/Tiingo) fallback also waits here.

15. **APScheduler migration.** Move heavy jobs off crontab into APScheduler with DST-aware triggers
    and real dependency guards (skip recompute + P0-alert if macro/sector failed). Replaces the
    manual UTC-offset crontab. Higher effort; the P0 dependency guard (#3) covers the urgent half now.

16. **DR runbook + secrets hygiene.** Full RPO/RTO runbook and a test restore (the cheap snapshot
    action is already pulled into P0 #1); `detect-secrets` in pre-commit/CI, a 90-day rotation
    runbook, and a no-shell deploy-only SSH user.

17. **Signal + schema polish.** ETF holdings-based sector score and an IV-percentile microstructure
    signal (both from data already fetched); retire the legacy `event_analyses` dual-write and drop
    the 11 always-empty article columns (after a 2-week clean window + a guard test); expose macro
    R-squared and `attempted_at` vs `last_successful_refresh_at` in the Pro methodology drill-down.

---

## The critical path, in one line

Close the realized data-loss hole and turn on alerting (P0 #1-2) -> make macro real with free FRED
and break the sequential-recompute scaling wall (P1 #7-8) -> converge news coverage and prove it
with source-consistency + coverage SLO monitors (P1 #9-10) -> only then weigh paid data, gated on
revenue (P2 #14). The single highest-leverage free engineering item nobody had on the list is the
recompute parallelization (#8); the single highest-ROI 30-minute fix is the rsync + snapshot
data-loss insurance (#1).
