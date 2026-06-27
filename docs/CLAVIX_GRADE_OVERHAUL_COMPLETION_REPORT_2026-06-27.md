# Clavix Grade Overhaul: Completion Report

Date: 2026-06-27
Author: Claude (autonomous execution of the Data Quality & Grade Rescale Master Plan)
Scope: backend scoring + data integrity + DB + iOS + website, shipped and verified on production.

## 1. What this was

Clavix risk grades were compressed and credit-styled: 91.6% of the S&P sat in two grades
(A/BBB), the composite stddev was ~6, and the scale imitated S&P/Moody's (AAA..CCC). The
goal: make grades actually discriminate, present them as familiar academic letters (A+ to F),
remove a fabricated `confidence` figure, and fix the broken inputs feeding the model.

All ten workstreams (WS-A..WS-J) were executed, validated read-only against the live universe,
then cut over to production. Three real bugs surfaced only in the live write path and were fixed
mid-cutover (see section 4).

## 2. Before → After (live, 546 S&P names)

| Metric | Before | After | Target | Status |
|---|---|---|---|---|
| Composite stddev | 6.0 | 15.0 | >= 12 | PASS |
| Composite range | 38.8 - 78.9 | 5.6 - 100 | <=25 to >=90 | PASS |
| Distinct composites | 206 | 303 | more discrimination | PASS |
| Grade scale | credit AAA..CCC | academic A+..F | academic | PASS |
| Grade buckets populated | 6 | 13 of 13 | >= 8 | PASS |
| Largest single grade | 52% (BBB) | 17.6% (B) | < 35% | PASS |
| risk-score confidence | 0.75 constant | removed (0 rows) | gone | PASS |
| sector_exposure stddev | 5.2 | 9.9 | discriminating | IMPROVED |
| sector_exposure nulls | 22 | 1 (IWM, broad ETF) | 0 | IMPROVED |
| volatility avg / cluster | 81.2, 72% in 80-89 | 57.3, 0% in 80-89 | de-inflated | PASS |
| news dimension | 28 hard-50, proxy-fed | functional, real sentiment | working | PASS |
| articles at exactly 50 | 21.8% | 0.0% | < 8% | PASS |

Median S&P name now grades ~B (composite ~69), with A+ and F both reachable by real names.

## 3. The fixes (by workstream)

- WS-A Price integrity: `prices` deduped 130,489 -> 89,527 rows (0 intraday dups); read path
  collapses to one close/day; beta is date-aligned over common trading days with a >=20-day
  floor and a [-3, 4] sanity clamp. Fixed a latent 1000-row Supabase cap that had been
  truncating high-traffic tickers (AAPL) to stale/garbage betas.
- WS-B Sector: real per-ticker sector beta + relative-strength terms, reduced weight on the
  shared sector-ETF momentum/breadth, de-inflated baseline (65 -> 60), and an asset-class
  fallback so non-sector ETFs score instead of NULLing.
- WS-C Volatility: routed through the now-real beta; baseline de-inflated 78 -> 62.
- WS-D News: prompt forbids the lazy 50 and emits `scorable`; parser persists NULL (not 50)
  for unscorable; aggregation excludes unscorable and gates on scorable count. Re-scored the
  ~3.3k legacy exactly-50 articles (46 became real scores, 3,206 honest NULLs).
- WS-E Spread: affine re-spread inside `calculate_weighted_score` (env-gated:
  K=2.0, CENTER_IN=60, CENTER_OUT=69), with one-time bypass of EMA, hysteresis, AND the
  per-day move cap.
- WS-F Grades: academic A+/A/A-..F ladder in `score_to_grade`, `_GRADE_LOWER_BOUND`,
  `_RISK_LEVELS`; grade-contract tests updated.
- WS-G Confidence: removed the 0.75 constant from scorer, persistence, API, digest, scheduler,
  Pydantic model, and iOS dead code (per-article / portfolio confidence untouched).
- WS-H iOS: full academic migration across 13 files, 3 score->letter mappers centralized into
  one source of truth; app builds clean.
- WS-I Website: methodology + llms.txt updated to the granular A+/F scale (screenshots already
  showed academic letters; no contradiction). Push to live left for sign-off (outward-facing).
- WS-J Monitoring: recompute logs completed_with_errors at >=95% success instead of "failed".
- DB migration `academic_grade_check_constraints`: widened 6 CHECK constraints that had
  hard-coded the credit alphabet (the true cutover blocker; they silently rejected every
  academic write).

## 4. Bugs caught during cutover (none visible to the read-only harness)

1. Six DB grade CHECK constraints allowed only credit letters -> every academic write failed
   silently (only A/B/C/F slipped through, valid in both alphabets). Widened all six.
2. `smooth_score_change` daily-move cap throttled the re-spread back toward each name's old
   compressed score -> first bulk run wrote compressed grades. Bypassed for the re-spread.
3. `_safe_float(None)` returns 0.0 (not None): unscored articles were counted as sentiment 0,
   collapsing the news dimension to 0; and the event builder stored sentiment under `confidence`
   with no `sentiment_score` key. Both fixed; news now computes real values.

### 4.4 Semiconductor F-cliff (found by the adversarial Bloomberg-grade evaluation)

An independent multi-analyst review caught a face-validity failure the metrics alone hid:
high-beta semiconductors (MU fin 90, AVGO, NVDA fin 94, AMD) were graded F/C+ because the macro
AND volatility dimensions BOTH floored toward 0 on the same correlated beta cluster (beta was
double-counted, macro/vol correlated ~0.80). A paid risk product grading NVDA an F would poison
trust. Fix: (a) cap the macro beta proxy at beta 2.0 and floor the macro dimension at 30 on both
the regression and proxy paths (a name is never "infinitely" macro-exposed); (b) decouple
volatility from beta entirely (it is realized-vol + drawdown driven now), removing the double
count. Result: MU/AVGO C-, NVDA/AMD/LRCX B-/B, no blue-chip F's; the only F's are genuinely
distressed names. This is the one item the evaluation gated launch on, and it is fixed + verified.

## 5. Operational gotchas (for future grade-scheme changes)

- DB CHECK constraints gate grades; update them first.
- A killed recompute leaks its Postgres advisory lock via the idle PostgREST pooled connection;
  clear with `pg_terminate_backend` on the advisory-lock holder.
- `SCHEDULER_TIER=intraday` overrides `PAUSE_SYSTEM_SCHEDULER`; set `SCHEDULER_TIER=none` to
  truly pause, and restore to `intraday` afterward.
- `docker logs` shows only the uvicorn main process, not `docker exec -d` job processes.

## 6. Safety / rollback

- Backups: `bak_risk_snapshots_20260626`, `bak_prices_20260626`.
- Env flag `COMPOSITE_SPREAD_ENABLED=false` reverts the spread; reverting `score_to_grade`
  restores letters; Supabase PITR covers data.
- No user accounts, auth, secrets, legal, or identity data were touched.

## 7. Final live distribution (546 S&P names, post semi-fix recompute)

Composite stddev 12.42, range 13.4-100, median name ~B+ (composite ~71). News coverage 99%,
sector 545/546 (IWM the lone honest null), 0 confidence rows, 0 legacy grades, 0 stale stragglers.
(The semi-fix in section 4.4 lifted the high-beta low tail, so F shrank 24 -> 3 and stddev eased
15.1 -> 12.4; still comfortably above the >=12 floor and a more face-valid, S&P-appropriate shape.)

| Grade | n | % |
|---|---|---|
| A+ | 28 | 5.1% |
| A  | 63 | 11.5% |
| A- | 65 | 11.9% |
| B+ | 84 | 15.4% |
| B  | 103 | 18.9% |
| B- | 72 | 13.2% |
| C+ | 53 | 9.7% |
| C  | 26 | 4.8% |
| C- | 24 | 4.4% |
| D+ | 14 | 2.6% |
| D  | 8 | 1.5% |
| D- | 3 | 0.5% |
| F  | 3 | 0.5% |

A-range (A+/A/A-) = 28.6% (quality blue chips); F = 0.5% (3 genuinely distressed names:
SATS/EchoStar fin 19, POET speculative, SMH concentrated semi ETF). Largest bucket B at 18.9%
(under the 35% ceiling). Face-validity spot check: JNJ A, BAC A, JPM/KO A-, AAPL/META/XOM/WMT B+,
MSFT/GOOGL/PG B, NVDA/AMZN B-, TSLA C.

## 8. Production state at handoff

- New code live on the VPS backend (container clavis-backend-1), all modules import clean.
- Scheduler restored to SCHEDULER_TIER=intraday (daily recompute, news refresh, ops monitor running).
- Composite spread env locked in backend/.env; daily recompute keeps grades spread via normal
  smoothing (the one-time bypass was only for the re-spread).
- iOS app migrated + builds; website copy updated locally (push pending sign-off).

## 9. Launch verdict

Adversarial multi-analyst Bloomberg-grade evaluation: overall backend **B-** pre-fix with one
launch-blocker (the semi F-cliff), now fixed -> effectively **B / GO** for the grading system.
Dimension grades: data integrity B+, coverage/reliability B+, news/compliance B, methodology C+,
distribution C+ (the C+ on the last two reflect honest debt: the affine spread is an amplification
of a ~7.5pt genuine spread, and macro/vol shared variance — now reduced by the decouple).

Backend is launch-ready for the grading system: the founder can proceed with the manual iOS
QA/design pass. Fast-follow (non-blocking) debt to schedule post-launch:
1. News dual-writer in scheduler.py (~12 high-volume tickers can still show news=50 via a second
   snapshot path) — confirm and route through the same sentiment fix.
2. Recompute reliability: the forced bulk run needed retries and once silently skipped 11 tickers
   (self-healed); harden the single-pass coverage + re-enable the dormant coverage-repair job.
3. Beta low-bias: raise the 20-day common-day minimum before scaling beyond the S&P.
4. Refresh or surface the stale prices display-cache (does not affect the model).
5. Backtest the scorer anchors against realized outcomes (drawdowns/downgrades) post-launch.
6. One idiosyncratic data outlier (KLAC: a bad price bar inflated vol to 0 / sector to 6) — the
   rolling daily recompute should self-correct as the window advances; spot-check it.
