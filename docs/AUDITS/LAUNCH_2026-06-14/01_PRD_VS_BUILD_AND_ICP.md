# Report 1: PRD vs Build, and ICP Fit (2026-06-14)

Source of truth: `docs/CLAVIX_TRUTH.md` v2.1 and `docs/CLAVIX_LAUNCH_SCOPE_v1.md`.

---

## 1. Feature parity against the spec

Status legend: built and working, partial or unverified, missing or broken.

| Spec area (CLAVIX_TRUTH section) | Promise | Build state | Notes |
|---|---|---|---|
| Daily digest (§9) | Personalized morning briefing, macro to sector to position | Built and generating (3 today) | Verbose vs standard is a Pro gate; see monetization |
| Five risk dimensions (§6) | Financial Health, News Sentiment, Macro, Sector, Volatility, all scored | Built, but unstable | Values swing day to day; stored in `*_dim` columns, see report 2 |
| Composite and grade (§7) | 0 to 100 to bond-rating grade, with hysteresis | Built, hysteresis not holding | Grades flicker across boundaries day to day |
| Methodology drill-down (§8) | Tap any score to see formula, inputs, sources | Built | `TickerDetailView`, dimension audit views, article detail sheet all present |
| Ticker universe (§5) | S&P 500 plus qualifying mid and large caps plus top 50 ETFs | Partial | About 507 stocks scored; ETFs almost entirely missing |
| Search and ticker detail (§12) | Search, detail, outside-universe add | Built; radar screener is the new hero | `/tickers/screen` deployed and auth-gated |
| Watchlist (§13) | Add and track tickers | Built | Free cap of 5 in current build; changes under trial-only model |
| Score history (§14) | Rolling 90-day history, no fabricated deltas | Built | `ScoreHistoryChart` present |
| Alerts (§15) | Grade and dimension change alerts | Built in-app, never delivered | 0 push tokens, 0 delivered; see report 6 |
| Portfolio mechanics (§11) | Manual entry, position-weighted rollup | Built | Rollup fails intermittently for the AMD position |
| Tier split (§16) | Free vs Pro | Built as freemium; you want trial-only | Needs rework, see report 5 |
| Brokerage sync | Deferred to post-v1 | Correctly off (`FeatureFlags.brokerageEnabled = false`) | But the app still makes brokerage network calls, see report 4 |

**Headline:** the feature surface is essentially complete and matches the spec. The gaps are not missing screens, they are data quality (dimension stability, ETF coverage) and the tier model. That is a good place to be this close to a beta.

---

## 2. The ICP, and whether the current app satisfies it

The ICP (truth doc §3): a 45 to 65 year old self-directed investor with $500K to $5M, wealth-preservation minded, holds individual stocks and ETFs and occasionally bonds, reads 10-Ks, currently stitches together Bloomberg, Seeking Alpha, Yahoo, and CNBC every morning. The job to be done is to answer "did anything in my book get materially worse overnight" in about a minute, with the math shown.

### Where the build satisfies the ICP
- **The core loop matches the JTBD.** A single morning briefing plus a per-position grade plus a transparent drill-down is exactly the "Bloomberg compressed into a morning memo" promise. This is the right product for this person.
- **Transparency is present.** The methodology drill-down (formula, inputs, source dates, the article list with per-article scoring) is the moat the spec describes, and it is built. This is what differentiates Clavix from a black-box fintech score, and it is the thing this specific persona will test hardest.
- **Tone and framing are correct.** Bond-rating grades, no buy/sell language, informational not advisory. This matches a credit-rating-agency voice that a sophisticated investor respects.

### Where the build will disappoint the ICP (in priority order)
1. **Grade flicker destroys trust faster for this persona than any missing feature.** The truth doc says it plainly: "if a sophisticated investor can't explain why a position is rated B-, they don't trust the rating." A user who opens the app daily (the entire point of the product) will see AAPL go A, then BBB, then BBB, then A, then A, with financial health bouncing 62, 80, 88, 62. A 10-K reader knows Apple's balance sheet did not change three times in a week. The first time they see that, the moat becomes a liability. This is the number one ICP risk and it is a data problem, not a UI problem. See report 2.
2. **ETFs are missing.** This persona holds broad-market and sector ETFs as a core sleeve (QQQ, VTI, the sector SPDRs, AGG or BND for fixed income, SCHD for dividends). Right now only SPY and VOO have any data and it is stale. If the tester adds QQQ or AGG, they get no risk data, which reads as "this product does not actually cover my portfolio." The spec promises the top 50 ETFs. Closing this gap is high leverage for ICP fit.
3. **Manual entry is real friction for a large portfolio.** Brokerage sync is correctly deferred, but the consequence is that a $1M-plus, 20-to-40-position book has to be typed in by hand on a phone. For this ICP that is a meaningful onboarding cost. The daily-briefing value may justify it, but a CSV or paste import would sharply reduce first-session abandonment. Worth a fast-follow even though full brokerage sync stays deferred.
4. **Score-column incoherence.** If any screen shows `safety_score` (say 83) next to a "B" grade derived from `composite_score` (48), this persona notices immediately. See report 2.

### ICP gaps that are acceptable for v1
- Bonds and treasuries as first-class holdings (spec defers; ICP only "occasionally" holds them).
- International and crypto (deferred to v1.5).
- Brokerage auto-sync (deferred, with the CSV-import caveat above).

### Net ICP verdict
The product is aimed at exactly the right person and the shape of it fits their job. The risk is not that it does too little, it is that the data is not yet stable and complete enough to earn the trust this specific, skeptical, daily-checking persona requires. Fix grade stability and ETF coverage and the ICP fit goes from "promising demo" to "this respects how I think about risk," which is the line the truth doc draws.

---

## 3. Recommended ICP-driven priorities before the beta
- Stabilize grades and dimensions (report 2). This is the single biggest ICP-trust lever.
- Backfill the top ETFs into the universe so common portfolios are covered.
- Make sure every score surface reads one canonical score column.
- Consider a paste-or-CSV import as a fast-follow to reduce manual-entry friction for large books.
