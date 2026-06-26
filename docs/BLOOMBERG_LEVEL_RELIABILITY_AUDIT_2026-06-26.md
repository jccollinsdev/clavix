# Clavix Bloomberg-Level Reliability Audit (2026-06-26)

Skeptical, evidence-first review of the data/reliability upgrade. Prior session claims were
**not** trusted; every conclusion below is backed by a live query, log line, or code read taken
on 2026-06-26 between ~14:50 and ~15:15 UTC. Production database is Supabase project
`uwvwulhkxtzabykelvam` (clavis). Backend runs on the VPS `sansar@134.122.114.241` in the
`clavis-backend-1` Docker container.

---

## 1. Executive summary

The upgrade is **real and largely deployed**, but it is **not yet Bloomberg-level reliable**.
The strongest pillars are genuine: macro factors are real FRED data, fundamentals are 98% on
primary-source SEC EDGAR XBRL, the composite recompute is deterministic with full 546/546
coverage, news ingestion for the universe runs through Tickertick (commercially licensed), Sentry
is live, and deploy/rollback safety is solid. The verified deployed code is byte-identical to local
`HEAD` (`b119de92c`).

The gaps that block a "Bloomberg-level" claim are concentrated in **news enrichment depth and
compliance**:

- Only **53%** of tickers (291/546) have 10+ fully-enriched ("complete") articles; the target was
  all 546.
- New-article enrichment is **50-59% complete**, far below the 85% target (MiniMax LLM rate-limiting
  is the bottleneck, not ingestion).
- The legacy **Google News RSS + Finnhub** path is still wired into the live on-demand
  digest/position-analysis flow, so "free/unlicensed feeds fully decommissioned" is **false**.
- **22 news jobs are stuck in `running`** in `job_runs` (orphaned by the 13:48 deploy restart, never
  reaped), polluting monitoring and occasionally causing `skipped_lock`.
- 8-K coverage is real but **thin** (149 events, 1 per ticker, 149/546 tickers).

**Go/no-go: NO-GO on "truly Bloomberg-level reliable yet."** Foundation is strong; enrichment
coverage, compliance cleanup, and job hygiene must close first.

---

## 2. What changed (deployed and confirmed)

Confirmed deployed via `RELEASE_SHA = b119de92c..., deployed 2026-06-26T13:49:12Z`, md5 manifest of
`/opt/clavis/backend/app` identical to local (`56cbd929...`, 125 files), and file mtimes all 13:48
UTC today.

- **Tickertick news pipeline** (`app/pipeline/tickertick_ingest.py`, `app/services/tickertick.py`):
  the universe news dispatcher `ingest_and_enrich_ticker_news` routes only through Tickertick when
  `USE_TICKERTICK` is true (the VPS default, env var unset).
- **IV / Polygon options removal** (commit `1645e82c6`): `fetch_near_term_implied_vol_30d` now has
  **zero callers**; volatility scoring uses metadata proxies (`_vol_rationale`).
- **SEC EDGAR XBRL fundamentals** (`edgar_fundamentals_sweep`) and **8-K events**
  (`edgar_events_sweep`) jobs added; `revenue_growth_trend` migrated to numeric + `fundamentals_source`
  column added.
- **Real FRED macro** (`macro_snapshot`, `macro_regression`): `data_status = real_factors`.
- **Alerting** (`app/services/alerting.py`): Sentry init + healthchecks.io dead-man heartbeat +
  provider-degradation monitor (`ops_monitor`).
- **Deploy safety** (`.github/workflows/deploy-prod.yml`): rsync `--delete` to `/opt/clavis`,
  pre-deploy tarball to `/opt/clavis_backups`, health-gated, auto-rollback from `last_stable.tar.gz`.
- **iOS onboarding "Aha" redesign** (commit `69fb863e5`) on `main`.

---

## 3. What is actually verified (with evidence)

| Claim | Verified? | Evidence |
|---|---|---|
| Deployed code == repo HEAD | YES | `RELEASE_SHA=b119de92c`; md5 manifest match (`56cbd929...`); 125/125 files; mtimes 13:48Z |
| Sentry active | YES | container log `{"event":"sentry_initialized","environment":"production"}` at 13:49 |
| Macro is real FRED | YES | latest `macro_regime_snapshots.data_status='real_factors'`, SPY 7357.49, VIX 18.63, UST10Y 4.41, credit_spread 2.76 |
| EDGAR fundamentals primary-source | YES | `fundamentals_source`: edgar=502, finnhub=47 → 502/511 non-ETF = **98.2%**; 505 fresh <30d |
| Recompute coverage 546/546 | YES | latest snapshot per ticker: 546 dated today, 0 stale >7d, all `methodology_version=v2`, all `updated_at` 13:58-14:50Z today |
| Recompute deterministic / no flicker | YES | live NVDA rebuild: grade BBB and composite 62.2 identical before/after, 6.6s, source_count=10 |
| IV options dead code | YES | `fetch_near_term_implied_vol_30d` zero callers; no options 403 in 2h post-deploy logs incl. a full recompute |
| Tickertick is the universe news provider | YES | `USE_TICKERTICK` default true (unset on VPS); dispatcher routes Tickertick-only; live `active_ticker_news_refresh` + `tickertick_news_sweep` jobs |
| 8-K events reach the news pipeline | YES (thin) | 149 `source='sec.gov'` events across 149 tickers; `edgar_events_sweep` completed today (459 processed, 1223s) |
| API is up | YES | `GET 127.0.0.1:8000/health` → `200 {"status":"ok"}` |
| `revenue_growth_trend` decodes in Swift | YES | served value is JSON string ("declining","positive_3q") for 505/546; Swift model is `String?` |

---

## 4. What is NOT verified / still weak

- **Per-ticker enrichment depth**: only **291/546 (53%)** tickers have 10+ `analysis_status='complete'`
  articles. 461 have 10+ *total* events but enrichment has not caught up.
- **New-article enrichment rate**: last 2d **1991/3960 = 50.3%**, last 7d **6032/10147 = 59.4%**
  complete. Target 85% not met. MiniMax `/chat/completions` is actively retrying (rate-limited) in
  logs, so this is throughput-bound.
- **Compliance**: the on-demand `execute_analysis_run` path (digests + position analyses) still calls
  `fetch_google_company_rss` and Finnhub `fetch_market_news` when no Tickertick payload is prebuilt
  (the live digest route passes none). Finnhub also powers `earnings_calendar` and 47 tickers'
  fundamentals.
- **healthchecks.io "green"**: heartbeat is wired (`CLAVIX_HEARTBEAT_URL` set, `ping_heartbeat`
  called by `ops_monitor`) but pinged only **once/day**; the external dashboard state could not be
  observed directly from here.
- **iOS exhaustive decode**: only the highest-risk recently-changed field was verified. Every
  endpoint was not decoded against the Swift models.
- **Self-sustaining daily recompute**: the scheduled 10:00 cron run today **failed** (processed 31,
  skipped 510, 5 Polygon "Connection reset"); full 546/546 freshness was produced by a **manual
  post-deploy force recompute** (13:55-14:50), not the cron.

---

## 5. Status against every target criterion

| # | Target criterion | Verdict | Detail |
|---|---|---|---|
| 1 | VPS alerting: Sentry + healthchecks green | PARTIAL | Sentry MET; heartbeat wired but daily-only and dashboard not directly observed |
| 2 | iOS onboarding on main, CI green | MET (caveat) | `69fb863e5` on main; Backend CI green; **no iOS build/test in CI** |
| 3 | IV dead code removed, zero options 403 in recompute | MET | zero callers; no options 403 post-deploy; 10:00 403 was the pre-deploy container |
| 4 | Recompute races fixed: no stuck jobs / no dict-size errors | PARTIAL | no dict-size errors; **22 jobs stuck in `running`**, 4 `skipped_lock` |
| 5 | Tickertick: all 546 with 10+ LLM-enriched articles | NOT MET | 291/546 (53%) have 10+ complete; ops_monitor: 278 below 10 usable fresh |
| 6 | Finnhub/RSS decommissioned: zero in production | NOT MET | Google RSS + Finnhub live in on-demand analysis/digest path; Finnhub earnings + 47 fundamentals |
| 7 | News analysis_status complete >=85% of new | NOT MET | 50% (2d), 59% (7d) |
| 8 | Bloomberg news grade C -> B+ | ~B- | full coverage + rich bodies, but enrichment incomplete |
| 9 | EDGAR fundamentals >=95% non-ETF XBRL | MET | 98.2% (502/511) |
| 10 | Bloomberg financial health grade B- -> B+ | ~B | EDGAR primary-source + fresh, but dimension `data_source` mislabeled "finnhub" |
| 11 | EDGAR 8-K events in pipeline | MET (thin) | 149 events, 1/ticker, 149/546 tickers |
| 12 | Full recompute healthy: 546/546, stable grades | MET (fragile) | 546/546 fresh today, non-degenerate dist; daily cron fragile, manual force needed |
| 13 | iOS compatible: all responses decode | LARGELY | API healthy; high-risk field safe; not exhaustively decoded |
| 14 | Compliance clean: no unlicensed/free feeds in production | NOT MET | see #6 |

Scorecard: **6 MET, 5 PARTIAL/qualified, 3 NOT MET (#5, #7, #14).**

---

## 6. SQL / API / log checks used as evidence

```sql
-- News coverage + freshness
SELECT count(*) total, count(*) FILTER (WHERE created_at>now()-interval '7 days') c7d,
       count(DISTINCT ticker) tk, max(created_at) latest FROM shared_ticker_events;
-- => total 11326, c7d 10135, tk 546, latest 2026-06-26 15:01 (live ingestion)

-- analysis_status distribution
SELECT analysis_status, count(*) FROM shared_ticker_events GROUP BY 1;
-- => complete 6638, headline_only 2597, partial 2029, incomplete 48, null 15

-- per-ticker enriched depth
WITH p AS (SELECT ticker, count(*) FILTER (WHERE analysis_status='complete') c
           FROM shared_ticker_events GROUP BY ticker)
SELECT count(*) FILTER (WHERE c>=10) FROM p;  -- => 291 of 546

-- new-article enrichment
SELECT count(*) FILTER (WHERE created_at>now()-interval '2 days') t2,
       count(*) FILTER (WHERE created_at>now()-interval '2 days' AND analysis_status='complete') c2
FROM shared_ticker_events;  -- => 3960 / 1991 = 50%

-- snapshot coverage/freshness/grades
WITH l AS (SELECT DISTINCT ON (ticker) ticker, snapshot_date, grade, updated_at
           FROM ticker_risk_snapshots ORDER BY ticker, snapshot_date DESC, updated_at DESC)
SELECT count(*), count(*) FILTER (WHERE snapshot_date>=current_date) FROM l;  -- => 546 / 546

-- fundamentals source
SELECT fundamentals_source, count(*) FROM ticker_metadata GROUP BY 1;  -- => edgar 502, finnhub 47

-- job status taxonomy
SELECT status, count(*) FROM job_runs GROUP BY 1;
-- => completed 217, failed 60, running 22, skipped_lock 4, skipped 1

-- stuck jobs
SELECT job_id, count(*) FROM job_runs WHERE status='running' GROUP BY 1;
-- => active_ticker_news_refresh 15, tickertick_news_sweep 6, daily_eod_price_capture 1

-- macro reality
SELECT data_status, regime_state FROM macro_regime_snapshots ORDER BY created_at DESC LIMIT 1;
-- => real_factors, neutral

-- iOS decode (served type of revenue_growth_trend)
SELECT jsonb_typeof(dimension_inputs->'financial_health'->'revenue_growth_trend')
FROM ticker_risk_snapshots WHERE snapshot_date=current_date;  -- => string 505, null 21, absent 20
```

Logs / API / shell:
- `docker logs` → `sentry_initialized`; `Retrying request to /chat/completions` (MiniMax throttle).
- `/var/log/clavix/cron.log` → `composite_recompute FINISHED with 5 failures` (Connection reset);
  `Polygon auth error 403 ... snapshot/options/BF.B` (10:00, pre-deploy); `[OPS_MONITOR] news: 278
  active tickers below 10 usable fresh articles (530 measured)`.
- `curl 127.0.0.1:8000/health` → `200 {"status":"ok"}`.
- Live NVDA `refresh_ticker_snapshot(job_type='manual_refresh')` → fresh snapshot in 6.6s, grade
  stable.

---

## 7. Data quality findings

1. **News coverage is universe-wide** (546/546 tickers have at least one event; 461 have 10+ total)
   and **bodies are substantive** (avg 2,620 chars, 7,330 articles with 1,000+ char bodies, 8,647
   with summaries, ~7,500 with `tldr`/`what_it_means`). This is a genuine improvement over the prior
   "alphabetical cliff."
2. **Enrichment is the weak link**: 53% of tickers reach 10+ enriched articles; 41% of all events are
   not `complete`. Cause is LLM throughput (MiniMax `MINIMAX_MIN_INTERVAL_SECONDS` throttle +
   retries), not ingestion.
3. **Fundamentals are primary-source and fresh** (98.2% EDGAR, 505 fresh <30d), but the snapshot
   dimension labels `data_source = "finnhub"` for 526 tickers (a hardcoded default in
   `methodology.py:293`). Values are EDGAR; the displayed provenance is stale/wrong.
4. **Macro is real and non-degenerate** (`real_factors`, live FRED levels). Minor: `growth_signal`,
   `inflation_signal`, `risk_on_off_signal` are NULL in the latest snapshot.
5. **8-K events are real but shallow**: 1 event per ticker, 149/546 tickers, mostly untyped
   (`event_type` NULL on 11,204 of 11,326 rows).
6. **Grade distribution is healthy** (BBB 284, A 216, BB 39, B 5, AA 1, CCC 1): not the prior
   degenerate ~99%-one-bucket shape, though compressed into BBB/A.

---

## 8. Reliability findings

1. **22 stuck `running` jobs** in `job_runs` (15 `active_ticker_news_refresh`, 6
   `tickertick_news_sweep`, 1 `daily_eod_price_capture`), 1.2-15.3h old. Most predate the 13:48
   deploy restart and were never reaped. There is an orphan-reaper for `analysis_runs`
   (`_fail_orphaned_runs`) but **not for `job_runs`**.
2. **Daily recompute cron is fragile**: today's 10:00 run failed (5 Polygon "Connection reset by
   peer", processed only 31, skipped 510). Full 546/546 freshness depended on a **manual** post-deploy
   force recompute. The system is not yet self-sustaining for full daily freshness.
3. **Vestigial failing systemd unit**: `clavix-universe-backfill.service` (ExecStart
   `/opt/clavis/scripts/nightly_refresh.sh`, a file that no longer exists) fails daily with
   `status=203/EXEC`. Harmless (real jobs run via `/etc/cron.d/clavix`) but it is noise and a latent
   trap.
4. **Heartbeat granularity is coarse**: only `ops_monitor` (daily 12:30) pings the dead-man switch, so
   a same-day outage after the ping would not page until the next day.
5. **Host is memory-constrained** (2 GB host, container capped 1.5 GB). A concurrent full recompute +
   news sweep + enrichment could OOM. This caps safe parallelism for any hard reload.
6. **Positive**: recompute is deterministic (NVDA proof), deploy has tarball rollback, Sentry is live,
   and there is a pre-recompute freshness guard preventing silent stale-input corruption.

---

## 9. Compliance findings

1. **Universe news ingestion is compliant**: Tickertick (commercially permissive) is the only feed
   for `active_ticker_news_refresh` and `tickertick_news_sweep`.
2. **On-demand path is NOT compliant**: `execute_analysis_run` (live for digests via
   `routes/digest.py` and position analyses) calls `fetch_google_company_rss`,
   `fetch_google_sector_rss`, `fetch_cnbc_*_rss`, and Finnhub `fetch_market_news` whenever it runs
   without a prebuilt Tickertick payload, then persists results via `_store_relevant_articles`. The
   live digest route creates runs with no payload, so this path fires. Evidence: 32
   `provenance='shared'` events in the last 2 days and 158 `event_analyses` (latest 11:08 today) with
   sources like Yahoo Finance, Seeking Alpha, Barron's that originate from this path.
3. **Finnhub remains in production** for: `earnings_calendar` (daily cron), 47 tickers' fundamentals,
   and the legacy market-news call above.
4. **Google decoder cache** `gnews_wrapper_resolution` holds 12,296 rows (historical). No recent
   `news.google.com` URLs were found in `shared_ticker_events` (last 7d = 0), because decoded URLs
   resolve to publisher domains, so source names alone do not prove decommissioning.

Net: the *bulk* pipeline is licensed, but free/unlicensed feeds still execute in the user-facing
analysis path. Criterion #14 is not met.

---

## 10. iOS compatibility findings

1. **API is healthy** and iOS hits the FastAPI backend (`clavis.andoverdigital.com`) for
   `/dashboard`, `/tickers/*`, `/digest`, etc., plus Supabase only for auth.
2. **No decode regression on the riskiest field**: commit `b119de92c` made
   `ticker_metadata.revenue_growth_trend` numeric, but the served field
   (`dimension_inputs.financial_health.revenue_growth_trend`) is still a **string** label for 505/546
   tickers, matching Swift `Methodology.revenueGrowthTrend: String?` and its
   `.humanizedTitleCasedDisplayText` usage. No crash.
3. **`is_product_visible = false` for all 546 snapshots is harmless**: grep shows **zero code reads**
   of the column anywhere in the backend; it is a vestigial field, not a visibility gate.
4. **Residual risk**: not every endpoint was decoded against the Swift models in this pass, and there
   is no iOS build/test stage in CI. The financial-health "source: Finnhub" label will display
   incorrectly (it is EDGAR data).

---

## 11. Bugs and suspicious inconsistencies

1. `job_runs` status taxonomy is `completed`/`failed`/`running`/`skipped_lock`/`skipped` (not
   `success`). Any monitoring that checks for `status='success'` would mis-report everything as failed.
   (This audit corrected for it mid-stream.)
2. `data_source` for the financial-health dimension is hardcoded to fall back to `"finnhub"` while the
   real source is EDGAR.
3. `clavix-universe-backfill.service` points at a deleted script and fails daily.
4. `job_runs` accumulates orphaned `running` rows on every container restart (no reaper).
5. `tickertick_news_sweep` docstring/`active_ticker_news_refresh` docstring still say "Google News
   RSS" though they now run Tickertick (stale comments, not a functional bug).
6. Daily composite recompute marks the whole run `failed` on a 14% per-batch failure even though 510
   were legitimately skipped as fresh, which exaggerates failure in alerting.

---

## 12. Severity-ranked issues

**P0 (blocks "Bloomberg-level" + compliance):**
- C1 Compliance: Google News RSS + Finnhub still execute in the live digest/position-analysis path
  (criteria #6, #14).

**P1 (data quality below target):**
- D1 Enrichment depth: only 53% of tickers have 10+ enriched; new-article complete rate 50-59% vs 85%
  target (criteria #5, #7).
- R1 Daily full-recompute not self-sustaining: cron path fails on Polygon resets; full freshness needs
  manual force runs (criterion #12 fragility).

**P2 (reliability/hygiene):**
- R2 22 orphaned `running` job rows; no `job_runs` reaper; causes `skipped_lock` and false monitoring.
- R3 Vestigial failing `clavix-universe-backfill.service`.
- Q1 Financial-health `data_source` mislabeled "finnhub" (should be EDGAR).
- R4 Heartbeat pinged once/day only.

**P3 (polish):**
- 8-K coverage thin (1/ticker, 149/546); event_type largely untyped.
- Stale docstrings; recompute failure-rate accounting; remove orphan `polygon_options.py`.
- No iOS build/test in CI.

---

## 13. Recommended next steps (priority-ranked)

1. **Close the compliance leak (P0).** Make `execute_analysis_run` read company/market news from the
   Tickertick-backed `shared_ticker_events` pool instead of `fetch_google_company_rss` /
   `fetch_market_news`. Gate the legacy fetchers behind `USE_TICKERTICK=false`. Move
   `earnings_calendar` off Finnhub if licensing requires, or confirm Finnhub's license covers it.
2. **Raise enrichment throughput (P1).** Increase MiniMax concurrency/quota or add a second enrichment
   worker; run a focused backfill on the 255 tickers under 10 complete articles; track
   `analysis_status='complete'` rate as an SLO.
3. **Make daily recompute self-healing (P1).** Add retry/backoff for Polygon "Connection reset";
   schedule a nightly `force_refresh=true` full pass; stop counting `skipped` fresh tickers as
   failures.
4. **Add a `job_runs` orphan reaper (P2)** on scheduler startup (mark `running` rows older than N
   hours as `failed`), mirroring `_fail_orphaned_runs`.
5. **Fix provenance label (P2):** set financial-health `data_source` from `fundamentals_source`
   (EDGAR) instead of the hardcoded "finnhub".
6. **Remove the dead systemd unit (P2)** or repoint it at a real script.
7. **Deepen 8-K ingestion (P3):** pull more than one filing per ticker; populate `event_type`.
8. **Add an iOS decode smoke test (P3)** and an Xcode build stage in CI.

---

## 14. Go / no-go judgment

**NO-GO on "Clavix is truly Bloomberg-level reliable yet."**

The infrastructure and structural data layers (macro, fundamentals, recompute, deploy safety,
alerting, Tickertick universe ingestion) are genuinely solid and verifiably deployed. But three of the
headline criteria fail on hard evidence: enrichment depth (53% vs 100%), new-article enrichment rate
(50-59% vs 85%), and compliance (free/unlicensed feeds still in the live analysis path). Reliability
hygiene (stuck jobs, fragile daily cron) is a notch below "production-grade autonomous."

Realistic grade today: **B- / B**. With the P0 compliance fix and the enrichment backfill caught up to
85%, it reaches a defensible **B+**. "Bloomberg-level" (A) additionally requires deeper 8-K/event
coverage and self-sustaining daily operation without manual force runs.
