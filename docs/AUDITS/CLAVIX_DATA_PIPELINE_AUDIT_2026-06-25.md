# Clavix Data Pipeline Audit: Freshness, Completeness, Accuracy

Date: 2026-06-25. Scope: the full 546-ticker universe, all five risk dimensions, the news
article corpus, every source-data table, and every scheduled job that feeds them. Database:
Supabase project `uwvwulhkxtzabykelvam` (clavis, prod). Code baseline: repo HEAD `4d7c3cb43`.

Method: 12 parallel investigators (6 querying the live DB read-only, 6 tracing pipeline
code), then an adversarial verification pass that independently re-ran 26 of the load-bearing
claims (22 confirmed, 4 partial: minor arithmetic or denominator corrections only). On top of
that, every headline number in this document was re-queried by hand against the live DB. Where
a number is marked "verified" it was reproduced at least twice from independent SQL.

> Read the Executive Summary and the Critical Operational Landmine first. Everything after is
> the evidence and the fix plan.

---

## 1. Executive summary

The earlier audits (the 2026-06-22 "alphabetical cliff" note in particular) are out of date.
Raw coverage and daily recompute are now genuinely healthy: all 546 tickers get a fresh
snapshot every day, news flows in every few hours, and the alphabetical cliff is gone. The
problem has moved. It is no longer "we have no data." It is "the data we have is thin, partly
heuristic, and the depth (enrichment + real per-ticker signal) falls far short of the goal of
every ticker carrying 10 fully filled-out articles and five real dimensions."

The honest one-line verdict: **of 546 tickers, exactly 0 meet the full bar you described** (all
five dimensions real plus 10 fully-enriched articles), because two of the five dimensions are
not real for anyone (macro is a near-constant from a regression with R-squared near 0.02, and
volatility implied-vol is `estimated` for 100% of tickers), and only 105 tickers (19.2%) have
10 fully-enriched articles.

What is healthy:

- 546/546 tickers have a snapshot dated today. The daily universe recompute completed
  546/546 with 0 failures on both 06-24 and 06-25.
- News is arriving continuously: 9,007 articles, 540/546 tickers have at least one, the corpus
  is uniformly fresh (9,005 of 9,007 are under 30 days old, newest about 2 hours before query).
- The alphabetical cliff is refuted. Every letter A through Z has articles (per-ticker average
  6.7 to 40.4).
- Four of the five dimensions are non-null for nearly the whole universe (macro 546, volatility
  546, financial_health 525, sector 524).
- The serving layer is honest: when a dimension is thin it is hard-nulled and shown as a
  "Limited Data" badge rather than faked.

What is broken or short of perfect (the rest of this document details each with numbers):

1. **Deployment hygiene (corrected, not a landmine).** Direct VPS inspection shows the running
   backend is byte-for-byte identical to this repo, so pushing is safe. But a richer news
   pipeline (batched rotation + coverage repair) lived only on the VPS, was never committed, and
   a routine 06-24 deploy erased it. It must be rebuilt and tracked. See section 2.
2. **News dimension is null for 223/546 (40.8%)**, and only 6 of those genuinely lack articles.
   144 of them have 5 or more enriched articles; the dimension simply is not being computed from
   data that exists.
3. **Enrichment depth is the real shortfall.** Only 105/546 tickers (19.2%) have 10
   fully-enriched articles. 3,614 articles have no TLDR, 3,925 have no key implications, and the
   deep-analysis tier wrote only 69 of 9,007 rows.
4. **Macro dimension is statistically meaningless** (regression R-squared averages 0.019, below
   0.10 for all 546) yet drives a near-constant score around 90 that inflates grades (76.7% of
   the universe is now graded A).
5. **Volatility implied-vol is `estimated` for 100% of tickers** (real options IV never used).
6. **Financial inputs are partly dead:** `fcf_margin` and `interest_coverage` are NULL for
   100% of the universe, so financial_health runs on 3 of its 5 intended inputs, plus a unit bug
   makes a 4th non-discriminating.
7. **Source tables are stale or empty:** `prices` has no bar in 30 days for 92.7% of the
   universe, `asset_safety_profiles` froze on 2026-05-08, `sector_regime_snapshots.sector_score`
   and `sector_beta` have never been populated, macro regime is stuck in `price_only` mode.
8. **Several jobs are silently dead:** `weekly_fundamentals_sweep` has never run,
   `daily_eod_price_capture` and `daily_alert_evaluation` stopped after 06-23, and the news job
   run-logging is stuck (a monitoring blind spot, though news itself keeps flowing).
9. **Dead/duplicate columns:** `is_product_visible` / `verification_status` / `writer_source`
   stopped being written 40 days ago and have no readers; `composite_score` equals
   `safety_score` byte-for-byte for every ticker.
10. **The product target is mis-specified in code.** The documented SLA is "3 articles in 7
    days," not 10. The pipeline deliberately stops topping up at 3.

---

## 2. Deployment topology (CORRECTED after direct VPS inspection): no drift, repo == prod

An earlier draft of this audit called this section a "critical landmine: unversioned production
code." Direct inspection of the VPS (DigitalOcean 134.122.114.241, container `clavis-backend-1`)
on 2026-06-25 disproves that. The corrected picture:

- **The running backend is byte-for-byte identical to this repo's `backend/app`** (diff: 0
  files, 0 lines, including `scheduler.py`, `ticker_cache_service.py`, `risk_scorer.py`,
  `run.py`, `composite_recompute.py`). The committed code IS what runs.
- **Deploy works as designed and pushing is SAFE.** Push to `clavix` `main` triggers the Action
  that `rsync -az --delete`-es the repo to `/opt/clavis` and restarts the container. A push
  deploys the code that already runs; it does not wipe anything that exists today.
- The confusion came from `/opt/clavis/.git`, a stale unused checkout of a DIFFERENT GitHub repo
  (`jccollinsdev/clavis`, trailing "s") than the deployment source (`jccollinsdev/clavix`). Its
  "59 uncommitted changes" are just the clavix files sitting on top of that old checkout, so
  `git status` there is meaningless. Recommend deleting that stray `.git` / checkout. Nothing
  runs from it.
- The phantom jobs that triggered the original alarm (`universe_news_refresh` batched rotation,
  `daily_snapshot_coverage_repair`, `daily_tldr_backfill`, the job_runs-logged news refresh)
  were a richer, EPHEMERAL news pipeline that ran before 2026-06-24. It was never committed to
  either repo (`git log --all -S` empty in both), and the 06-24 deploy of an unrelated iOS
  commit `rsync --delete`-ed it away and restarted the container (uptime 27h, `/etc/cron.d/clavix`
  rewritten 16:39 on 06-24). It is not recoverable from git and must be rebuilt, not restored.
  The stuck `universe_news_refresh` "running" row in `job_runs` is its orphan; safe to mark
  failed or delete.

Net: there is no untracked running code and no deploy landmine. The real issue is operational
hygiene (two near-identically-named repos `clavix` vs `clavis`, a stale extra checkout on the
box, and a useful news pipeline that lived only on the VPS until a routine deploy erased it).
Because repo == prod, every code root-cause in this document was read from the exact running
code, so the file:line references are accurate (no "may differ from prod" caveat applies). The
current news pipeline is the simpler in-process one in this repo (`SCHEDULER_TIER=intraday`,
4-hour `_run_active_ticker_news_refresh` over the full universe, no job_runs logging), which is
why news still flows but the richer rotation and coverage-repair jobs are gone.

---

## 3. Scorecard

| Domain | Status | Headline metric (verified) |
|---|---|---|
| Snapshot coverage | Healthy | 546/546 have a snapshot dated today, 0 missing |
| Daily recompute | Healthy | 546/546 processed, 0 failed (06-24, 06-25) |
| News article supply | Mixed | 540/546 have >=1 article; 369 (67.6%) have >=10 raw |
| News enrichment depth | Poor | 105/546 (19.2%) have >=10 fully-enriched; 37% of articles fully enriched |
| News Sentiment dimension | Poor | NULL for 223/546 (40.8%); 217 of those have articles |
| Financial Health dimension | Mixed | Real but runs on 3 of 5 inputs; FCF + interest-coverage 100% NULL |
| Macro dimension | Broken (degenerate) | R-squared avg 0.019; near-constant ~90; not discriminating |
| Sector dimension | Mixed | 524/546 real per-ticker; source aggregate table never populated |
| Volatility (Stability) dimension | Mixed | Realized-vol real; implied-vol `estimated` for 100% |
| Source: prices | Stale | 92.7% of universe has no bar in 30 days |
| Source: asset_safety_profiles | Dead | Frozen at 2026-05-08 (48 days) |
| Source: macro_regime | Degraded | Daily but `price_only`, no credit spread, proxy-coded levels |
| Source: sector_regime | Degraded | sector_score / sector_beta never populated (0/265) |
| Source: fundamentals | False-fresh | Timestamp today, but 2 of 5 fields 100% NULL |
| Jobs | Mixed | Core daily jobs run; fundamentals_sweep never ran; 2 dailies stopped 06-23 |
| Serving / honesty | Healthy logic, wrong target | Honest "Limited Data" badge; SLA is 3 articles, not 10 |
| Product-visibility gate | Dead | is_product_visible NULL for all 546, no readers |
| Code in version control | Healthy (corrected) | Running backend == repo (0 diff); deploy is clean; stale extra `.git` checkout to remove |

---

## 4. Universe and snapshot coverage

Verified facts:

- `ticker_universe` = 546 rows, all `is_active = true`. 17 distinct sectors. Membership: SP500
  503, ETF 28, CORE_ETF 13, USER_SHARED 2.
- `ticker_metadata` = 549 rows (3 more than the universe: orphan rows to reconcile).
- All 546 tickers have at least one snapshot; anti-join for "no snapshot" = 0.
- Latest snapshot for every one of the 546 is dated 2026-06-25, written 10:00 to 11:49 UTC
  today. Freshness buckets: today 546, everything else 0.

Short of perfect:

- **`data_status = 'partial'` for 223/546 (40.8%)**, only 323 (59.2%) are `complete`. ETFs are
  the worst: 27/28 ETF and 10/13 CORE_ETF are partial. "Partial" tracks exactly with the
  news-dimension NULL set (same 223).
- **Recompute has had gaps:** 2026-06-21 has no snapshots at all, and several recent days landed
  partial counts (06-19 = 335, 06-15 = 269, 06-14 = 5, 06-11 = 100). There is no alert when a
  recompute lands fewer than 546 rows.
- **11 universe tickers have NULL or empty `sector`** (drives the 22 NULL sector dimensions).
- **3 orphan `ticker_metadata` rows** that are not in the universe.

---

## 5. The five dimensions

Latest snapshot per ticker (`distinct on (ticker) ... order by snapshot_date desc, created_at
desc`). NULL counts and distributions (verified):

| Dimension | Column | NULL count | Avg | Stddev | Verdict |
|---|---|---|---|---|---|
| Financial Health | `financial_health` | 21 (3.8%) | 62.2 | 9.1 | Real but thin (3 of 5 inputs) |
| News Sentiment | `news_sentiment_dim` | 223 (40.8%) | 58.3 | 9.3 | Broken coverage |
| Macro Resilience | `macro_exposure_dim` | 0 | 89.6 | 5.4 | Degenerate (not real signal) |
| Sector Resilience | `sector_exposure` | 22 (4.0%) | 75.0 | 6.5 | Mostly real per-ticker |
| Price Stability | `volatility` | 0 | 76.4 | 9.9 | Real realized-vol, estimated IV |

`composite_score` and `safety_score` are byte-for-byte identical for all 546 rows (one is a
redundant duplicate). Grade distribution: A 419 (76.7%), BBB 93 (17.0%), AA 26 (4.8%), BB 8
(1.5%); no AAA and nothing below BB. An 81.5% A/AA pile-up is as degenerate as the old 98.8%
BBB/BB cluster, and it is caused by the inflated, near-constant macro (avg 89.6) and volatility
(avg 76.4) dimensions pulling composites up.

### 5.1 News Sentiment (the worst dimension)

- NULL for 223/546 (40.8%). Of those 223: only **6 genuinely have zero articles**; **85 have
  10 or more articles**; **144 have 5 or more sentiment-enriched articles**; **111 have 3 or
  more events in the last 7 days** and still score NULL.
- So roughly 96% of the news-dimension gap is a computation/wiring problem, not a data-supply
  problem. The articles exist; the dimension is not derived from them.

Root cause (repo logic, consistent with the data):

- `refresh_ticker_snapshot` (the daily recompute) is a scoring pass that only **reads**
  `shared_ticker_events`. It never ingests news. So a ticker the news job has not reached gets
  reprocessed every day forever and re-derives the same NULL. The daily recompute can never
  raise news coverage.
- The scorer requires 3 or more **relevant** articles inside a strict 7-day window
  (`_build_news_sentiment_inputs`, floor of 3). Two filters destroy usable signal before that
  check: `_filter_news_rows_by_relevance` (drops any article whose title does not contain the
  ticker symbol or company first word) and a `[:10]` truncation applied before scoring. Together
  these push the 111 "have-articles-but-NULL" tickers below the floor.
- When the result is NULL, `dimension_last_refreshed['news_sentiment']` is **stamped fresh
  anyway** (the timestamp is written for all five keys unconditionally). This is a "freshness
  lie": the snapshot looks scored and fresh while the value is missing, and it can suppress a
  same-day retry.

### 5.2 Financial Health

- Real, not a constant, but runs on 3 of its 5 intended inputs. Across all 546:
  `fcf_margin` NULL 546/546 (100%), `interest_coverage` NULL 546/546 (100%) (even for
  AAPL/MSFT/TSLA), `debt_to_equity` NULL 42, `current_ratio` NULL 62, `pe_ratio` NULL 65,
  `market_cap` NULL 42, `revenue_growth_trend` NULL 41. `beta` is fully populated.
- **Unit bug:** `revenue_growth_trend` is stored as a percentage (avg 15.55, max 260) but the
  scorer compares it as a fraction (>= 0.30). Roughly 89% of tickers trip the max bonus, so this
  input no longer discriminates.
- `fundamentals_updated_at` is today for all 546 (false freshness: the row is stamped without
  the missing fields being filled). Fundamentals stay fresh only as an accidental side effect of
  the daily recompute re-fetching the Finnhub profile; the dedicated `weekly_fundamentals_sweep`
  has never run.

### 5.3 Macro Resilience (degenerate)

- `macro_exposure_dim` is non-null for all 546 but the per-ticker macro regression has
  **R-squared averaging 0.0188 (max 0.0744), below 0.10 for every single ticker.** That is no
  explanatory power. The output collapses to a near-constant around 89.6 (stddev 5.4) applied to
  the whole universe. It is computed from real inputs but is not a real signal, and it inflates
  composites.
- The macro source (`macro_regime_snapshots`) is fresh-dated (06-24) but stuck in
  `data_status = 'price_only'`: `credit_spread_level` is NULL on every recent row, and
  `ust10y_level` (87.38) and `dxy_level` (28.53) are ETF proxy prices, not the real 10Y yield
  (about 4%) or DXY (about 98). `macro_sensitivity_score` in `asset_safety_profiles` is 100%
  NULL.

### 5.4 Sector Resilience

- `sector_exposure` is real per-ticker for 524/546 (computed from the ticker against its sector
  ETF). The 22 NULLs are tickers whose sector is missing from the sector-ETF map (the 21 ETFs
  with NULL sector plus 1 other).
- The source aggregate `sector_regime_snapshots` is degraded: `sector_score` and `sector_beta`
  have **never been populated (0 of all 265 rows ever)**, momentum and breadth are NULL on the
  latest, and it covers only 12 ETF-based sectors versus the 41-sector taxonomy used by
  `ticker_metadata` and `sector_medians`.

### 5.5 Price Stability (volatility)

- Realized-volatility component is real for 546/546. But the **implied-vol component is
  `iv_source = 'estimated'` for 100% of tickers** (real options IV via Polygon never lands), and
  it is not flagged as limited. So "stability" is part real, part heuristic, for everyone.
- The dedicated `prices` table is stale (section 7), which does not appear to break the
  volatility dimension (realized vol is computed from bars fetched live during recompute) but
  does affect reference prices, charts, and the 14-day backfill.

---

## 6. News article corpus and enrichment depth

Corpus (verified): 9,007 articles, 540/546 tickers with at least one (6 with zero, 36 with zero
in the last 7 days). Freshness is excellent: 9,005 of 9,007 under 30 days, none over 90 days,
newest published about 2 hours before query.

The ">=10 articles" target, every way of counting it (single authoritative query):

| Definition | Tickers meeting it | % of 546 |
|---|---|---|
| >=10 raw articles (any age) | 369 | 67.6% |
| >=10 raw in last 7 days | 207 | 37.9% |
| >=10 with `what_it_means` analysis | 200 | 36.6% |
| >=10 fully enriched (TLDR + sentiment + risk_direction + key_implications) | **105** | **19.2%** |

Average articles per ticker: 16.5 raw, 9.7 enriched. So the direct answer to "every stock with
10 fully filled-out articles" is **105/546 (19.2%) today.**

Per-article enrichment fill rates (verified, of 9,007):

- `tldr`: 5,393 filled (59.9%), **3,614 missing**.
- `what_it_means`: about 58.8% filled, **3,709 missing**.
- `key_implications` (array length >= 1): about 56.4% filled, **3,925 empty**.
- `sentiment_score`: 8,912 filled (98.9%), only 95 missing. The 2-hour sentiment job keeps up.
- `risk_direction`: filled on 65.1%, of which about 2,612 are the `neutral` default. Only about
  36% carry a real directional signal.
- Deep-analysis tier (`what_happened`, `long_analysis`, `scenario_summary`, `confidence`,
  `follow_up_notes`): populated on **69 of 9,007 rows (0.77%)**, all from `analysis_source =
  'minimax'`. That tier is essentially not running.
- Fully enriched (TLDR + sentiment + risk_direction + key_implications all present): 3,335 of
  9,007 (37%).

Why depth is missing (extraction funnel, verified):

| `extraction_status` | Count | Has body text | Has TLDR |
|---|---|---|---|
| success | 6,495 (72.1%) | 6,495 | 5,321 |
| failed | 1,965 (21.8%) | 1,965 | 0 |
| navigation_only | 477 (5.3%) | 477 | 3 |
| (null) | 69 | 0 | 69 |
| paywalled | 1 | 1 | 0 |

So about 2,442 articles (27.1%) never reach clean extraction, and those rows essentially never
get a TLDR or analysis. The TLDR ceiling is therefore bounded by extraction quality, not by the
backfill job (which runs daily and processed about 1,029 candidates on 06-24).

Observability gaps in the corpus: `analysis_status` and `data_status` are **100% NULL on all
9,007 article rows**, so the pipeline has no row-level completeness flag to resume partial
enrichment or to filter to "fully enriched." Eleven documented columns are 100% empty
(`body_markdown`, `body_length`, `headline_only`, `missing_fields`, `limited_reason`,
`url_resolution_status`, `extraction_error_code`, `rejection_reason`, `resolved_url`,
`original_url`, `generated_at`).

News cadence and the observability bug:

- News is ingested on a roughly 4-hour cadence via a 28-batch cursor rotation (20 tickers per
  run). A full universe cycle takes about 28 x 4h = 4.7 days. That is why ">=10 in 7 days"
  (207) lags ">=10 ever" (369): the long tail is only revisited about twice a week.
- News is flowing right now (article-creation histogram shows about 100 new rows at 06-25 16:00
  UTC, with spikes every 4 hours through today).
- But the **job-run logging is stuck**: `universe_news_refresh` has shown `running` for about 26
  hours (since 06-24 16:35, items_processed 0), and no news job has logged a completed run since
  then, even though articles keep arriving. This is a monitoring blind spot, not a news outage,
  but it means a real news outage would be invisible.

The legacy `event_analyses` table is still being written (newest 2026-06-25) for only about 7
positions and links to 0 shared events: a second, divergent enrichment path that should be wired
in or retired.

---

## 7. Source-data tables

| Table | Latest | Freshness verdict | Key gap |
|---|---|---|---|
| `prices` | 2026-06-25 (a few) | Stale | 506/546 (92.7%) have no bar in 30 days; only 11 in 3 days; 26 tickers have no price at all |
| `asset_safety_profiles` | 2026-05-08 | Dead (48 days) | `macro_sensitivity_score` 100% NULL on latest; 0 rows since June |
| `macro_regime_snapshots` | 2026-06-24 | Fresh but degraded | `price_only`; `credit_spread_level` NULL; proxy-coded yield/DXY |
| `sector_regime_snapshots` | 2026-06-24 | Fresh but degraded | `sector_score` / `sector_beta` never populated (0/265); 12 sectors only |
| `ticker_metadata` fundamentals | 2026-06-25 | False-fresh | `fcf_margin` + `interest_coverage` 100% NULL |
| `sector_medians` | 2026-06-20 | Healthy | weekly, on cadence |
| `peer_groups` | 2026-06-20 | Healthy | weekly, on cadence |
| `earnings_calendar` | 2026-06-25 | Fresh but narrow | 45 rows, about 7.9% of universe |
| `etf_holdings` | 2026-06-22 | Fresh but narrow | about 22% of universe as constituents |

The recurring theme: the snapshot table shows non-null, fresh-looking dimensions while the
source tables behind them are empty or weeks stale. `macro_exposure_dim` and `volatility` are
non-null for 546/546 today while their underlying sources are degraded or stale. There is no
source-vs-snapshot consistency check, so heuristic fallbacks present as real data.

---

## 8. Job execution and scheduling

Healthy: the core daily jobs all ran today within about 11 hours
(`daily_macro_snapshot`, `daily_sector_snapshot`, `daily_composite_recompute_universe`,
`daily_portfolio_rollup_per_user`, `daily_earnings_calendar_refresh`, `event_fundamentals_pull`).
The universe recompute completed 546/546 with 0 failures on 06-24 and 06-25 (about 110 to 140
minutes per run).

Dead or degraded (verified from `job_runs`):

- **`weekly_fundamentals_sweep`: never run** (absent from `job_runs` entirely). It is in the
  repo registry but is on neither the crontab nor the in-process scheduler.
- **`daily_eod_price_capture` and `daily_alert_evaluation`: stopped after 2026-06-23** (only 3
  lifetime runs each, last about 46 hours before query). Alerts are not being evaluated, which
  means users get no alert notifications, and EOD price capture stopping explains the stale
  `prices` table.
- **All weekly recompute jobs last ran 06-20/06-21** (over 5 days): `weekly_peer_groups_recompute`,
  `weekly_sector_medians_recompute`, `weekly_volatility_recompute`, `weekly_universe_audit`.
- **Composite recompute history is fragile:** 16 completed vs 21 failed lifetime. A
  `score_to_grade is not defined` bug zeroed roughly 400 of about 500 tickers per day from
  2026-06-03 through 06-12, and deploy restarts interrupted runs on 06-15/19/23.
- **`ticker_refresh_jobs`: 21.8% lifetime failure** (9,867 of 45,363), though 0 failures in the
  last 48 hours.
- `data_generation_runs` / `data_generation_run_items` pipeline is dormant (last activity
  2026-05-17, about 39 days ago).
- One orphaned `scheduler_jobs` row (system user, active=false, no matching `user_preferences`).
- The news-job run logging is stuck (section 6): no logged news run for about 26 hours despite
  news flowing.

There is **no alerting** on any of this. A job exceeding its cadence (daily over 30h, weekly
over 8d) does not page anyone, which is why three jobs silently stopped without notice.

---

## 9. Serving contract and honesty

The serving logic is sound: when a dimension is flagged limited it is hard-nulled before the
response leaves the server, and thin news returns a "Limited Data" badge and a coverage note
rather than a fabricated number. No fake scores are invented. That part of the honesty contract
holds.

The mismatch is the target. The documented SLA in `docs/CLAVIX_TRUTH.md` is "3 or more articles
in 7 days, else show Limited Data and drop the dimension from the composite," not "10 enriched
articles." The scorer faithfully implements the floor of 3, and the pipeline deliberately stops
topping up at 3 (`GOOGLE_FALLBACK_MIN_USABLE_ARTICLES = 3`, `limit_per_ticker = 8`). So the code
is honoring a contract that is materially weaker than the goal you stated. Result: 41% of the
universe is shown a 4-dimension composite every day, and the product copy ("exactly five
dimensions," "14 days of news") promises more than 40% of tickers can deliver.

Secondary serving issues: ticker-detail and `/screen` serve stale snapshots silently (no
freshness gate, only a best-effort background refresh), and user-visible coverage copy emits
`CLAVIX_TRUTH`-banned words ("Limited data," "sources," "thin," "provisional") raw to the client.

The `is_product_visible` column is NULL for all 546 (it has been true only 6 times in 26,753
historical rows) and has **no readers in the committed serving code**, so in the repo it is a
dead gate. It stopped being written 2026-05-16 along with `verification_status` and
`writer_source`. (Prod behavior cannot be confirmed from the repo because of the drift in
section 2, but the app demonstrably serves ticker data, so it is not hard-gating on this column.)

---

## 10. Complete defect register (everything short of perfect)

Severity: P0 = breaks the data promise broadly or is an integrity/operational hazard; P1 =
significant gap; P2 = partial/medium; P3 = minor.

| # | Sev | Area | Defect | Metric (verified) |
|---|---|---|---|---|
| 1 | P1 | Ops | Useful news pipeline lived only on VPS, erased by 06-24 deploy; rebuild + track it | running backend == repo (verified 0 diff); not a deploy landmine |
| 2 | P0 | News dim | `news_sentiment_dim` NULL | 223/546 (40.8%); 217 of those have articles |
| 3 | P0 | News depth | Few tickers hit 10 fully-enriched articles | 105/546 (19.2%) |
| 4 | P0 | Macro | Regression has no explanatory power; near-constant | R-squared avg 0.019, all < 0.10; avg 89.6 |
| 5 | P0 | Financial | FCF margin and interest coverage entirely missing | 546/546 NULL each |
| 6 | P0 | Source | `prices` ingestion effectively stopped | 506/546 (92.7%) no bar in 30 days |
| 7 | P0 | Source | `asset_safety_profiles` frozen | Latest 2026-05-08 (48 days) |
| 8 | P0 | Source | `sector_regime` score/beta never populated | 0 of 265 rows ever |
| 9 | P0 | Recompute | Daily recompute reads news but never ingests it | structural dead-end for news-starved tickers |
| 10 | P1 | News enrich | Deep-analysis tier almost entirely absent | 69 of 9,007 rows (0.77%) |
| 11 | P1 | News enrich | TLDR / key implications missing on ~40% | 3,614 no TLDR; 3,925 no implications |
| 12 | P1 | News enrich | Extraction fails or navigation-only | 2,442 of 9,007 (27.1%) |
| 13 | P1 | News enrich | `risk_direction` mostly missing or defaulted | NULL 35%, `neutral` default ~29% |
| 14 | P1 | Volatility | Implied vol is `estimated` for everyone | 546/546 `iv_source='estimated'` |
| 15 | P1 | Dims | `composite_score` == `safety_score` duplicate | identical for all 546 |
| 16 | P1 | Coverage | `data_status='partial'` (especially ETFs) | 223/546 (40.8%); 27/28 ETF partial |
| 17 | P1 | Gating | `is_product_visible` etc. dead | NULL all 546 since 2026-05-16, no readers |
| 18 | P1 | Jobs | `weekly_fundamentals_sweep` never ran | 0 runs ever |
| 19 | P1 | Jobs | `daily_eod_price_capture` + `daily_alert_evaluation` stopped | last run 06-23; alerts not firing |
| 20 | P1 | Financial | `revenue_growth_trend` unit bug (% vs fraction) | ~89% get max bonus, non-discriminating |
| 21 | P1 | Observability | News job-run logging stuck | no logged run ~26h while news flows |
| 22 | P1 | Macro | Regime stuck `price_only` | no credit spread; proxy-coded yield/DXY |
| 23 | P1 | Sector | Source covers 12 sectors vs 41 taxonomy | 21 NULL-sector ETFs -> NULL dim |
| 24 | P1 | Serving | SLA is 3 articles, not 10 | pipeline stops topping up at 3 |
| 25 | P1 | Serving | Copy promises 5 dims / 14d news prod cannot meet | ~40% served 4-dim daily |
| 26 | P2 | News articles | `analysis_status` / `data_status` 100% NULL | no row-level completeness flag |
| 27 | P2 | News articles | 11 documented columns 100% empty | dead/unused fields |
| 28 | P2 | Recompute | Partial/skipped recompute days, no alert | 06-21 missing; 06-14 = 5; 06-11 = 100 |
| 29 | P2 | Coverage | 11 universe tickers NULL/empty sector | feeds the 22 NULL sector dims |
| 30 | P2 | Source | `earnings_calendar` and `etf_holdings` narrow | 7.9% and ~22% of universe |
| 31 | P2 | Recompute | Two overlapping universe recompute schedules | APScheduler 8:00 ET + crontab 10:00 |
| 32 | P2 | Jobs | Weekly recompute jobs over 5 days stale | last 06-20/06-21 |
| 33 | P2 | Serving | Stale snapshots served with no freshness gate | best-effort background refresh only |
| 34 | P2 | Serving | TRUTH-banned vocabulary in client copy | "Limited data," "sources," "thin" |
| 35 | P3 | Coverage | 3 orphan `ticker_metadata` rows | 549 vs 546 |
| 36 | P3 | News | Legacy `event_analyses` still written, disconnected | ~7 positions, 0 shared links |
| 37 | P3 | Jobs | Orphaned `scheduler_jobs` row | system user, inactive |
| 38 | P3 | News | Residual A-letter bias in supply | A avg 40.4 vs others 6.7 to 20.3 |

---

## 11. Remediation plan: from "no lack" to "bountiful"

The goal you set (every ticker has 10 or more fully-enriched articles and five real dimensions,
always) requires three things the current system lacks: a real per-ticker article FLOOR (not a
ceiling of 8 and a floor of 3), a real source for the two broken dimensions (macro and IV), and
monitoring that makes any gap impossible to miss. Phased below.

### Phase 0: Stop the bleeding (do this first, this week)

1. **Deployment hygiene (section 2).** Running backend already equals the repo, so no
   reconciliation is needed and pushing is safe. Do delete the stale `/opt/clavis/.git` checkout
   (different repo, causes misleading `git status`), confirm `clavix` is the single deploy
   source, and rebuild the erased richer news pipeline as tracked code (Phase 2).
2. **Restart the dead jobs.** Get `daily_eod_price_capture` and `daily_alert_evaluation` firing
   again (they stopped 06-23), and schedule `weekly_fundamentals_sweep` (never run). Add the
   crontab entries if missing on the VPS.
3. **Clear the stuck `universe_news_refresh` run** and fix the run wrapper so it always closes
   out (so observability reflects reality).
4. **Add cadence alerting on `job_runs`:** page when any registered job's last start exceeds its
   cadence (daily over 30h, weekly over 8d, monthly over 32d). This alone would have caught items
   18, 19, 21, 32 automatically.

### Phase 1: Make every dimension real (2 to 3 weeks)

5. **News supply floor.** Raise the per-ticker target from 3 to 10+: bump
   `GOOGLE_FALLBACK_MIN_USABLE_ARTICLES` to 10 and `limit_per_ticker` to 15+, and have the news
   job top up each ticker until it has 10 usable articles rather than stopping at the first 3 to
   8. Add explicit Finnhub rate limiting (token bucket) so the serial 546-ticker loop stops
   silently dropping tickers to 429.
6. **News scoring attrition.** Loosen `_filter_news_rows_by_relevance` (match on
   `affected_tickers` / body, not just title substring), apply the `[:10]` cap after relevance
   not before, and fall back to a 14-day window when the 7-day count is under the floor. This
   recovers the 111 tickers that have articles but score NULL.
7. **Stop the freshness lie.** Only write `dimension_last_refreshed['news_sentiment']` when the
   value is non-null, or split `attempted_at` from `refreshed_at`, so the daily recompute can
   retry news-starved tickers instead of treating them as fresh.
8. **Macro.** Either source real macro inputs (true 10Y yield, real DXY, credit spreads) and
   re-fit, or suppress/down-weight `macro_exposure_dim` when R-squared is below 0.10 so a
   2%-fit regression stops inflating composites. Today it should be flagged limited, not shown
   as a real 90.
9. **Volatility IV.** Wire real Polygon options IV (verify the entitlement), or explicitly label
   the dimension as estimate-derived. Stop presenting `estimated` IV as real.
10. **Financial inputs.** Source `fcf_margin` and `interest_coverage` from a provider that
    returns them (Polygon financials or Finnhub financials-as-reported). Fix the
    `revenue_growth_trend` unit bug. Make "fresh" require at least one non-null numeric field so
    false freshness cannot mask an empty refetch.
11. **Sector source.** Populate `sector_score` / `sector_beta` in `sector_regime_snapshots`,
    reconcile the 12-sector ETF map with the 41-sector taxonomy, and backfill sector for the 11
    NULL-sector tickers.

### Phase 2: Make enrichment bountiful (2 to 4 weeks)

12. **Extraction recovery.** Add retry / alternate-extractor logic keyed on `extraction_status`,
    and accept the Finnhub/RSS summary as a usable body when full extraction fails, so the 2,442
    failed/navigation-only articles can still get a TLDR. This is the single biggest lever on the
    "10 fully-enriched" number.
13. **Backfill the analysis tier.** Run a one-time pass over the 3,709 articles that have a body
    but no `what_it_means`, then keep a daily worker that prioritizes deficient tickers. Restart
    or replace the `minimax` deep-analysis tier (69 of 9,007 rows is effectively dead).
14. **Per-ticker rotation guarantee.** Replace the blind 28-batch round-robin with a cursor that
    prioritizes tickers below 10 enriched fresh articles, so the long tail is guaranteed coverage
    within a 7-day window instead of every 4.7 days.
15. **Row-level completeness flags.** Populate `analysis_status` / `data_status` per article so
    partial enrichment can resume and "fully enriched" is queryable.

### Phase 3: Guarantee it stays that way (ongoing)

16. **Source-vs-snapshot consistency monitor.** Fail/alert when a dimension is non-null in
    `ticker_risk_snapshots` while its source table is empty or over 7 days stale (this catches
    heuristic fallbacks presenting as real data).
17. **Distribution-collapse monitor.** Fail CI/monitoring when any dimension's stddev or
    distinct-value count collapses (would have caught the degenerate macro and the A-grade
    pile-up).
18. **Daily completeness assertions.** Alert when the recompute lands fewer than 546 rows, when
    any universe ticker has fewer than 10 enriched articles, or when all-5-real coverage drops
    below target. Add a per-ticker news-coverage SLO to `weekly_universe_audit`.
19. **Reconcile the contract.** Decide the real target (10 enriched articles, five real
    dimensions) and update `CLAVIX_TRUTH.md`, the scorer thresholds, and the product copy
    together so the promise and the data match. Scrub banned vocabulary from client copy.
20. **Cleanup.** Resolve `composite_score` vs `safety_score`, the dead gating columns, the 11
    empty article columns, the orphan metadata rows, the legacy `event_analyses` path, and the
    duplicate recompute schedules.

---

## 12. Appendix: method, provenance, caveats

- All DB numbers were measured against Supabase project `uwvwulhkxtzabykelvam` on 2026-06-25
  (DB `now()` around 18:28 UTC). Queries were read-only.
- Headline numbers were reproduced at least twice from independent SQL (once by the audit
  workflow, once by hand) and by an adversarial verification pass (26 claims re-run: 22
  confirmed, 4 partial with only arithmetic/denominator corrections, 0 substantive refutations).
- Corrections applied from verification: extraction non-success is 2,442 not 2,443;
  `asset_safety_profiles` universe coverage is 503/549 not 503/546; macro had 1 missing weekday
  in 30 days (Juneteenth) not 2; the `score_to_grade` bug spanned 06-03 to 06-12 not just
  06-10/12. The agent-reported "81 tickers with 10+ in 7d" did not reproduce; the verified raw
  figure is 207 (and 128 enriched).
- **Code provenance (verified):** code references are to repo HEAD `4d7c3cb43`, which was
  confirmed byte-for-byte identical to the running production backend on 2026-06-25 (direct VPS
  diff, 0 files/0 lines). So file:line root causes describe the running code exactly. (An earlier
  draft wrongly claimed prod ran divergent uncommitted code; that was a stale extra `.git`
  checkout of a different repo causing a misleading `git status`, since corrected.)
- Full machine-readable findings and the verification verdicts are in the audit workflow output
  for this session.
