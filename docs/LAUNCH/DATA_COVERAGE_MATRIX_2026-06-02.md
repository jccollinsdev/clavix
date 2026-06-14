# Data Coverage Matrix — 2026-06-02

Live production data as of ~11:00 UTC. Daily recompute still in progress (~176/534 done).

---

## Universe & Snapshots

| Metric | Value | Status |
|---|---|---|
| Total tickers in universe | 534 active | ✅ |
| Today's snapshots generated | 176 (mid-recompute; full run ~534) | ⚠️ In progress |
| Historical snapshot dates | 49 days | ✅ |
| Total unique tickers ever scored | 507 | ✅ |

---

## Today's Dimension Coverage (176 snapshots generated so far)

| Dimension | Column | Count with data | % | Status |
|---|---|---|---|---|
| Composite score | `composite_score` | 176/176 | 100% | ✅ |
| Grade | `grade` | 176/176 | 100% | ✅ |
| Financial Health | `financial_health` | 176/176 | 100% | ✅ |
| News Sentiment | `news_sentiment_dim` | 54/176 | 30.7% | ⚠️ Mid-run, expected ~80%+ by EOD |
| Macro Exposure | `macro_exposure_dim` | 165/176 | 93.8% | ✅ |
| Sector Exposure | `sector_exposure` | 176/176 | 100% | ✅ |
| Volatility | `volatility` | 175/176 | 99.4% | ✅ |
| Data status field | `data_status` | 0/176 | 0% | ❌ Never populated |

**Note:** `news_sentiment` and `macro_exposure` (legacy column names with no `_dim` suffix) are essentially empty for today's run — these are old columns; the active ones are `news_sentiment_dim` and `macro_exposure_dim`.

---

## Grade Distribution (today's 176 recomputed tickers)

| Grade | Count | % | Status |
|---|---|---|---|
| AAA | 0 | 0% | Acceptable |
| AA | 4 | 2.6% | ✅ |
| A | 76 | 49.7% | ✅ Healthy |
| BBB | 62 | 40.5% | ✅ Healthy |
| BB | 6 | 3.9% | ✅ |
| B | 4 | 2.6% | ✅ |
| CCC | 1 | 0.7% | ✅ |
| CC/C/F | 0 | 0% | Acceptable |

**Verdict:** Grade distribution looks realistic post-calibration fix. Ceiling is AA (not AAA), consistent with the "no AAA at launch" note in CLAUDE.md.

---

## Digests

| Metric | Value | Status |
|---|---|---|
| Total digests ever | 186 | |
| Unique users with at least one digest | 5 | |
| Digests in last 24h | 6 | ✅ |
| Digests in last 48h | 7 | ✅ |
| Most recent digest | 2026-06-01 20:10 UTC | ✅ Yesterday |
| Users with failing digest jobs (2026-06-01) | 2 of 4 | ❌ BLOCKER |
| Failure error | `"sequence item 0: expected str instance, NoneType found"` | ❌ Code bug |

---

## Alerts

| Metric | Value | Status |
|---|---|---|
| Total alerts ever | 16,823 | ✅ Active |
| Alerts in last 24h | 32 | ✅ |
| Alerts in last 48h | 41 | ✅ |
| Most recent alert | 2026-06-01 20:09 UTC | ✅ Yesterday |
| Unique users with alerts | 5 | ✅ |
| Distinct alert types | 6 | ✅ |
| Push notifications delivered | 0 | ❌ APNs non-functional |

---

## Positions / Holdings

| Metric | Value | Status |
|---|---|---|
| Total positions across all users | 514 | |
| Total users with positions | 5 | |
| Outside-universe positions | 0 | |
| In-universe positions | 514 | ✅ 100% |

---

## Users / Subscriptions

| Tier | Users | Has Trial Data |
|---|---|---|
| free | 4 | 0 |
| admin | 1 | 0 |
| pro | 0 | N/A |

---

## Screen-by-Screen Data Point Map

### Today Tab (TodayView / DigestView)

| Data point | Source API | Backend table | Status |
|---|---|---|---|
| Portfolio composite grade | `GET /holdings` → portfolio_risk_snapshots | `portfolio_risk_snapshots.grade` | ✅ Live |
| Portfolio composite score | same | `portfolio_risk_snapshots.composite_score` | ✅ Live |
| Score delta | same | `portfolio_risk_snapshots.score_delta` | ✅ Live |
| Holdings list (grade, score) | `GET /holdings` → positions | `positions` + `ticker_risk_snapshots` | ✅ Live |
| Today's biggest mover | computed client-side | n/a | ✅ |
| Morning Report link | `GET /digest` | `digests` | ⚠️ Fails for 2 users |

### Morning Report (MorningReportView)

| Data point | Source API | Backend table | Status |
|---|---|---|---|
| Report title / date | `GET /digest/today` | `digests.generated_at` | ✅ |
| Portfolio grade hero | digest content | `digests.structured_sections` | ✅ |
| Macro section | digest content | `digests.structured_sections` | ✅ (when digest generates) |
| Sector section | digest content | `digests.structured_sections` | ✅ |
| Positions section | digest content | `digests.structured_sections` | ✅ |
| Watchlist section | digest content | `digests.structured_sections` | ✅ |
| "Most recent saved briefing" warning | computed from generated_at | n/a | ✅ |
| Verbose digest (Pro) | summary_length check | `user_preferences.summary_length` | ✅ Gated (no payment flow yet) |
| Not yet generated empty state | no digest found | n/a | ✅ Handled |

### Holdings Tab (HoldingsListView)

| Data point | Source API | Backend table | Status |
|---|---|---|---|
| Ticker symbol | `GET /holdings` | `positions.ticker` | ✅ |
| Current price | `GET /holdings` → ticker cache | `prices` / `ticker_risk_snapshots` | ✅ |
| Day change % | same | `ticker_risk_snapshots.factor_breakdown` | ✅ |
| Composite grade | same | `ticker_risk_snapshots.grade` | ✅ |
| Composite score | same | `ticker_risk_snapshots.composite_score` | ✅ |
| Score delta | same | `ticker_risk_snapshots` | ✅ |
| Portfolio value | computed client-side | n/a | ✅ |
| Portfolio composite grade | `GET /holdings` envelope | `portfolio_risk_snapshots.grade` | ✅ |
| Unrealized P&L | computed: (price - cost) × shares | n/a | ✅ |
| Sector breakdown | portfolio snapshot | `portfolio_risk_snapshots.sector_breakdown` | ✅ |
| Watchlist items | `GET /watchlists` | `watchlist_items` | ✅ |
| Subscription tier | `GET /preferences` | `user_preferences.subscription_tier` | ✅ (DB value only) |
| Free limit gate (3 holdings) | client-side check | n/a | ⚠️ UI-only, no backend enforcement |
| Free limit gate (5 watchlist) | client-side? | n/a | ❌ Not implemented |

### Search Tab (SearchView)

| Data point | Source API | Backend table | Status |
|---|---|---|---|
| Search results | `GET /tickers/search?q=` | `ticker_universe` + `ticker_risk_snapshots` | ✅ |
| Result grade | search result | `ticker_risk_snapshots.grade` | ✅ |
| Result score | search result | `ticker_risk_snapshots.composite_score` | ✅ |
| Result price | search result | `ticker_risk_snapshots` or `prices` | ✅ |
| isSupported flag | search result | `ticker_universe.is_active` | ✅ |
| "OUTSIDE" label | `isSupported == false` | n/a | ✅ |
| Recent viewed tickers | UserDefaults (local) | n/a | ✅ |
| Browse chip filters | hardcoded search seeds | n/a | ❌ Fake (not real filters) |
| Trending section | not implemented | n/a | ❌ Placeholder always |
| Add outside-universe CTA | missing | n/a | ❌ Not connected |

### Ticker Detail Tab (TickerDetailView)

| Data point | Source API | Backend table | Status |
|---|---|---|---|
| Ticker, company name | `GET /tickers/{ticker}` | `ticker_metadata` | ✅ |
| Current price | same | `prices` or cached | ✅ |
| Day change | same | `factor_breakdown` | ✅ |
| Composite score | same | `ticker_risk_snapshots.composite_score` | ✅ |
| Composite grade | same | `ticker_risk_snapshots.grade` | ✅ |
| Financial Health score | same | `ticker_risk_snapshots.financial_health` | ✅ |
| News Sentiment score | same | `ticker_risk_snapshots.news_sentiment_dim` | ✅ (30.7% mid-run) |
| Macro Exposure score | same | `ticker_risk_snapshots.macro_exposure_dim` | ✅ (93.8%) |
| Sector Exposure score | same | `ticker_risk_snapshots.sector_exposure` | ✅ 100% |
| Volatility score | same | `ticker_risk_snapshots.volatility` | ✅ 99.4% |
| Methodology drill-down | `GET /methodology/{ticker}` | `ticker_risk_snapshots.dimension_inputs` | ✅ |
| Recent news articles | `GET /tickers/{ticker}/news` | `shared_ticker_events` | ✅ |
| News TLDR | same | `shared_ticker_events.tldr` | ✅ (after relevance fix) |
| News sentiment reason | same | event analysis | ✅ |
| Score history (30d composite) | `GET /tickers/{ticker}/history` | `ticker_risk_snapshots` | ✅ |
| Score history (90d all dims, Pro) | same | same | ⚠️ Gated, Pro tier needed |
| Outside universe banner | `sharedAnalysis.outsideUniverse` | `positions.outside_universe` | ✅ Banner exists |
| Limited data banner | `limitedDataDimensions` | `ticker_risk_snapshots.limited_data_dimensions` | ✅ |
| Last updated timestamp | `ticker_risk_snapshots.updated_at` | same | ✅ |
| Watchlist button | `POST /watchlists/{id}/items` | `watchlist_items` | ✅ |

### Alerts Tab (AlertsView)

| Data point | Source API | Backend table | Status |
|---|---|---|---|
| Alert list | `GET /alerts` | `alerts` | ✅ Live (32 in last 24h) |
| Alert type (grade_change, major_news, etc.) | same | `alerts.type` | ✅ |
| Alert message | same | `alerts.message` | ✅ |
| Alert ticker | same | `alerts.position_ticker` | ✅ |
| Grade before/after | same | `alerts.previous_grade`, `alerts.new_grade` | ✅ |
| Alert read state | same | `alerts.read_at` | ✅ |
| Push delivered | same | `alerts.delivered_at` | ❌ Never delivered (APNs missing) |
| Watchlist alerts (Pro) | gated | n/a | ⚠️ Partial |
| Macro-shock alerts (Pro) | gated | n/a | ⚠️ Partial |

### Settings Tab (SettingsView)

| Data point | Source API | Backend table | Status |
|---|---|---|---|
| Display name | `GET /preferences` | `user_preferences.name` | ✅ |
| Email | Supabase auth | `auth.users.email` | ✅ |
| Subscription tier display | same | `user_preferences.subscription_tier` | ✅ (DB value) |
| Digest delivery time | same | `user_preferences.digest_time` | ✅ |
| Digest length (Free/Pro gate) | same | `user_preferences.summary_length` | ✅ |
| Push alerts "Coming soon" | hardcoded | n/a | ✅ Labeled correctly |
| Brokerage "Coming soon" | FeatureFlags | n/a | ✅ Labeled correctly (but names specific brokerages) |
| App version | Bundle info | n/a | ✅ |

---

## What's Missing for Launch

| Missing data / feature | Severity | Notes |
|---|---|---|
| Subscription purchase flow | CRITICAL | No StoreKit |
| Push notification delivery | HIGH | APNs placeholder env vars |
| Email digest delivery | MEDIUM | No Resend key |
| Outside-universe add CTA | MEDIUM | Backend ready, UI not connected |
| Browse chip real filters | LOW | Fake hardcoded shortcuts |
| Trending section | LOW | Placeholder always |
| data_status field population | MEDIUM | Always null |
| 90-day all-dimension history (Pro) | MEDIUM | Gated but Pro doesn't exist yet |
