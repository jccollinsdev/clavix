# Dimension Data Enrichment: Rollout + Freshness Plan

Date: 2026-07-01. Status: implemented + tested on device (HOOD, AMD). Awaiting your review before the two production steps flagged below.

## What this covers

The three thin dimensions (Price Stability, Sector Resilience, Macro Resilience) now show far more real data. This document explains where each new data point comes from, how it reaches every ticker in the universe, and how it stays fresh, so you can approve the rollout.

Two guiding principles kept this safe:
1. Wherever possible, new data is computed at view time from the daily price history the app already fetches (`/prices/{ticker}`). That means it works for every ticker automatically and is always fresh, with no backend recompute and no deploy.
2. Nothing changes a score or a grade yet. Scores still come from the backend exactly as before. Everything added is display enrichment. Any change to scoring is called out separately below as a decision for you.

## What was added, and how it reaches all tickers

### Price Stability (all client-side, always fresh)
| New card | What it shows | Source | Works for all tickers? | Fresh? |
|---|---|---|---|---|
| Max Drawdown chart | Real price line, peak to trough highlighted, 15 days before / 30 after | `/prices/{ticker}` (365d) | Yes, any ticker with price history | Yes, recomputed each view |
| How Its Days Are Spread | Histogram of daily % moves + worst/best day | same | Yes | Yes |
| 52-Week Range | Low / current / high range bar | same | Yes | Yes |
| In Up vs Down Markets | Up-capture and down-capture vs the S&P 500 | `/prices/{ticker}` + `/prices/SPY` | Yes | Yes |

Because these compute in the app from the `prices` table, they are correct for every ticker the moment its daily price row updates. There is no per-ticker backend work and nothing to recompute.

### Sector Resilience (all client-side, always fresh)
| New card | What it shows | Source | All tickers? | Fresh? |
|---|---|---|---|---|
| How {ETF} Has Traded | 6-month sector-ETF price sparkline + 90d change | `/prices/{sector_etf}` | Yes, any ticker with a mapped sector ETF | Yes |
| {Ticker} vs Its Sector | 90-day relative strength + correlation to the sector | `/prices/{ticker}` + `/prices/{sector_etf}` | Yes | Yes |

The sector ETF comes from the methodology response (`sector_etf`), which every equity already has. Diversified ETFs (no single sector) simply skip these cards, same as today.

### Macro Resilience (uses data the backend already computes)
| New card | What it shows | Source | All tickers? | Fresh? |
|---|---|---|---|---|
| Today's Macro Backdrop | Live 10-yr Treasury, VIX, US dollar, HY credit spread | `current_factor_levels` in the snapshot (from FRED) | Yes, already stored for all tickers | Yes, refreshed every recompute; FRED cached 6h |
| What Drives Its Macro Exposure | Ranked factor importance using unit-comparable `contributions` | `contributions` in the snapshot | Yes, already stored for all tickers | Yes |

Important: the backdrop card is already live because `current_factor_levels` is already served. The ranked-contribution card is fully built but needs one additive API field to light up (see step 1). It reveals what was already being computed but hidden: the market is roughly 95% of HOOD's macro exposure, with rates and the dollar as small secondary drivers. Until it is deployed, the app gracefully falls back to the plain-language direction rows it already shows.

## The two production steps that need your go-ahead

### Step 1 (small, safe): deploy the additive macro API fields
I added three keys to the macro object of `/tickers/{ticker}/methodology`: `contributions`, `macro_daily_vol`, `top_factor`. These are already computed and stored for every ticker (in `dimension_inputs.macro_exposure`), so this is pure exposure with zero score impact and full backward compatibility. Deploying it lights up the ranked factor-importance card for the entire universe at once, with no recompute.

- Files: `backend/app/routes/methodology.py` (done), plus the matching iOS model field (done).
- Rollout: standard deploy (git push triggers the rsync + restart workflow). No data migration, no recompute.
- Risk: minimal. Old app versions ignore the new keys; the new app falls back if they are absent.

### Step 2 (optional, larger): promote high-value metrics into the backend and into scores
The client-side layer makes the dimensions feel rich today. If you also want these to influence the scores and be queryable server-side (for alerts, screening, the morning report), we promote the best ones into the recompute pipeline. This is the part that changes grades, so it is gated on your approval and should run on a Supabase branch first.

Highest-value promotions, from the vendor audit:
1. Persist full OHLCV in the `prices` table. Today the daily capture job fetches full bars from Polygon then throws away everything except the close. Storing open/high/low/volume (columns already free to add, data already on the wire) unlocks true 52-week high/low, average true range, and volume-spike detection with zero new API calls.
2. Fold downside deviation and up/down capture into the Price Stability score, so a name that only falls hard is scored worse than one that is merely bouncy.
3. Wire WTI crude into the macro regression. The series (`DCOILWTICO`) is already fetched from FRED and currently discarded; it matters a lot for energy, airlines, and transports. Adding 2 to 3 more FRED series (2-year yield, breakeven inflation, investment-grade spread) is nearly free since FRED is one cached fetch per cycle.
4. Fetch all 11 sector ETFs once per cycle (not per ticker) and cache, to rank each stock's sector against the other ten. That is 11 shared Polygon calls total, and it gives a real "your sector is leading / lagging" signal for the whole universe.

Each of 2 to 4 changes a score, so the rollout for those is: implement on a Supabase branch, recompute the universe there, diff the grade distribution, sanity-check the movers, then merge and recompute production. Item 1 (OHLCV persistence) is safe to ship first since it only adds columns.

## Freshness: how the data stays current for everyone

- Client-side enrichments (most of Price Stability and Sector): fresh by construction. They read the `prices` table at view time, so they reflect the latest daily close the moment the EOD capture job writes it. Nothing to schedule.
- `prices` table freshness: maintained by the existing daily EOD price capture job. If that job is healthy, the client-side layer is fresh for all 500+ tickers.
- Macro backdrop and contributions: refreshed on every ticker recompute; the FRED pull is shared and cached 6h, so a full-universe recompute hits FRED once, not 500 times. Backdrop values are market-wide, so they are identical across tickers on a given day (as expected).
- Recompute cadence: unchanged. The new stored fields (backdrop, contributions) ride along on the recompute you already run; they are already being written.

## Net effect

- Live today, no action: Price Stability (drawdown chart, distribution, 52-week range, up/down capture) and Sector Resilience (sector sparkline, relative strength, correlation) for every ticker, always fresh; Macro backdrop for every ticker.
- One safe deploy away: the ranked macro factor-importance card, universe-wide.
- Your call: promoting selected metrics into the scores (grade-affecting, branch-and-validate first) and persisting OHLCV to unlock the range/volume family.

Nothing here is committed to git yet. Say the word and I will commit the frontend + the additive backend API change, and separately prepare the Supabase-branch work for the score-affecting items.
