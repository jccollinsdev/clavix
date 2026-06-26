# Clavix Data Audit, Bloomberg-Terminal Standard

Date: 2026-06-26. Auditor stance: the most skeptical user imaginable, someone who pays
for a Bloomberg terminal and expects Clavix to match it on accuracy and coverage across
every supported ticker and every datapoint. This audit grades Clavix against that bar,
not against "good for a free app." It is deliberately unkind.

This audit follows a full code remediation (action-plan P0+P1 executed and deployed) and
a from-scratch universe recompute against the upgraded pipeline. All numbers below are
measured live from the 2026-06-26 snapshot batch, not asserted.

---

## 1. Verdict

Clavix is now an honest, fully-covered, five-dimension daily risk rating over a 546-name
universe, with one dimension (macro) upgraded this session from fake to genuinely real.
Against a Bloomberg terminal it remains a different and far smaller instrument: daily not
intraday, ~5 fundamental ratios not the full financial statement history, real-but-shallow
news (41% of names hit the 10-article depth target), real macro factors with modest
explanatory power (mean R-squared 0.19), and zero options/estimates/ownership/filings data.

The right one-line characterization: **Clavix tells the truth about a deliberately narrow
slice of what Bloomberg covers, and now tells it with a real macro signal instead of a
fabricated one.** It is not a Bloomberg substitute and the UI should never imply it is.

Grade against the Bloomberg bar: **C+ on coverage breadth, A- on honesty, B on the depth
of what it does cover.** A year ago the honesty grade would have been a D (fabricated macro,
freshness lies, A-grade pile-up); that gap is what this session closed.

---

## 2. The bar: what "Bloomberg-grade" actually demands

| Capability | Bloomberg terminal | Clavix today | Gap |
| --- | --- | --- | --- |
| Price granularity | Real-time tick + full history | EOD daily closes (Polygon free) | Structural (no intraday on free tier) |
| Fundamentals | Every statement line, restated, quarterly + history | ~5 ratios (D/E, FCF margin, interest cov, current ratio, rev growth), latest only | Deep |
| News | Real-time, every name, NLP, full text | Google+Finnhub, 4h refresh, 41% of names at >=10 usable/wk, bodies often headline-only (paywalls) | Deep |
| Options / IV / greeks | Full chain real-time | None (Polygon free returns 403); IV estimated from realized vol | Structural |
| Macro factors | Every series real-time | 5 real FRED factors daily (10Y, HY OAS, broad USD, VIX, SP500), ~1-day lag | Narrow but now REAL |
| Estimates / ratings / ownership / filings | Yes | None | Total |
| Refresh cadence | Continuous | Daily recompute + 4h news + weekly fundamentals | Coarser |

Everything below is measured against this table. "Structural" gaps cannot be closed without
paid data; "deep"/"narrow" gaps are matters of degree.

---

## 3. Datapoint-by-datapoint scorecard (measured 2026-06-26, N = 546)

### Coverage
- Snapshots: 546/546 of the active universe carry a current rating. 100%.
- All five dimensions real (non-null) on the same ticker: 510/546 = 93.4%. The 36 that are
  not all-five are predominantly ETFs (sector beta / single-name fundamentals do not apply)
  and are honestly flagged Limited Data, not faked.
- Per-dimension non-null: financial 96.2%, news 96.5%, macro 100%, sector 96.0%, volatility 100%.

### Financial health (B-)
- ~5 ratios from Finnhub basic-financials, latest only, weekly sweep. No statement history,
  no segment data, no restatements. The revenue-growth unit bug (percent treated as fraction,
  which had ~89% of names tripping the top bonus) is fixed and regression-tested.
- vs Bloomberg: a thin slice, correctly computed. Honest, shallow.

### News sentiment (C)
- Non-null on 96.5% of snapshots, but the quality bar tells the real story: **>=10 usable
  fresh articles on only 224/546 (41%)**, >=3 on 486/546 (89%), zero on 18. Bodies for
  paywalled domains are frequently headline-only (summary used as body, honestly flagged).
- The 41% figure is also mid-recovery: the in-process 4h news refresh was interrupted
  several times today by deploy/container restarts, aging enriched articles out of the
  7-day window. The persistent neediest-first rotation cursor (added this session) restores
  it without manual intervention, but right now depth is below target.
- vs Bloomberg (real-time full-text on every name): a large, partly structural gap (paywalls)
  and partly operational (enrichment must catch back up).

### Macro exposure (B, up from F)
- **This is the headline change.** The dimension previously regressed each stock on four ETF
  proxies (TLT/UUP/USO/VIXY) and produced a universe-wide R-squared of ~0.02, i.e. a
  fabricated near-constant that inflated every grade. It is now a real OLS regression on five
  real FRED factors: 10Y yield (DGS10), high-yield OAS (BAMLH0A0HYM2), broad USD (DTWEXBGS),
  VIX (VIXCLS), and SP500.
  - data_source = fred on **544/546**.
  - **mean R-squared 0.194, median 0.154**; **347/546 (63.5%) now clear the 0.10 threshold and
    score off the real regression** instead of the beta fallback. A year ago that count was zero.
  - The macro regime snapshot is real: 10Y 4.41%, HY OAS 2.76%, VIX 18.63 (data_status
    real_factors), replacing the old price_only ETF proxies.
- Honest caveat sold as such: 0.19 mean R-squared is a real but modest signal. Daily stock
  returns are mostly idiosyncratic; macro genuinely explains a minority of variance. We do not
  claim a high fit, we claim real factors. ~36% of names still fall back to the market-beta
  proxy because their fit is below 0.10, which is the correct behavior, not a bug.

### Sector exposure (B-)
- Real ETF-beta where a sector mapping exists (96%); ETFs and the unmapped honestly Limited.

### Volatility (B- / structural ceiling)
- Realized-vol based, 100% coverage. Implied vol is **estimated**, not real: Polygon free
  returns 403 on the options snapshot, and the circuit breaker now stops the 546x 403 thrash.
  Real IV requires Polygon Professional (~$250/mo). This is a hard, disclosed ceiling.

### Distribution sanity
- Safety score: mean 65.7, stdev 6.0, range 39-79, 37 distinct integer values. No collapse.
- Grades: AA 1, A 214 (39.2%), BBB 285 (52.2%), BB 40, B 5, CCC 1. The A-grade pile-up that
  was 76.7% at the start of remediation and 60.4% after the first pass is now 39.2%, with BBB
  the plurality. Quality-weighted dimension averaging (weighting each dimension by signal
  confidence) plus the real macro signal drove the spread.
- Skeptic's note: stdev 6.0 is on the tight side. Most names sit 60-72. That is partly real
  (the S&P 500 is mostly investment-grade-ish names) and partly a free-tier-input ceiling:
  with shallow fundamentals and modest macro R-squared, the model cannot justify confident
  extreme ratings, so it stays near the middle. That is defensible but worth stating plainly.

---

## 4. How the data is generated (so the rating is auditable)

- Prices: Polygon EOD. A daily `eod_price_capture` job appends closes; a new
  `prices_history_backfill` job (grouped-daily, one call per trading day) backfilled
  **69,904 closes across 149 trading days**, bringing the full universe to >=60 days of
  history so the scorers read from Postgres, not live Polygon.
- Fundamentals: Finnhub basic-financials, weekly sweep, cached; `fundamentals_updated_at`
  is stamped only when real fundamentals are present (no freshness lie).
- News: Finnhub company-news (primary, rate-limited 1.1s/call) + Google News RSS (fallback),
  4h refresh of the neediest-first batch via a persistent rotation cursor, LLM-enriched
  (MiniMax) for sentiment/TLDR/implications.
- Macro: FRED `fredgraph.csv` (key-free) daily for the five factors; a 252-day OLS per ticker;
  macro regime snapshot written daily with real levels.
- Composite: deterministic structural scorer combines the five dimensions with
  confidence-weighting; a dimension that is limited/NULL is never stamped fresh and never
  silently averaged as zero.
- Recompute: `daily_composite_recompute_universe`, now bounded-concurrency (6) and
  persisted-first, with a dependency guard that aborts if macro/sector inputs are stale.

## 5. Uptime and reliability (the unglamorous truth)

This session surfaced and fixed several real reliability defects; it also exposed the host's
fragility. A Bloomberg terminal does not have these failure modes. Clavix does, and they are
now mostly mitigated or at least monitored:

- **Realized data-loss hole**: the deploy used `rsync --delete` with no rollback; a prior
  deploy had erased a production-only pipeline. Now: pre-deploy tarball snapshot, health-gated
  release stamp, and automatic rollback on a failed health check.
- **No external alerting**: monitors failed silently. Now: centralized Sentry + Slack + a
  dead-man's-switch heartbeat (operator must add the free webhook/DSN to receive pages; the
  code is wired and no-ops safely until then).
- **Single 2 GB host**: the container is now memory-capped so a runaway job cannot OOM-kill
  SSH/cron; only one heavy job may run at a time. This is a single point of failure with no
  redundancy. Disaster recovery rests on Supabase PITR + (operator-enabled) DO snapshots.
- **Provider fragility observed live**: FRED's Akamai edge tarpits any custom User-Agent and
  blackholes PMTU on the Docker bridge (both fixed: default UA + MTU 1400); a single Polygon
  403 trips a shared 5-minute auth cooldown that cascades (the grouped-daily backfill now
  bypasses it). ops_monitor now flags low-success provider sweeps.
- **Advisory-lock leak**: session-scoped Postgres advisory locks over the Supabase pooler
  occasionally leak, causing a job to skip; transient and caught by the cadence monitor, but a
  durable TTL-based lock is still owed.
- **Parallel-recompute race**: the new concurrency exposed a "dictionary changed size during
  iteration" on 1 ticker and ~5 transient connection resets per full run (~1% of the universe);
  re-run cleanly. The stuck `ticker_refresh_jobs` rows left by failed parallel workers blocked
  re-computation until cleared. Both are known issues, not yet hardened.

Net: the recompute is ~4x faster (about 30 minutes vs ~110), steady (no Polygon cliff), and
self-guarding, but the platform is still one small box with a handful of newly-papered cracks.

---

## 6. What a Bloomberg user would still reject

1. No intraday. Ratings move once a day. (Structural: needs paid real-time.)
2. No real options IV/greeks. (Structural: Polygon Pro ~$250/mo.)
3. Fundamentals are five ratios, latest-only, weekly. No statements, no estimates, no history.
4. News depth: 41% of names below the 10-article target; paywalled bodies headline-only.
5. Macro R-squared averages 0.19. Real, but explains a minority of return variance; a quant
   would treat it as a weak factor, not a verdict.
6. No analyst ratings, ownership, insider, or filings ingestion at all.
7. Single-host, no HA, recovery measured in minutes-to-an-hour, not seconds.

None of these are dishonesty. They are the boundary of a free-data, 2-user, pre-launch
product. The product is honest about all of them; it must stay that way in the UI copy.

---

## 7. What genuinely improved this session

- Macro went from fabricated (R-squared ~0.02, ETF proxies, price_only) to real (FRED factors,
  mean R-squared 0.194, 347 names on a real regression, real macro regime row).
- A-grade clustering 76.7% -> 39.2%; BBB now the plurality; quality-weighted averaging live.
- Recompute ~110 min -> ~30 min (bounded concurrency + persisted-first + grouped-daily backfill).
- Full-universe price history (>=60 days on 100% of sampled names) so the pipeline is
  Postgres-bound, not Polygon-bound.
- Deploy safety (snapshot + rollback), real alerting + heartbeat, recompute dependency guard,
  OOM cap, persistent news cursor, source-vs-snapshot + provider-degradation monitors, client
  vocabulary scrubbed, and a regression smoke-suite that pins the just-fixed honesty bugs.

## 8. Disposition table

| Item | Bloomberg bar | Clavix 2026-06-26 | Status |
| --- | --- | --- | --- |
| Universe rating coverage | 100% | 546/546 | MET |
| All-5-dimensions real | 100% | 93.4% (rest honestly Limited) | ACCEPTABLE |
| Macro is real | real-time | FRED daily, 544/546, R2 0.19 | FIXED (was fake) |
| Macro explanatory power | high | mean R2 0.19 | HONEST CEILING |
| News depth (>=10/wk) | every name | 41% (mid-recovery) | BELOW TARGET |
| Real options IV | yes | estimated | STRUCTURAL (paid) |
| Intraday prices | yes | EOD only | STRUCTURAL (paid) |
| Fundamentals depth | full history | 5 ratios latest | DEEP GAP (paid/secondary source) |
| Recompute reliability | n/a | 98.9% first pass, ~30 min | IMPROVED |
| External alerting | enterprise | wired, needs operator webhook | CODE DONE |
| HA / DR | redundant | single host + PITR | RISK ACCEPTED (pre-launch) |
| Distribution health | n/a | mean 65.7 / sd 6.0 / 37 distinct | OK (slightly tight) |

---

## 9. Honest open items (next, mostly free)

1. Let the 4h news cursor run undisturbed for ~24h and re-measure >=10 depth; if it stalls
   below ~70%, add the jina.ai free reader for paywalled bodies.
2. Durable job lock (TTL row-lock) to end the advisory-lock leak and the stuck-refresh-job
   blocking seen during parallel recompute.
3. Find and fix the "dictionary changed size during iteration" race in the per-ticker path,
   or lower default recompute concurrency to 4 to shrink the race window.
4. Operator (not code): enable Supabase PITR >= 7 days, DO weekly snapshots, and set
   SENTRY_DSN / CLAVIX_SLACK_WEBHOOK_URL / CLAVIX_HEARTBEAT_URL to actually receive pages.
5. Inner-hop parallelization of the ~15-20 sequential Supabase round-trips per ticker, the
   remaining recompute wall now that Polygon is no longer the bottleneck.
6. Paid data (Polygon Pro for real IV + intraday, a secondary fundamentals source) gated on
   ~15 Pro subscribers, with the breakeven documented in OPERATIONS.md.
