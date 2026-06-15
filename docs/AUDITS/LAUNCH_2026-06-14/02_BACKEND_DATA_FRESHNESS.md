# Report 2: Backend Health and Data Freshness (2026-06-14)

Evidence basis: live `/health`, timed curls, live `docker inspect` and logs on the VPS, and live production Supabase SQL.

---

## 1. Service health: good

- `/health` returns ok with apns, snaptrade, minimax, and supabase all configured. `/ping` is fast and DB-free.
- Edge latency through the Cloudflare Tunnel is excellent: `/health` and `/ping` answer in roughly 50 to 75 ms. Authed routes (`/holdings`, `/digest`, `/tickers/{t}`, `/tickers/{t}/risk`, `/tickers/screen`) all return 401 without a token in about 60 ms, which means routing and auth gating are correct and the edge is not your latency problem.
- Container `clavis-backend-1`: RestartCount 0, OOMKilled false, restart policy `unless-stopped`. The several container starts visible tonight are clean redeploys (each `docker compose up` builds a new image and replaces the container), not crash restarts.
- Host: 1.9 GB RAM with about 1.4 GB available, disk 27% used (35 GB free), CPU idle. Backend resident size about 113 MB. Comfortable for now.

Nothing is down. The problems below are data correctness and feature completeness, not outages.

---

## 2. Data freshness: recovered, and the fix is proven

The 06-12 audit found 352 of 507 tickers 8+ days stale because the daily recompute hit a Finnhub free-tier 429 wall after about 100 tickers. That is fixed.

Live freshness today:

| Freshness | Tickers |
|---|---|
| 0 days (today) | 5 |
| 1 day | 498 |
| 8+ days | 4 |

Proof the fix is real, not a one-off: the `weekly_volatility_recompute` job, which walks the full universe the same way, **failed on 06-06** (131 processed, 372 failed) and **succeeded on 06-13** (503 processed, 0 failed, about 103 minutes). Between those two runs, commit `a7d32eb4d` (throttle Finnhub to 60 per minute) plus `c98fbd7ad` (fix a `score_to_grade` UnboundLocalError) landed and were deployed. So the throttle works.

**One caveat worth watching.** The job that actually refreshed everything to "1 day old" was Saturday's weekly volatility recompute, not the daily composite recompute. The daily composite job (`daily_composite_recompute_universe`) last ran 06-12 and failed, and has not run since (it runs on weekdays, and 06-13 and 06-14 are the weekend). Its first post-fix run is the next weekday. The evidence strongly suggests it will pass now (same Finnhub path, same fix, and the volatility job already proves it), but it is not yet proven for that specific job. Watch the next weekday run and confirm it completes.

Per-user freshness is good independently: digests generate daily (3 today, latest 21:28 UTC) and alerts generate daily (11 today). Owned-holding refresh runs on its own path, so a user's own portfolio stays current even when the universe batch is behind.

---

## 3. Data correctness: three real problems

This is where the trust risk lives. None of these show up in the aggregate grade distribution (which looks healthy: AA 12, A 320, BBB 135, BB 30, B 9, CCC 1), so they were missed by audits that only looked at the distribution. They show up per ticker, over time, which is how the ICP looks at the data.

### 3.1 Grade flicker and dimension instability (red)

AAPL, latest six snapshots (financial health, news sentiment, macro, sector, volatility, composite, grade):

| Date | FH | NS | Macro | Sector | Vol | Composite | Grade |
|---|---|---|---|---|---|---|---|
| 06-13 | 62 | 29 | 85 | 82 | 80 | 73.0 | A |
| 06-12 | 62 | 54 | 100 | 68 | 90 | 74.8 | A |
| 06-11 | 88 | 52 | 65 | 68 | 62 | 67.0 | BBB |
| 06-10 | 80 | 45 | 35 | 75 | 55 | 60.0 | BBB |
| 06-09 | 62 | 54 | 100 | 68 | 90 | 74.8 | A |
| 06-08 | 62 | 50 | 100 | 68 | 90 | 74.0 | A |

Problems:
- The grade oscillates A, BBB, BBB, A, A across consecutive days. The truth doc §7 requires hysteresis: a grade change needs the new score at least 3 points across the boundary and held for 2 days. That is plainly not being enforced here, or the underlying scores are noisy enough to defeat it.
- Financial health is specified as quarterly and slow-moving (§6). It bounces 62, 80, 88, 62. A balance sheet does not change that fast. This points to the dimension being recomputed from partial or fallback inputs on some days (likely correlated with whether the upstream calls succeeded that run).
- Macro exposure swings 100, 35, 65, 100, 85 and volatility 90, 55, 62, 90 day to day. The spec says correlations recompute weekly. Daily swings of this size indicate the value is being regenerated from a different (sometimes degraded) code path per run rather than read from a stable weekly base.

Why it matters: this is the exact failure the moat is supposed to prevent. For the daily-checking ICP it reads as "the rating is random," which is worse than no rating.

What to investigate (for a follow-up coding session):
- Whether `daily_composite_recompute` recomputes all five dimensions every run, or should reuse the stable weekly bases (financial health quarterly, macro and sector-beta weekly) and only refresh the fast ones (news, volatility). The spec implies the slow dimensions should be cached and reused.
- Whether the 429 era left a heuristic-fallback path that writes plausible-but-fake dimension values when upstream fails, and whether that path is still active for some tickers.
- Whether hysteresis is applied at write time (compare to the prior snapshot) and, if so, why it is not catching these crossings.

### 3.2 Two score columns disagree, plus duplicate rows (red)

`ticker_risk_snapshots` carries both `safety_score` and `composite_score`, and they diverge:
- AMD 06-11: `safety_score` 83.5, `composite_score` 48.0, grade B (grade follows composite).
- AMD 06-09: `safety_score` 84.2, `composite_score` 42.2, grade B.
- AAPL 06-11: `safety_score` 80.0, `composite_score` 67.0.

A 35-point gap on the same row is incoherent. If any surface (API field, iOS model, a chart) reads `safety_score` while the grade is derived from `composite_score`, the user sees an 83 next to a "B." Pick one canonical column, make every reader use it, and either drop or recompute the other.

Also: AMD has **two different snapshots for the same date** (06-12: one BB at 50.8 and one A at 73.8). That means there is no unique constraint on `(ticker, snapshot_date)`, or two writers are racing. Duplicate rows break `DISTINCT ON` assumptions and are the most likely cause of the intermittent `daily_portfolio_rollup_per_user` failure for the user holding AMD.

There are also dead duplicate columns: `news_sentiment` and `macro_exposure` (non-`_dim`) are NULL on every row while the real values live in `news_sentiment_dim` and `macro_exposure_dim`. This is a trap. Confirm the API and the iOS decoder read the `_dim` columns, then drop the dead ones.

### 3.3 ETF coverage is nearly absent (red for ICP)

Of ten common ETFs checked, only SPY and VOO have any snapshot and both are stale (latest 06-01). QQQ, XLK, XLE, VTI, SCHD, AGG, BND, IWM have none. The spec promises the top 50 ETFs by AUM. The live universe is effectively S&P 500 stocks only. See report 1 for the ICP impact. Backfilling the top ETFs (with the ETF-specific financial-health handling the spec describes, weighted from top holdings) is the fix.

### 3.4 AMD limited-data and rollup failure (orange, carried over)

AMD's 06-14 snapshot flags four of five dimensions as limited (`news_sentiment`, `macro_exposure`, `sector_exposure`, `volatility`) with news sentiment null, so it is effectively scored on financial health alone. This is the "empty radar" issue from prior audits, still present, and it ties to the duplicate-row and rollup-failure problems above. Backfilling AMD's dimensions clears the empty radar and likely the per-user rollup failure.

---

## 4. Observability gaps in the data pipeline

- `job_runs.error_json` is still NULL on failed runs, so failures are counted but not captured. The 06-12 commit labeled "recompute hardening" did not add error capture. Add it, and add a failed-ticker resume so a partial run can retry only what failed instead of re-walking from the top.
- The `writer_source` and `generated_at` columns on `ticker_risk_snapshots` are NULL on the recent rows, so you cannot tell which job wrote a snapshot. Populating these would make incidents like the duplicate AMD rows diagnosable.
- There is no alert when a scheduled job fails. The recompute failed daily for at least five days (06-08 through 06-12) and nothing surfaced it. See report 3 for the recommended job-failure alert.
- Legacy `data_generation_runs` still holds orphaned `status = running` rows from 05-16. Cosmetic, but clean them so the table is not misleading.

---

## 5. Security: clean

Supabase advisors show no error or critical lints. One low warning: the `citext` extension is installed in the `public` schema (move it to a dedicated schema when convenient). The standing manual task to toggle leaked-password protection in Supabase Auth is still open.

---

## 6. Backend punch list (ordered)

1. Confirm the next weekday `daily_composite_recompute_universe` run completes green now that the throttle is deployed.
2. Fix grade and dimension stability: reuse stable weekly and quarterly bases, enforce hysteresis at write time, and remove any fake-value fallback path (3.1).
3. Unify on one score column, add a unique constraint on `(ticker, snapshot_date)`, dedupe existing rows, drop the dead columns (3.2).
4. Backfill the top ETFs into the universe (3.3).
5. Backfill AMD's dimensions; confirm the per-user rollup stops failing (3.4).
6. Capture `error_json`, populate `writer_source` and `generated_at`, add failed-ticker resume (4).
7. Security housekeeping: move `citext`, toggle leaked-password protection (5).
