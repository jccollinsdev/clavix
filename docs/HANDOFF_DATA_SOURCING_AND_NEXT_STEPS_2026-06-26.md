# Clavix Data Sourcing + Next Steps: Engineering Handoff

Date: 2026-06-26
Status: research complete, decisions locked, NO code wired yet
Author: prior session (Claude). Read this cold and you can execute without the chat history.

This document captures three things:
1. All the data-provider research done this session (two multi-agent research sweeps, ~80 providers verified against their live pricing + terms pages).
2. The takeaways from the Bloomberg-grade accuracy audit.
3. The exact next steps, with the decisions the owner has already made.

Style note for whoever edits this: the owner dislikes em dashes. Use colons, periods, or parentheses instead.

---

## 0. TL;DR (decisions are LOCKED, do not relitigate)

- **News provider: use Tickertick NOW (free, clean license). Move to Stock News API Premium ($49.99/mo) LATER.** This is the owner's explicit choice. Do not wire up anything else.
- **Drop options implied volatility (IV) entirely.** The volatility dimension should be computed only from price-derived stats: realized volatility, beta to SPY, drawdown, plus vol-trend and downside deviation. IV was already dead in production (see Section 8), so this is mostly cleanup.
- **No analyst estimates.** The owner does not want them. Skip every "estimates" provider.
- **Summaries are fine for news.** Clavix feeds each article to an LLM that extracts implications and sentiment, so a headline + summary/snippet is fully sufficient. Full article body is NOT required. This is what makes a cheap/free news feed viable.
- **The real constraint is commercial LICENSING, not data availability.** Most cheap data tiers forbid commercial use or forbid serving "derived" outputs. Clavix is a paid app, so it must use feeds whose license actually permits this.
- **Current stack has a live compliance problem.** Finnhub free and Google News RSS are not licensed for a commercial product. Switching news to Tickertick fixes this at $0.
- **SEC EDGAR is a free, license-clean bonus** for fundamentals (statements) and for material-event "news" (8-K + press-release exhibits). Treat it as a secondary signal, not the primary news source.

---

## 1. Context

Clavix (a.k.a. Clavis in the repo) is a consumer-facing PAID iOS app that assigns risk grades (AAA to D, via a 0 to 100 safety score) to a FIXED universe of ~546 US large-cap equities (S&P 500-ish). The grade is a weighted blend of 5 dimensions:

1. financial_health
2. news_sentiment_dim
3. macro_exposure_dim
4. sector_exposure
5. volatility

Backend: Python/FastAPI, APScheduler (in-process intraday jobs) + crontab (daily/weekly), Docker Compose on a single 2 GB DigitalOcean droplet. Data in Supabase Postgres. See `docs/OPERATIONS.md` for the full ops runbook and topology.

Current data stack (all FREE tiers):
- Prices: Polygon free (EOD only, 5 calls/min, options return 403).
- Fundamentals + quotes: Finnhub free.
- News: Google News RSS + Finnhub company news.
- Macro: FRED (key-free, real, added this session).

The owner asked: "where else can we get free/cheapest data for intraday prices, options/IV, deep fundamentals, and full-text news?" Then refined: summaries are fine for news, drop IV, drop analyst estimates, and equities only (no crypto/forex/other asset classes ever).

---

## 2. The finding that governs everything: licensing is the wall

Across ~80 providers verified this session, the pattern is overwhelming: the data is cheap or free to obtain, but the **license** on the cheap/free tier almost always (a) restricts use to personal/non-commercial, and/or (b) forbids redistributing or displaying "derived" outputs to third parties. A risk score computed from someone's data, then shown to a paying user, is exactly the "derived output displayed to third parties" that these licenses forbid.

So provider selection is a LICENSE-first exercise, not a price-first one. A $0 tier that forbids commercial use is worth less than a $0 tier with a clean license, even if the former has richer data.

Corollary, important: **the current stack is already out of compliance.**
- Finnhub free is "strictly for personal use" and forbids sharing "derived results" with third parties without written approval. Clavix does exactly that.
- Google News RSS scraping is legally gray for a commercial product.
Switching news to Tickertick (clean license, free) removes this liability immediately.

---

## 3. Bloomberg-grade audit takeaways

Full audit: `docs/AUDITS/CLAVIX_BLOOMBERG_GRADE_AUDIT_2026-06-26.md`. One-line verdict from it: Clavix now tells the truth about a deliberately narrow slice of what Bloomberg covers, with a real macro signal instead of a fabricated one. Grades it assigned: roughly C+ on breadth, A- on honesty, B on depth.

What is REAL and good now (shipped this session, all live):
- **Macro is real.** Was a fabricated near-constant (R^2 ~ 0.02 from ETF proxies). Now a real regression on FRED factors (10Y, HY OAS, USD, VIX, SP500): 544/546 on real FRED data, mean R^2 ~ 0.194, 347 names scoring off a genuine regression.
- **Quality-weighted dimension averaging** broke the A-grade clustering (77% -> 39% A-grades; BBB is now the plurality).
- **Recompute** went from ~110 min to ~30 min (persisted-first prices + bounded concurrency + a grouped-daily price backfill of ~69,904 closes).
- **Deploy safety, alerting, OOM cap, dependency guard, monitors** all shipped.

The honest gaps the audit named (this is the to-do list that motivated the research):
- **Options / IV is fake or thin.** Free Polygon returns 403 on options, so there is no real IV. Decision: drop IV (Section 8).
- **News depth and relevance.** Headlines only, alphabetical coverage cliffs historically, limited per-ticker volume. Decision: switch provider (Section 6) + summaries-are-fine lens.
- **Fundamentals depth.** Free Finnhub is shallow and non-commercial. Decision: SEC EDGAR for statements (Section 5), no estimates.
- Breadth vs Bloomberg (546 US large-caps vs millions of global instruments across asset classes) is intentional and will not be chased. Equities only, forever.

The "to get to Bloomberg you must pay" reality, in priority order, was: real-time prices, then options/IV, then deep fundamentals + estimates, then licensed full-text news. The owner has since decided to drop IV and estimates, which removes two of those four cost centers.

---

## 4. The four original needs and where they landed

| Need | Decision | Source |
|---|---|---|
| Intraday/real-time prices | Keep EOD/price-data approach for now; migrate OFF non-commercial free tiers when budget allows | See Section 5 price options |
| Options + IV | DROP. Replace with price-derived volatility | Section 8 |
| Deep fundamentals: statements | SEC EDGAR XBRL (free, commercial-clean) when built | Section 5 |
| Deep fundamentals: analyst estimates | DROP. Owner does not want estimates | n/a |
| News (full body) | Reframed: summaries are fine. Use Tickertick now, Stock News API later | Section 6 |

---

## 5. Research Pass 1: general data-provider landscape

Method: 7 parallel research agents (per-need + aggregators + free/open + comparison threads), then adversarial verification of each provider's free-tier and commercial-license claims against their live pricing and terms pages, then a completeness critic. 40 unique providers.

### 5a. Prices (intraday / better-than-EOD)
- No source is both free AND commercial-legal. Alpaca free (200 req/min, IEX) and Finnhub free (60/min) are technically great but personal-use-only.
- Cheapest commercial-legal: **Marketstack Basic $9.99/mo** (delayed, commercial license included, but it is Tiingo data resold) or **Tiingo $50/mo** (IEX intraday, internal-commercial). Polygon/Massive self-serve $29 tier is non-commercial; their commercial plan is quote-only.
- Verdict: not urgent. Equities price data we already have is workable. When migrating off non-commercial free tiers, Marketstack $9.99 (EOD/delayed) or Tiingo $50 (IEX intraday) are the budget options.

### 5b. Options + IV
- **No good free OR cheap commercially-licensed answer exists.** Every free options-IV source is license-poisoned for a paid app (Polygon free/$29 = non-commercial; yfinance = scraping, ToS-forbidden; MarketData.app free/Trader = internal-use-only; Tradier needs a funded brokerage account; ThetaData personal $40 but COMMERCIAL is $400-1600/mo; Intrinio/ORATS commercial start $150-333/mo+).
- IMPORTANT correction baked in: you cannot compute IV from the underlying price alone. IV is backed out of actual option market prices, so it requires an options feed. From price data you can only compute REALIZED volatility, not implied.
- Verdict (owner decision): drop IV. Use realized vol + beta + drawdown + vol-trend + downside deviation. See Section 8.

### 5c. Fundamentals (statements)
- **SEC EDGAR XBRL company-facts API is the answer: free, official US government source, public-domain license (storing derived scores is unambiguously fine), 100% coverage of the 546 names.**
  - Endpoint: `https://data.sec.gov/api/xbrl/companyfacts/CIK{10-digit}.json` (all XBRL facts for one filer in one call). Also `companyconcept`, `frames`, `submissions`.
  - Rate limit: ~10 requests/sec per IP. A descriptive `User-Agent` header with a contact email is MANDATORY or you get IP-blocked.
  - History: ~2009-present (XBRL era).
  - The catch: it is RAW as-reported XBRL. You must build a normalization/mapping layer (tag drift, company-specific extension tags, restatements, fiscal-period contexts). This is real, ongoing engineering, but it is a one-time build for a fixed 546-name universe.
- Other option flagged for evaluation: **financialdatasets.ai** (AI-era API, 30+ yr normalized statements, has a free tier, low paid tiers). Verify commercial-license language before relying on it. NOTE from Pass 2: its news/redistribution rights are gated to a $2,000/mo Pro plan, so its cheap tiers are individual-license only. Likely same trap for fundamentals; verify.

### 5d. Analyst estimates
- DROPPED by owner. For the record: there is no free commercial source of consensus EPS/revenue. Cheapest were FMP Premium ($59, restricted license) or Finnhub estimates add-on (~$75 commercial-quoted) or Nasdaq Data Link Zacks/Sharadar. Do not build.

---

## 6. Research Pass 2: news APIs under the "summaries are fine" lens

Method: 4 parallel research angles (finance-native, general-cheap, sentiment-aggregators, comparison threads), then adversarial verification of each provider's commercial license on the cheapest tier + content fields + volume fit for 546 names, then a critic naming the single cheapest clean option. 28 unique providers.

Lens that changed the answer: because Clavix's LLM summarizes and derives sentiment itself, a provider that returns headline + summary/snippet (and ideally a ticker tag) is sufficient. Full body not required. This reopens the cheap finance-news tier that full-body licensing had ruled out.

### 6a. The verified shortlist

| Provider | Price | Content returned | License (verified) | Verdict |
|---|---|---|---|---|
| **Tickertick** | **$0** | headline + summary + ticker tags (NO sentiment field) | CLEAN: README grants "free of commercial/non-commercial use", no display/redistribution clause (MIT, no API key) | **CHOSEN: use now** |
| **Stock News API (Premium)** | **$49.99/mo** | headline + short extract + keyword sentiment + ticker tags (no full body, by design) | CLEAN-ISH: FAQ explicitly steers commercial apps to Premium/Business "for display purposes" | **CHOSEN: use later** |
| Marketaux (Basic) | ~$24-29/mo | snippet + per-entity sentiment + ticker + relevance score | UNCLEAR: ToS only grants personal/non-commercial; no separate API commercial grant published | Cheapest paid IF license confirmed in writing. Not chosen |
| Stockdata.org | ~$24-29/mo | sibling of Marketaux, same payload | UNCLEAR (same as Marketaux) | Backup to evaluate only if Marketaux path is taken |

### 6b. Verified NOT-clean or not-viable (do not be tempted)
- **Tiingo News ($50 "commercial")**: VERIFIED not clean for us. The tier is "internal use" which the ToS defines as "you may not display or share the data." Displaying derived outputs = redistribution = needs a custom deal. Scratch for news.
- **Alpha Vantage NEWS_SENTIMENT**: best precomputed per-ticker sentiment of the entire field, but NO commercial rights on any published plan (negotiated only). Unusable license despite great payload.
- **Finnhub company-news (current source)**: forbidden. Personal-use-only, forbids serving derived results. This is the live compliance liability.
- **NewsData.io free**: the "free tier has sentiment + finance ai_tag" claim was REFUTED. Those are paid-only ($199.99/mo). Free is weak ticker relevance. Backstop at best.
- **GNews / NewsAPI.org / Mediastack / TheNewsAPI / Currents / Webz.io Lite / worldnewsapi / Apitube**: either non-finance (no ticker tags), or forbidden on cheap tiers, or commercial only at $99-$449/mo, or license forbids storing derived/transformed data outright (worldnewsapi, Currents).
- **EODHD / Polygon-Massive / Benzinga / FMP / financialdatasets.ai**: rich payloads but commercial use is contact-sales-only or $2,000/mo-tier. Not self-serve clean under budget.
- **finlight.me**: sentiment gated to $99 tier, license vague. Not the $29 win it first appeared.
- **Adanos ($299/mo)**: clean license but it is a sentiment-aggregate feed, not headline+summary, and 4x budget.

### 6c. Why Tickertick wins now
- Only provider whose license is clean in plain English for a commercial app.
- Returns exactly what the pipeline needs (ticker-tagged headline + summary); lack of a sentiment field is irrelevant because the LLM derives sentiment.
- Free, so it fits a ~$68/mo total budget with zero marginal cost.
- Fixes the current compliance problem at $0.
- The one real catch is OPERATIONAL, not legal: it is a single-maintainer hobby project, rate-limited to ~10 req/min (and a 30-second IP ban if more than ~5 requests hit in any 30-second window), with no SLA. A full 546-name daily sweep is ~55 to 110 minutes at safe pacing. Acceptable for a once-daily refresh. Mitigate with conservative pacing and graceful failure (fall back to last-known articles; never hard-fail the recompute on a news miss).

### 6d. Tickertick API specifics (for the integration build)
- Base: `https://api.tickertick.com/feed?q=<query>&n=<count>` (no API key).
- Query language: `tt:TICKER` (stories from/about a ticker), `z:TICKER` (broader), boolean `and/or/diff`, `T:curated` etc. For Clavix, per-ticker pull is `q=(and tt:AAPL T:curated)` style or simply `tt:aapl`.
- Returns up to `n=200` stories. Fields per story: `id`, `title` (headline), `url`, `site` (source domain), `time` (ms epoch), `favicon_url`, `tags` (ticker array), `tickers`, and an optional `description` (the summary).
- Rate limit: ~10 req/min; keep under ~5 requests / 30 seconds to avoid the temporary IP ban. Pace accordingly.

---

## 7. Decisions locked in (restate, so nobody re-opens them)

1. News = Tickertick now, Stock News API Premium ($49.99/mo) later. Nothing else.
2. Summaries are sufficient; do not chase full article bodies.
3. Drop options IV from the volatility dimension.
4. Drop analyst estimates entirely.
5. Equities only, US large-cap universe (~546). No crypto/forex/other asset classes, ever.
6. SEC EDGAR (statements + 8-K events) is a free, license-clean enhancement to build when convenient; secondary to the news API.
7. Keep total data spend near the current ~$68/mo until ~15 Pro subscribers justify more.

---

## 8. Volatility dimension: what IV was doing (nothing) and the cleanup

Findings from reading the code (verified this session):

- The volatility score is computed by `_score_volatility` in `backend/app/pipeline/risk_scorer.py` (~line 837). It reads ONLY three price-derived inputs: `realized_vol_30d`, `beta_to_spy`, `max_drawdown_252d`.
- The IV fetch lives in `backend/app/services/polygon_options.py` (`fetch_near_term_implied_vol_30d`, line 82). On the free Polygon tier it returns 403 on every ticker, trips a process-level circuit breaker, and returns `None` permanently. So `implied_vol_30d` is always null in production.
- When IV is null, `_build_volatility_inputs` in `backend/app/services/ticker_cache_service.py` (~line 771-819) falls back to `estimate_iv_rank_from_realized_vol` (`backend/app/pipeline/structural_scorer.py` line 142), which is just a 30d/90d realized-vol ratio wearing an "IV rank" label (explicitly marked `iv_source="estimated"`).
- CRUCIAL: that `iv_rank` / `implied_vol_30d` is stored in `volatility_inputs` and surfaced on the methodology / "show your work" screen (`backend/app/routes/methodology.py` ~lines 226-395), but it does NOT feed the grade. It is decorative.

So the volatility grade is ALREADY realized-vol + beta + drawdown. Dropping IV is mostly removing dead, misleading plumbing.

Cleanup plan (NOT YET DONE; owner deferred it into this handoff):
1. In `_build_volatility_inputs` (`ticker_cache_service.py` ~line 792): remove the `fetch_near_term_implied_vol_30d(ticker)` call and stop populating `implied_vol_30d`, `iv_rank`, `iv_source`. This also kills 546 doomed Polygon options requests per recompute. Remove the now-unused imports (`fetch_near_term_implied_vol_30d`, `estimate_iv_rank_from_realized_vol`).
2. In `backend/app/routes/methodology.py` (~lines 226-395): remove `iv_rank` / `implied_vol_30d` from the response and the methodology display, or replace the "IV rank" line with the honest `vol_ratio` (30d/90d) which is already computed.
3. (Score upgrade, OPTIONAL but recommended) In `_score_volatility`: fold in the `vol_ratio` (30d/90d realized vol, the closest free stand-in for the forward-looking signal IV was meant to give: when short-term vol runs hot vs its medium-term baseline, the regime is destabilizing) and add a downside-deviation term (volatility of only negative returns) so upside volatility is not punished like downside. NOTE: this changes computed grades, so it requires a universe recompute and a before/after distribution check.
4. Consider deleting `backend/app/services/polygon_options.py` entirely once nothing imports it. Keep `estimate_iv_rank_from_realized_vol` only if the methodology route still wants the ratio; otherwise delete.
5. Update/extend the regression smoke-suite (`backend/tests/test_p9_remediation_regressions.py`) so the "volatility is price-derived only, no IV" invariant is pinned.
6. After deploy, run a full universe recompute (see `docs/OPERATIONS.md`) and confirm the grade distribution did not collapse or spike.

Tunables already in the scorer for reference: base 78.0; realized_vol penalty `(rv30 - 0.20) * 60`; beta penalty `min(18, (|beta|-1)*10)`; drawdown `max_drawdown * 30`. Calibration anchors in comments: SPY rv30 ~ 0.12 -> ~84; TSLA rv30 ~ 0.80 -> ~42.

---

## 9. Implementation plan / next steps (ordered)

Priority order reflects: fix compliance first, then quality, then nice-to-haves.

### Step 1: Wire Tickertick as the news source (HIGH, fixes compliance + quality)
- Current news ingestion architecture:
  - `backend/app/pipeline/rss_ingest.py` (Google News RSS) and `backend/app/pipeline/finnhub_news.py` (Finnhub company news) are the current sources.
  - `backend/app/services/google_news_decoder.py` decodes Google News wrapper URLs.
  - `backend/app/pipeline/relevance.py` + `backend/app/services/candidate_ranker.py` filter/rank.
  - `backend/app/services/news_feed_service.py` / `news_enrichment.py` handle storage/enrichment.
  - Orchestrator: `_run_active_ticker_news_refresh` in `backend/app/pipeline/scheduler.py` (~line 5598), an in-process APScheduler job ("active_ticker_news_refresh", 4h cadence) with a persistent rotation cursor (`NEWS_ROTATION_CURSOR_KEY`, ~line 5564). `NEWS_REFRESH_BATCH_SIZE` env (default 150).
- Build: a new `backend/app/services/tickertick.py` client (per Section 6d), then a `backend/app/pipeline/tickertick_ingest.py` that mirrors the shape of `rss_ingest.py` / `finnhub_news.py` and returns article candidates for the existing relevance + storage pipeline.
- Swap: route `_run_active_ticker_news_refresh` to source from Tickertick. Keep an env kill-switch (mirror `DISABLE_NEWS_ENRICHMENT`) so you can fall back. Decommission the Google News RSS + Finnhub-news sources once Tickertick is verified (this is what removes the compliance liability).
- Respect the rate limit: pace to <= ~5 requests / 30s; the once-daily 546-name sweep is fine. Never hard-fail the recompute on a news miss; fall back to last-known articles.
- Verify: confirm per-ticker article counts recover, then run a universe recompute and confirm the news dimension is populated for the universe.

### Step 2: Volatility cleanup (HIGH, all internal code)
- Execute Section 8. Pure code, no new service. Recompute + distribution check after.

### Step 3: SEC EDGAR fundamentals normalizer (MEDIUM, free quality + compliance upgrade)
- Build a client + XBRL normalization layer (Section 5c). Replaces the shaky Finnhub-free fundamentals dependency with as-reported, license-clean, primary-source data. Real engineering; one-time for the fixed universe.

### Step 4: SEC EDGAR 8-K + press-release exhibits as an event signal (MEDIUM, free)
- Full-text search API (`efts.sec.gov`) + filing archive gives complete body text of 8-Ks and EX-99.1 press releases for every covered name, free and commercially clean. High signal for risk grading (material events: earnings, guidance, executive changes, debt, litigation). Complements the media-news feed; does not replace it.

### Step 5: Stock News API Premium ($49.99/mo) (LATER, when budget/quality justifies)
- Drop-in upgrade from Tickertick for native sentiment, throughput, and an SLA. Use the Premium tier (NOT the $19.99 Basic, which is positioned non-commercial). Same ingestion seam built in Step 1.

### Step 6: Migrate prices off non-commercial free tiers (LATER, when budget allows)
- Marketstack Basic $9.99 (delayed) or Tiingo $50 (IEX intraday). Only needed to fully clear the Polygon-free / Finnhub-free personal-use exposure on prices.

---

## 10. Data-spend ladder tied to revenue

- Now (free, code-only, also fixes compliance): Tickertick news ($0) + SEC EDGAR fundamentals/events ($0). Keep total near current ~$68/mo.
- First paid step (small): Stock News API Premium $49.99/mo for native sentiment + SLA, when news quality becomes a priority.
- At ~15 Pro subscribers: optionally add commercial-clean prices (Marketstack $9.99 or Tiingo $50).
- At meaningful revenue (only if the product ever needs it): real options IV would be ~$199/mo (Polygon/Massive Options Advanced, commercial). Currently OUT of scope per owner decision to drop IV.
- Estimates: OUT of scope (owner decision).

---

## 11. Operational constraints + gotchas a cold agent MUST know

(Full detail in `docs/OPERATIONS.md`. Highlights:)
- VPS: `sansar@134.122.114.241`, key `~/.ssh/id_ed25519`, container `clavis-backend-1`. Code is volume-mounted, so `docker exec ... python -m app.jobs.run <job>` runs the deployed on-disk code.
- The running backend == this repo. Push to `main` triggers `.github/workflows/deploy-prod.yml` (rsync + `docker compose up -d --build` + health gate + auto-rollback). Pushing is safe.
- 2 GB host: container capped at `mem_limit 1500m`. Run only ONE heavy `docker exec` job at a time or you OOM-kill children.
- NEVER commit `backend/.env` or secrets (gitignored + deploy-excluded).
- Do NOT commit the unrelated uncommitted iOS files (`ios/Clavis/ViewModels/OnboardingViewModel.swift`, `OnboardingContainerView.swift`) or unrelated untracked files when committing backend work.
- Owner dislikes em dashes in copy/docs. Use colons/periods/parentheses.
- Provider gotchas already learned: FRED tarpits any custom User-Agent (use default requests UA). Docker bridge MTU pinned to 1400. Polygon single 403 trips a shared 5-min auth cooldown (grouped-daily bypasses it). Advisory locks can leak over the Supabase pooler.
- SEC EDGAR REQUIRES a descriptive User-Agent with a contact email, or it IP-blocks you. (Different from FRED, which rejects custom UAs. Do not confuse the two.)

---

## 12. Appendix: pointers

- Bloomberg-grade audit: `docs/AUDITS/CLAVIX_BLOOMBERG_GRADE_AUDIT_2026-06-26.md`
- Backend action plan that preceded it: `docs/AUDITS/CLAVIX_BACKEND_ACTION_PLAN_2026-06-25.md`
- Ops runbook: `docs/OPERATIONS.md`
- Roadmap: `docs/ROADMAP_TO_LAUNCH.md`
- Raw research outputs from this session (may be ephemeral, in `/tmp`): two Workflow runs, "free-market-data-research" (40 providers) and "news-summary-api-research" (28 providers), each with per-provider verification of license + pricing against live pages. The material tables are reproduced above in Sections 5 and 6, so this doc is self-contained.

Key code files for the work ahead:
- Volatility: `backend/app/pipeline/risk_scorer.py` (`_score_volatility` ~837), `backend/app/services/ticker_cache_service.py` (`_build_volatility_inputs` ~771), `backend/app/services/polygon_options.py`, `backend/app/pipeline/structural_scorer.py` (`estimate_iv_rank_from_realized_vol` ~142), `backend/app/routes/methodology.py` (~226-395).
- News: `backend/app/pipeline/rss_ingest.py`, `backend/app/pipeline/finnhub_news.py`, `backend/app/pipeline/relevance.py`, `backend/app/services/candidate_ranker.py`, `backend/app/services/news_feed_service.py`, `backend/app/services/news_enrichment.py`, `backend/app/pipeline/scheduler.py` (`_run_active_ticker_news_refresh` ~5598).
- Tests: `backend/tests/test_p9_remediation_regressions.py`.
