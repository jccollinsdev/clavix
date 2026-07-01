# Clavix Deep Pre-Launch Audit + Fixes — 2026-06-30 (overnight session)

Autonomous session. Scope: (1) verify no degradation in morning digests, ticker
info, and 5-dimension analysis across the whole universe; (2) fix ticker-detail
data + UX issues; (3) redesign the news-sentiment screen and the 5-dimension
views; (4) full regression sweep; (5) leave the backend launch-ready.

Live DB: Supabase `uwvwulhkxtzabykelvam` (clavis). Backend: VPS
`sansar@134.122.114.241`, container `clavis-backend-1`, deploy via push to `main`
(GitHub Actions rsync). Jobs: `docker exec clavis-backend-1 python -m app.jobs.run <job>`.

## Where I left off (git archaeology)
- Last commits (2026-06-27/28): morning-digest overhaul (real macro/sector/event
  data + LLM per-item), methodology redesign, holdings composition donuts, nav
  unification. Tree clean; VPS release `4238699d2` (last commit `4d917a463` is
  iOS-only, so backend is in sync).

## BACKEND HEALTH SWEEP — findings

### Healthy (no degradation)
- **5 dimensions**: 547/547 active tickers have a snapshot; 546 fresh ≤1d, 547 ≤3d.
  `composite_score`, `grade`, `macro_exposure_dim`, `volatility` never null.
- **Morning digests**: newest today (11:07 UTC), non-empty, generating per user.
- **Jobs**: all completing. My first sweep looked "all failed" only because jobs
  write `status='completed'` (not `'success'`). Real signals below.
- **Ops monitor works**: `daily_ops_monitor` correctly flags the enrichment gap
  ("only 63% of last-7d articles are 'complete', target ≥85%").

### Real issues found
1. **Incomplete articles served to users.** Of 24.6k `shared_ticker_events`, ~23%
   lack key_implications, ~31% lack risk_direction, ~32% lack sentiment_score.
   These are `analysis_status in (incomplete|partial|headline_only)` — extraction
   failed (paywall/navigation) or enrichment didn't finish. Serving layer does NOT
   filter them, so the app shows empty brief/risk/implications.
   → `analysis_status='complete'` == "has brief + risk signal + key implications".
   Every ticker has ≥1 complete article (544 have ≥3). **Fix: serve only complete.**
2. **News dimension NULL for ~28 real stocks** (COST, V, MA, CRM, CSCO, HD, …).
   Root cause: `ticker_cache_service.py:4728` truncates the news-scoring set to the
   **10 most-recent relevant articles** before scoring. When those newest 10 are
   freshly-ingested-but-not-yet-enriched (enrichment lags the 10:00 UTC recompute),
   `scored_count=0` even though 13–15 enriched articles exist just below the cutoff;
   the sticky snapshot then never re-scores. **Fix: widen scoring set; recompute.**
   (Null `financial_health` on bond/commodity ETFs — AGG/BND/TLT/GLD — is by design.)
3. **Conflicting driver cards.** `position_report_builder._build_driver_cards`
   groups by `(theme, direction)`, so `(regulatory_risk, positive)` and
   `(regulatory_risk, negative)` become two cards — "overhang clearing" AND
   "overhang strengthening" both show. **Fix: at most one card per theme (strongest).**
4. **Generic driver copy.** Static template fallback ("Regulatory clarity or
   approvals are removing a key overhang") isn't specific. **Fix: prefer concrete
   evidence text before the static fallback.**
5. **Recompute severity false alarm.** When almost all tickers are skipped-as-fresh
   and a single transient ticker error occurs (`processed==0, failed==1`), the whole
   547-ticker run is marked `failed` and pages. **Fix: don't fail a run that did no
   real work beyond a transient error.**

## ⚠️ BIGGEST FIND — universe-wide stale-data read bug (BE0)
`_VALID_GRADES` in `ticker_cache_service.py` was still the pre-migration bond
vocabulary `{AAA,AA,A,BBB,BB,B,CCC,CC,C,F}` — no `A+/A-/B+/B-/C+/C-/D+/D-`. Since the
2026-06-27 academic-grade migration the scorer emits those modifier grades, so
`snapshot_is_schema_complete()` returned **False** for every modifier-graded snapshot.
The read path (`_canonical_snapshot_sort_key`) ranks schema-complete snapshots first,
so for any ticker whose current grade has a +/- modifier it **silently served an older
bond-graded snapshot** — stale grade AND stale 5 dimensions AND stale news.
- **Blast radius: 329/547 tickers (60.1%)** were being served a stale snapshot.
- Example: COST's API returned the 06-30 row (grade B, news NULL, composite 85.9)
  instead of the fresh 07-01 row (B+, news 58, composite 79.9); CSCO returned a
  bond-vocab "BBB" from weeks earlier.
- Fix: expand `_VALID_GRADES` to the academic ladder (legacy bond kept for old rows).
  No data change needed — the fresh rows already exist and are now preferred. Verified
  the digest/alert grade→rank maps (notifier/portfolio_compiler/digest_inputs) are
  already academic-aware, so this was the only serving-path vocabulary gap.

This was found only because the live-API smoke test disagreed with the DB.

## FIXES APPLIED — BACKEND

**BE1. Hide incomplete articles everywhere they're served.**
- New shared gate `article_has_full_enrichment(row)` in `analysis_utils.py`: an
  article shows only if it has a brief (`tldr`/`what_it_means`) AND a risk-signal
  score (`sentiment_score`) AND ≥1 key implication. Field-based (robust to status drift).
- Applied in: `routes/methodology.py` (`display_articles`, recent-first with
  14d/all-window fallback so tickers with a thin week still show real articles);
  `services/news_feed_service.py` (Today news feed); `services/ticker_cache_service.py`
  (`_news_rows_to_response` recent-news + `_get_shared_ticker_events` now fetches a
  wider set and prefers complete rows). Aggregate stats (histogram/distribution) left
  on the full window — only the article *lists* are gated.

**BE2. Fix NULL news dimension for ~28 real stocks.**
- `ticker_cache_service.py` was truncating the news-scoring set to the 10
  most-recent relevant articles *before* scoring; freshly-ingested-but-unenriched
  newest rows drove `scored_count=0`. Now fetches 80, scores the top 60 relevant
  (recency-weighted, 28d window applied in the builder), keeps the event/driver
  surface at the newest 10. A force recompute repopulates the sticky NULLs.

**BE3. No more self-contradicting driver cards.**
- `position_report_builder._build_driver_cards` now keeps at most one card per
  theme (strongest wins, list is pre-ranked), so "overhang clearing" and "overhang
  strengthening" can't both appear.

**BE4. Specific driver copy.**
- `_select_summary_text` and `_candidate_from_news` now prefer the LLM-written
  `what_it_means`/`tldr` over the raw source summary, so driver cards quote a
  concrete, grounded implication instead of falling back to the generic template.

**BE5. Recompute severity false alarm.**
- `composite_recompute` no longer marks a whole 547-ticker run `failed` when it was
  mostly skipped-as-fresh and a single ticker hit a transient reset (rates failures
  against the whole examined set, incl. skipped). Alerting was already rate-limited.

**Tests**: new `tests/test_article_display_gate_2026_06_30.py` (8 cases) green. Full
suite: 512 passed / 28 failed, and the 28 are **pre-existing stale bond-grade-vocab
assertions** (identical with my changes stashed) from the 2026-06-27 academic-grade
migration — not runtime bugs (live DB has zero null grades). Flagged for separate cleanup.

**Deploy + data fix**: two commits deployed to VPS (releases `984698328`, `e42088c79`,
both health-gated green). Validated the news-dim fix on V/MA/COST/CSCO/AIG/BX/HD/DIS
(all NULL→scored, column == weighted_score). Kicked off a full-universe force recompute
so every ticker picks up the improved logic; smoothing + grade hysteresis keep
day-over-day stability.

## FIXES APPLIED — FRONTEND (iOS ticker detail)

**FE1. News Sentiment screen — full redesign** (`NewsSentimentAuditView.swift`).
- Removed the confusing "Weighting" card ("last 24h = 3x…"), the per-article "3.0x
  weight" multiplier, and the "Score Calculation / weighted average" card.
- Added a **sentiment-mix donut** (bullish/neutral/bearish) with a legend, matching
  the holdings composition ring, plus a plain one-line read ("Coverage leans positive").
- Added a **score-distribution histogram** (0–20…80–100 buckets, colored by band).
- Clean article cards: title, `source · 2h ago` (never a raw ISO timestamp), brief,
  and a colored sentiment chip (score + BULLISH/NEUTRAL/BEARISH). Only articles with a
  real sentiment score are shown (belt-and-suspenders with the backend filter), so the
  risk-signal score always renders.
- Replaced jargon "How scoring works" with a plain "How to read this".

**FE2. Five-dimension audit views de-jargoned.**
- Macro (`MacroExposureAuditView.swift`): replaced the raw regression table
  (`TNX 2.6451`, `R² 0.220 · days 252`) with a "What moves this stock" section —
  human factor names (10-Year Treasury, US Dollar, Crude oil, VIX, S&P 500), a
  plain direction phrase, a HIGH/MODERATE/LOW strength chip, and a signed magnitude bar.
- Volatility: humanized labels ("Swings, last month", "Worst drop, past year",
  "Market sensitivity") with explanatory captions + a plain summary line.
- Sector: humanized ("Sector sensitivity/momentum/breadth" with captions + a
  tailwind/headwind read), and removed a user-facing dev placeholder
  ("Sparklines will appear once historical sector metric series are returned").

**FE3. Holdings / Watchlist actions moved to the top nav.**
- Removed the two full-width bottom CTAs; added compact icon buttons (＋ / ✓ for
  holdings, ☆ / ★ for watchlist) in the top-right of the ticker header, the
  "in the corner with symbols" pattern the user asked for.

**FE4. Conflicting / generic key drivers** are fixed at the backend (BE3/BE4); the
existing `TickerDriverCardsSection` renders the corrected, de-conflicted, specific cards.

**Build**: `xcodebuild` for the Clavis scheme (iPhone 17 Pro sim) compiles clean.

## REGRESSION SWEEP — final state

- **5 dimensions**: 547/547 fresh; after the force recompute, null news dimension
  dropped from ~28 real stocks to only genuinely-thin names (correct limited-data).
  composite / grade / macro / volatility never null.
- **Morning digests**: both users have today's + yesterday's digest, all 7 structured
  sections populated, 2.5–3.8k chars. Serving-layer changes don't touch digest
  generation (`digest_inputs` reads `shared_ticker_events` directly) — no regression.
- **News/ticker info**: only fully-enriched articles (brief + risk-signal score + key
  implications) are served across the methodology audit, Today feed, and ticker detail.
- **Jobs**: all completing (`status='completed'`); ops monitor working; recompute
  severity labelling corrected.
- **Tests**: backend 520 passed / 28 pre-existing stale-vocab failures (zero new
  regressions; flagged as a follow-up task). iOS build clean.

## KNOWN / DEFERRED (not launch blockers)
- 28 stale bond-grade-vocab tests (spawned as a follow-up task). Runtime is correct.
- News enrichment completeness ~63% of last-7d articles (ops-monitor target 85%). The
  gap is largely structural (paywalled / navigation-only extraction can't be enriched);
  hidden from users now, and the hourly bulk-enrichment job keeps improving the fixable
  ones. Not a data-integrity issue — just coverage depth.


</content>
</invoke>
