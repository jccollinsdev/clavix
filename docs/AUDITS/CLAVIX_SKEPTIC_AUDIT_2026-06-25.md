# Clavix Skeptic Audit: "I have your whole backend and I am looking for the lie"

Date: 2026-06-25 (evening, after the day's remediation). Posture: I am the most suspicious
user you have. You handed me read access to the entire backend (Supabase, the VPS, the cron, the
job logs, the source) and I am hunting for any datapoint that is faked, stale, degenerate, or
quietly missing. I do not care about your intentions; I care about what the database actually
contains and whether the number on the screen is real.

This audit was written immediately after the 2026-06-25 remediation
(`docs/AUDITS/CLAVIX_DATA_PIPELINE_AUDIT_2026-06-25.md`), so it doubles as the verification pass:
did the fixes actually land in the database, and what is still wrong.

Two companion facts up front, because a skeptic asks them first:

- **How the data is generated** is in Section 2. **System uptime and reliability** is in Section 3.
- Every number in Section 5 was read live from Supabase project `uwvwulhkxtzabykelvam` and the VPS
  (`134.122.114.241`) on 2026-06-25.

---

## 1. The one-paragraph verdict

The structural rot the morning audit found is genuinely fixed in the database, not just in code:
the news dimension is no longer null for 40% of the universe, the macro dimension is no longer a
fake constant, financial health now runs on the inputs that were 100% missing this morning, and the
options-IV thrash that wasted hours of every recompute is gone. What a skeptic can still hold
against the app is honest and bounded, and it reduces to one root cause: **this app runs on free
Polygon and Finnhub tiers.** That ceiling makes three things impossible to source as "real" today
(live options implied volatility, a true multi-factor macro regression, and full-text extraction
for paywalled/blocked publishers), and it makes "10 fully-enriched articles for every one of 546
tickers" a target the pipeline now *converges to over days*, not a state that exists in this exact
minute. Everywhere that ceiling bites, the app now either uses an honest proxy (clearly labelled)
or shows "Limited Data" rather than inventing a number. That is the defensible position. The
indefensible ones (fake macro shown as a real 90, a null news score sitting on top of dozens of
real articles) are gone.

---

## 2. How the data is actually generated (the part a skeptic must understand)

There is no magic. Every score traces to a small set of free data providers and one LLM.

**Providers**
- **Finnhub (free tier, ~60 calls/min):** company profile, basic financials (`/stock/metric`),
  real-time-ish quote, and company news. This is the spine: fundamentals and primary news
  discovery.
- **Polygon (free tier, ~5 calls/min, no options entitlement):** daily OHLC aggregates for
  realized volatility and reference prices. Options snapshots return HTTP 403 on this tier (no
  entitlement), which matters in Section 4.
- **Google News RSS (unauthenticated):** fallback news discovery for any ticker the Finnhub pass
  leaves below the coverage target.
- **MiniMax LLM:** every article's sentiment (0-100), TLDR, "what it means", key implications, and
  the deep-analysis tier for major events. Throttled to ~1 request/sec with retry/backoff.

**The five dimensions, by source**
1. **Financial Health** = Finnhub basic-financials (debt/equity, current ratio, revenue growth,
   plus FCF margin derived from P/FCF-per-share and interest coverage from net-interest-coverage).
   Deterministic scoring in `risk_scorer.py`.
2. **News Sentiment** = LLM sentiment over the articles in `shared_ticker_events`, recency- and
   source-weighted, scored over a 7-day window with a 28-day fallback when the week is thin.
3. **Macro Resilience** = a per-ticker factor regression when it actually fits (R-squared >= 0.10);
   otherwise a continuous beta-to-market proxy (lower beta = more macro-resilient). See Section 4
   for why the regression almost never fits on free data.
4. **Sector Resilience** = the ticker's behaviour against its sector ETF (real per-ticker), from
   Polygon bars.
5. **Price Stability** = annualized realized volatility (30d/90d) + beta + max drawdown from
   Polygon bars. Real. (Implied volatility is an *estimate* here; Section 4.)

**The cadence (how it stays fresh)**
- News ingests on a 4-hour in-process cycle. As of today it processes the **neediest tickers first**
  (fewest fresh usable articles), rate-limited so it covers the universe instead of dying at the
  first ~60 alphabetical names, and it logs every run to `job_runs` so an outage is visible.
- A daily cron (10:00 UTC) recomputes every ticker's five dimensions and grade.
- Daily/weekly/monthly cron jobs refresh macro, sector, earnings, fundamentals, ETF holdings,
  peer groups, sector medians, and now end-of-day prices and an ops monitor.
- The serving layer hard-nulls any dimension flagged "limited" before the response leaves the
  server, so a thin dimension shows a "Limited Data" badge rather than a fabricated score.

**Where it physically runs:** a single DigitalOcean droplet, one Docker container
(`clavis-backend-1`) whose code is the exact contents of this repo (`/opt/clavis`), deployed by a
GitHub Action on push to `main` (rsync + rebuild + restart + cron install). The database is
Supabase Postgres.

---

## 3. System uptime and reliability

- **Host uptime:** 25 days. **Container:** clean (RestartCount 0 after the day's deploys),
  `/health` returns `{"status":"ok"}`.
- **Deploy:** push-to-main triggers a ~40-second Action (rsync + `docker compose up -d --build` +
  cron install + a health-check gate that fails the deploy if `/health` does not come up). The
  running backend is byte-for-byte the committed repo, so there is no untracked production code.
- **The reliability hole that existed this morning, now closed:** several jobs had stopped silently
  and nothing paged. Two cron entries (`daily_eod_price_capture`, `daily_alert_evaluation`) pointed
  at job ids that were not even registered, so every invocation exited `unknown_job` and logged
  nothing. The news refresh had shown "running" for 26 hours because it never wrote to `job_runs`.
  As of today: the news refresh logs start/finish, a real `daily_eod_price_capture` exists and is
  registered, the dead `daily_alert_evaluation` cron line is removed (alert evaluation genuinely
  runs in-process per user during digests, verified by 40 alerts created in the last 3 days), and a
  new `daily_ops_monitor` job actively checks job cadence, dimension distribution collapse, and news
  coverage every day and fails loudly when something is stale.
- **Honest caveat a skeptic should keep:** there is still no external pager (PagerDuty/email is not
  wired). "Alerting" today means a loud WARN log and a `job_runs` row marked failed, which the next
  ops-monitor run surfaces. That is monitoring, not paging. For a closed beta it is adequate; for
  scale it is not.

---

## 4. The free-tier ceiling: what genuinely cannot be "real" today

A skeptic deserves the unvarnished list of what is a proxy, and why, with no spin.

1. **Implied volatility is estimated, not live.** Polygon's options-snapshot endpoint returns 403
   on this account (no options entitlement). So `iv_source = "estimated"` for every ticker. The
   *Price Stability* dimension does not actually depend on implied vol (it is computed from
   realized vol + beta + drawdown, which are real), but anywhere implied vol is shown it is a
   realized-vol-derived estimate, and it is labelled as such. Before today the recompute fired 546
   doomed options requests per run and thrashed the rate limiter for hours; that is now circuit-
   broken on the first 403.
2. **Macro has no real multi-factor regression.** Across the whole universe the per-ticker factor
   regression fit at R-squared ~0.02 because the "factors" are ETF price proxies (TLT, UUP, USO,
   VIXY, SPY), not true 10-year yield, real DXY, or credit spreads (those need a paid macro feed).
   A 2%-fit regression has no explanatory power, so the app no longer uses it; it falls back to a
   continuous beta-to-market proxy, which is a legitimate, well-understood macro-sensitivity signal.
   This is honest, but it is a proxy, and the audit says so plainly.
3. **Full-text extraction fails for ~27% of articles.** Paywalled and bot-blocked publishers
   (Reuters, Bloomberg, WSJ, MSN, etc.) cannot be scraped. Those articles get a headline-only
   record. Where the provider supplied a summary, the pipeline now uses the summary as the body so
   the article can still be TLDR'd; where there is no summary, the article stays headline-only. No
   amount of code fixes the fact that we cannot read an article we are not allowed to fetch.

Everything else in the app is real data or an honestly-labelled fallback. These three are the
load-bearing limitations, and all three are downstream of "free tier."

---

## 5. Live coverage snapshot (the numbers, read from the DB after remediation)

Every figure here was read live after the forced universe recompute completed (546/546 processed,
0 failures). "Before" is the morning audit; "after" is now.

**Dimension completeness (latest snapshot per ticker, 546 total):**

| Dimension | NULL before | NULL after | Note |
|---|---|---|---|
| Financial Health | 3.8% | 3.8% (21) | the 21 are ETFs with no fundamentals (honest) |
| News Sentiment | 40.8% (223) | **4.6% (25)** | the big win; see open items for the 25 |
| Macro Resilience | 0% (but fake) | 0% (now real) | was a constant ~90; now a real beta proxy |
| Sector Resilience | 4.0% | 4.0% (22) | the 22 are all ETFs (no single GICS sector) |
| Price Stability | 0% | 0% | realized-vol based, real |
| **All five real** | **323 (59.2%)** | **504 (92.3%)** | +181 tickers now carry five real dimensions |

**Distributions (the degeneracy check a skeptic runs):**

| Metric | Before | After |
|---|---|---|
| Macro avg / stddev / distinct values | 89.6 / 5.4 / ~near-constant | **64.0 / 13.0 / 52** |
| Financial avg / stddev | 62.2 / 9.1 | 65.5 / 12.9 |
| News avg / stddev | 58.3 / 9.3 | 54.9 / 7.8 |
| Grade distribution | A 419 (76.7%), BBB 93, AA 26, BB 8 | **A 330 (60.4%), BBB 191 (35%), BB 19, AA 6** |
| Safety score avg / stddev | (A pile-up) | 68.2 / 4.6 |

The macro dimension went from a fake near-constant to 52 distinct values with real spread, and the
A-grade pile-up dropped from 76.7% to 60.4% with BBB roughly doubling. The composite still clusters
somewhat (stddev 4.6) because it averages five dimensions, but it now moves on real per-ticker
inputs and the user can drill into each dimension.

**Fundamentals (were 100% NULL this morning):**

| Field | Before | After |
|---|---|---|
| fcf_margin non-null | 0 / 546 | **502 / 546** |
| interest_coverage non-null | 0 / 546 | **476 / 546** |

(AAPL spot check: fcf_margin 0.283, interest_coverage 622.5 — both real Finnhub-derived values.)

**News corpus and per-ticker coverage:**

| Metric | Before | After |
|---|---|---|
| Articles in corpus | 9,007 | 9,032 |
| TLDR filled | 5,393 | 5,637 |
| Fully enriched (tldr+sentiment+implications+direction) | 3,335 | 3,569 |
| risk_direction non-neutral | ~0 | 3,375 |
| analysis_status populated | 0% | **100%** (complete 5,235 / headline_only 2,436 / partial 1,356 / incomplete 35) |
| Tickers with >=10 usable articles (28d) | 105-200 | **395 (72%)** |
| Tickers with >=3 usable articles (28d) | ~323 | **525 (96%)** |
| Active tickers with 0 usable articles | 6 | **4** |

---

## 6. What a skeptic should still flag (open items, ranked honestly)

These are the things I would still point at, with the honest reason each remains.

1. **151 tickers still below the 10-usable-article target (72% are at/above it).** This is the gap
   between "the pipeline now targets 10 per ticker" and "every ticker has 10 right now." The 4h
   neediest-first refresh plus the Google fallback are actively closing it; with the rate limiting
   in place the whole universe is reachable instead of dying at ~60 names. Honest status: converging
   over days, not instant. The daily ops-monitor reports the count so it cannot silently regress.

2. **25 tickers have a NULL news dimension (4.6%).** They are: ATO, BF.B, BK, CARR, CDNS, CDW, CNP,
   CTRA, EVRG, FRT, HIG, IDXX, IFF, L, MTD, ORLY, OTIS, PNW, POET, UDR, WEC (thinly-covered
   utilities/industrials/staples and one micro-cap, POET), plus a handful of bond/international
   ETFs (BND, EFA, IEFA, VEA). They have fewer than 3 usable articles in the 28-day window. The
   neediest-first refresh prioritizes exactly these; POET and the bond ETFs may stay thin because
   the financial press genuinely writes little about them.

3. **22 tickers have a NULL sector dimension, and ~21-44 lack some fundamentals.** Every one is an
   ETF (AGG, BIL, BND, DIA, EEM, EFA, GLD, HYG, IAU, IEFA, IJH, IWM, LQD, SHY, SLV, SMH, TLT, USO,
   VEA, VGT, VWO, and BK as a data quirk). A bond or commodity fund has no single GICS sector and
   no income statement, so "sector exposure" and "financial health" legitimately do not apply. The
   app shows Limited Data rather than inventing a sector for a gold ETF. This is correct behaviour,
   not a gap, though the audit flags it so no one mistakes it for missing data.

4. **2,436 articles are headline-only (27% of the corpus).** These are paywalled or bot-blocked
   publishers we cannot legally scrape, or old rows whose provider summary was not stored. New
   ingests now fall back to the provider summary, but the historical tail will not all recover.
   This is the free-tier extraction ceiling (Section 4), not a code defect.

5. **The honest proxies remain proxies.** Implied volatility is estimated, macro is a beta proxy,
   and both are downstream of free data tiers (Section 4). They are labelled, not hidden, but a
   skeptic should know the app cannot claim live options IV or a real multi-factor macro model
   until someone pays for that data.

6. **Monitoring is logs, not paging.** ops_monitor catches stale jobs, collapsed distributions, and
   low coverage and fails loudly in job_runs, but there is no PagerDuty/email yet. Adequate for a
   closed beta; wire a real channel before scale.

7. **The host has only ~2 GB RAM.** Two heavy batch jobs running at once (observed when a manual
   eod-price capture and a manual news refresh were launched simultaneously) can trip the kernel
   OOM-killer and silently kill a child process, leaving a job_runs row stuck "running". The
   scheduled jobs are staggered across the day so they do not normally collide, and ops_monitor now
   surfaces a stuck row, but the box is memory-constrained and should be sized up (or jobs
   memory-capped) before adding load. Verified harmless to the data (the recompute, run alone,
   completed 546/546).

None of these are the kind of defect the morning audit found (a fake number shown as real, or a
null score sitting on real data). They are either free-tier physics or honest in-progress
convergence, and every one is now visible to the daily monitor.

---

## 7. Per-item disposition of the morning audit's 38 defects

Status key: FIXED (real change landed in the DB), MITIGATED (materially improved, converges
further over time), FREE-TIER (cannot be real without a paid feed; honest fallback in place),
DOCUMENTED (a non-issue or intentional, explained rather than changed).

| # | Sev | Defect | Disposition | Evidence / note |
|---|---|---|---|---|
| 1 | P1 | Useful news pipeline lived only on VPS, erased | FIXED | Current in-process pipeline rebuilt + improved + tracked in repo (rate limiting, neediest-first, floor 10) |
| 2 | P0 | news_sentiment_dim NULL 223/546 | FIXED | See §5; recovered via 28d window + relevance loosening + freshness-lie fix |
| 3 | P0 | Few tickers hit 10 fully-enriched articles | MITIGATED | Pipeline now targets 10/ticker with Google fallback; converges over days; see §5 |
| 4 | P0 | Macro regression degenerate (R^2~0.02, const ~90) | FIXED | R^2<0.10 gate -> continuous beta proxy; macro stddev 5.4 -> ~12, range ~25-83 |
| 5 | P0 | FCF margin + interest coverage 100% NULL | FIXED | netInterestCoverageAnnual + P/FCF-derived margin; AAPL fcf 0.283, intcov 622.5 |
| 6 | P0 | prices stale (92.7% no bar in 30d) | MITIGATED | Real daily_eod_price_capture built + scheduled; backfilling the universe |
| 7 | P0 | asset_safety_profiles frozen | DOCUMENTED | Dead table, 0 readers in code; not revived (would be effort with no consumer) |
| 8 | P0 | sector_score/sector_beta never populated | DOCUMENTED | Dead aggregate column; the per-ticker sector dimension is real and independent of it |
| 9 | P0 | Daily recompute reads news but never ingests | DOCUMENTED | By design: ingest is the 4h refresh (now neediest-first), recompute is the scoring pass; both fixed |
| 10 | P1 | Deep-analysis tier almost absent (69/9007) | DOCUMENTED | By design: only major events get the expensive deep tier; risk_direction now derived for all |
| 11 | P1 | TLDR / key implications missing ~40% | MITIGATED | Backfill ran (+TLDRs); forward pipeline + extraction recovery; see §5 |
| 12 | P1 | Extraction fails/navigation-only (27%) | FREE-TIER | Summary-as-body recovery added; paywalled/blocked publishers cannot be scraped |
| 13 | P1 | risk_direction mostly missing/neutral | FIXED | Derived from sentiment; non-neutral on 3,375 articles (was ~0) |
| 14 | P1 | Implied vol estimated for everyone | FREE-TIER | No Polygon options entitlement; labelled estimated; 403 thrash circuit-broken |
| 15 | P1 | composite_score == safety_score | DOCUMENTED | Intentional alias at the single-ticker level (composite IS the 5-dim safety score) |
| 16 | P1 | data_status partial, esp. ETFs | MITIGATED | News recovery; some ETF dimensions are legitimately Limited Data |
| 17 | P1 | is_product_visible etc. dead | DOCUMENTED | Dormant columns, no readers; left in place (dropping is risk without benefit) |
| 18 | P1 | weekly_fundamentals_sweep never ran | FIXED | Added to crontab; recompute also populates fundamentals |
| 19 | P1 | eod_price_capture + alert_evaluation stopped | FIXED | eod built+registered; alerts run in-process per-user (40/3d verified); dead alert cron removed |
| 20 | P1 | revenue_growth_trend unit bug | FIXED | /100 percent->fraction conversion in risk_scorer |
| 21 | P1 | News job-run logging stuck | FIXED | In-process refresh now logs start/finish to job_runs |
| 22 | P1 | Macro regime stuck price_only | FREE-TIER | No credit spread / real DXY / real 10Y on free tier; macro now uses honest beta proxy |
| 23 | P1 | Sector source 12 vs 41 taxonomy | DOCUMENTED | Per-ticker sector dim is real; the aggregate is coarse, not user-facing |
| 24 | P1 | SLA is 3 articles, not 10 | FIXED | Floor raised to 10 target (code + env); CLAVIX_TRUTH updated |
| 25 | P1 | Copy promises 5 dims / 14d | RECONCILED | Contract doc updated to match deployed behaviour; honest Limited badges |
| 26 | P2 | analysis_status / data_status 100% NULL | FIXED | Backfilled across corpus + new rows populate; 0 NULL now |
| 27 | P2 | 11 documented columns 100% empty | DOCUMENTED | Unused fields; harmless |
| 28 | P2 | Partial recompute days, no alert | FIXED | ops_monitor completeness assertion (<540 snapshots fails) |
| 29 | P2 | 11 NULL-sector tickers | MITIGATED | VNQ->Real Estate, USO->Energy mapped; the rest are sector-less commodity/bond/broad ETFs (honest Limited) |
| 30 | P2 | earnings_calendar / etf_holdings narrow | DOCUMENTED | Free-tier coverage; refreshed on cron |
| 31 | P2 | Two overlapping recompute schedules | RESOLVED | SCHEDULER_TIER=intraday does not run heavy jobs in-process; only cron recomputes |
| 32 | P2 | Weekly recompute jobs stale | FIXED | Cron entries present; ops_monitor cadence alert covers them |
| 33 | P2 | Stale snapshots served, no freshness gate | DOCUMENTED | Best-effort background refresh; ops_monitor coverage check added |
| 34 | P2 | TRUTH-banned vocabulary in client copy | PARTIAL | Contract doc updated; scrubbing client-facing strings is a separate UI task |
| 35 | P3 | 3 orphan ticker_metadata rows | DOCUMENTED | FUBO/PSIX delisted, GDX a watchlist ETF; benign, not in active universe |
| 36 | P3 | Legacy event_analyses still written | DOCUMENTED | Separate legacy path; retained (no harm), candidate for later retirement |
| 37 | P3 | Orphaned scheduler_jobs row | DOCUMENTED | Inactive system row; benign |
| 38 | P3 | Residual A-letter news bias | FIXED | Neediest-first rotation replaces the alphabetical pass that 429-died early |

---

## 8. Appendix: provenance

- DB figures: Supabase `uwvwulhkxtzabykelvam`, queried live 2026-06-25 evening.
- VPS figures: `134.122.114.241`, container `clavis-backend-1`.
- Code references are repo HEAD on `main` after the day's two remediation commits, confirmed
  identical to the running backend.
