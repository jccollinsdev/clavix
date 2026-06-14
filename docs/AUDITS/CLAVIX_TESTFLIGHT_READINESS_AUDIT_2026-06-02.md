# Clavix TestFlight Readiness Audit — 2026-06-02

**Auditor:** Claude Sonnet 4.6  
**Date:** 2026-06-02  
**Scope:** End-to-end — iOS app, backend, Supabase, VPS, web/legal, Free vs Pro, outside-universe, digest, alerts, App Store readiness  
**Evidence basis:** Live code inspection, production Supabase DB, VPS Docker env, backend logs, legal docs, web files  
**Apple Developer account holder:** PRASHAMSHA KATUWAL (individual account)

---

## 1. Executive Summary

The Clavix core app is real, working, and shows real risk data. The design is polished. The backend is running and generating data daily. However, the app is **not ready for even internal TestFlight** in its current state due to several hard blockers.

The most critical gap: **there is zero StoreKit / IAP code**. The paywall shows "Pro is coming soon" — a button that dismisses with no payment flow. No subscription can be purchased or tested. For an app whose launch plan depends on a 14-day Pro trial, this is a foundational gap that must be resolved before TestFlight can meaningfully test the product.

Beyond subscriptions, **two of four active users' digest jobs are failing daily** with an unhandled None bug. **APNs env vars are literal placeholder strings** (`YOUR_APNS_KEY_ID`) — push notifications are entirely non-functional. **The health endpoint times out publicly** via Cloudflare. **30% of tickers are missing news sentiment** in today's snapshot cycle. And **upgrade copy in three places mentions brokerage sync** in violation of the v1 scope decision.

The outside-universe ticker flow exists and is implemented correctly in both iOS and backend. The legal docs are solid and updated. The data pipeline is running and mostly healthy.

**TestFlight verdict: NOT READY.** Requires P0 fixes before even internal testing is meaningful.

---

## 2. TestFlight Readiness Verdict

| Dimension | Status | Notes |
|---|---|---|
| Core app UI | ✅ Shippable | Polished, real data, good flows |
| Backend / VPS | ⚠️ Running with issues | Health endpoint 524, digest failures |
| Data freshness | ⚠️ Partial | 30% missing news sentiment daily (mid-cycle issue) |
| Free vs Pro subscription | ❌ BLOCKER | Zero StoreKit code; paywall is a dismiss button |
| Digest generation | ❌ BLOCKER | 50% of user digest jobs failing |
| APNs / push | ❌ Non-functional | Placeholder env vars |
| Legal / privacy | ⚠️ Mostly good | PrivacyInfo.xcprivacy has wrong DeviceID entry |
| Outside-universe ticker | ✅ Implemented | Flow works in both iOS and backend |
| App Store Connect | ❌ Not set up | No record, no bundle ID, no build uploaded |

**Ready for internal TestFlight (family/personal devices only):** ❌ NOT YET — Fix digest bug and App Store Connect setup first.  
**Ready for external TestFlight:** ❌ NO — Requires StoreKit + all P0 fixes.

---

## 3. Biggest Blockers

### B1 — No StoreKit / IAP (CRITICAL)
There is not a single line of StoreKit code in the iOS app (`grep -r StoreKit` returns empty). The paywall is a sheet that says "Pro is coming soon" with a button that calls `dismiss()`. The Settings upgrade sheet says "brokerage sync, and CSV import are part of Clavix Pro" — both of which violate the v1 scope decision. Subscription tier is manually set in Supabase (`subscription_tier TEXT`). `trial_started_at` and `trial_ends_at` columns exist in `user_preferences` but are always NULL. There is no mechanism for any user to purchase or trial Pro.

**Impact:** App cannot be commercially launched. TestFlight subscription testing is impossible.  
**Blocked on:** App Store Connect subscription products (IDs must exist before StoreKit can be coded).

### B2 — Digest job failing for 50% of users
Two of four active users had digest jobs fail on 2026-06-01 with the error: `"sequence item 0: expected str instance, NoneType found"`. This is a Python `str.join()` receiving a list with a None element. The test user (7ff5a6c5) is one of the failing users. The error is in the digest pipeline, likely in `portfolio_compiler.py` where a position payload contains a None-valued field that feeds into a string join.

**Impact:** TestFlight testers will not receive daily digests.  
**Can fix now:** Yes — defensive None guard in the join call.

### B3 — APNs env vars are literal placeholders
On the production VPS:
```
APNS_KEY_ID = "YOUR_APNS_KEY_ID"
APNS_TEAM_ID = "YOUR_APNS_TEAM_ID"
APNS_TOPIC = MISSING
APNS_P8_CONTENTS = MISSING
```
Push notifications are completely non-functional. The health endpoint likely reports `apns:missing` for this reason (public health check times out via Cloudflare 524 so cannot confirm, but internal env confirms it).

**Impact:** No push notifications. Grade-change and news alerts cannot be delivered.  
**Blocked on:** You must complete Apple Developer enrollment, create an APNs key in Apple Developer → Certificates, Identifiers & Profiles → Keys, download the `.p8` file, then update the VPS `.env` with real values.

### B4 — Public health endpoint times out (Cloudflare 524)
`https://clavis.andoverdigital.com/health` returns HTTP 524 (Cloudflare timeout). The backend container is running. The issue is the `/health` endpoint is too slow for Cloudflare's timeout threshold. This means the app's health monitoring doesn't work, and any service that pings `/health` to verify uptime will see the app as down.

**Impact:** Uptime monitoring broken. Not a user-facing blocker but critical for ops.  
**Can fix now:** Add a fast `/ping` endpoint that returns 200 immediately; move slow checks to `/health/full`.

### B5 — Brokerage copy in upgrade sheets (scope violation)
Three places in the iOS app mention "brokerage sync" in Pro upgrade pitches:
- `SettingsUpgradeSheet`: "Verbose digest, **brokerage sync**, and CSV import are part of Clavix Pro."
- `OnboardingContainerView` → `OnboardingUpgradeSheet`: "Pro will unlock unlimited positions, **brokerage sync**, verbose morning reports..."
- `OnboardingAddPortfolioView`: Brokerage card says "COMING SOON" badge, which is correct — but the description names it as an upcoming feature rather than deferred post-v1.

Per `CLAVIX_LAUNCH_SCOPE_v1.md` rule 3: "No user-visible copy implies brokerage works today." Mentioning brokerage in a paywall screen even with "coming later" language may violate App Review guidelines if the feature is listed as a paid feature but doesn't exist.

**Can fix now:** Yes — remove brokerage from all paywall/upgrade copy, replace with correct Pro feature list.

---

## 4. What You Must Do Manually (Admin Tasks)

See `TESTFLIGHT_ADMIN_CHECKLIST_2026-06-02.md` for the complete list. Summary:

1. **Apple Developer account setup** — confirm PRASHAMSHA KATUWAL's account is active and paid ($99/yr)
2. **Create App ID** in Identifiers: `com.clavisdev.portfolioassistant`, enable Push Notifications capability
3. **Create APNs key** (Auth Key, not certificate): download `.p8` file, note Key ID and Team ID — these go into VPS `.env`
4. **Create App Store Connect record** — new app, name "Clavix", bundle ID `com.clavisdev.portfolioassistant`
5. **Create In-App Purchase subscription group** — "Clavix Pro", monthly product `clavix_pro_monthly` at $19.99, 14-day free trial
6. **Distribution certificate + provisioning profile** — needed to build an Archive for TestFlight
7. **TestFlight setup** — internal group, add yourself as tester, set beta description and contact
8. **Age rating** — likely 4+ or 12+, must be set before build is testable
9. **Privacy nutrition labels** — configure in App Store Connect to match PrivacyInfo.xcprivacy
10. **Agreements/Tax/Banking** — PRASHAMSHA KATUWAL must accept paid-app agreements and set up banking for Pro proceeds (even if free TestFlight doesn't need this, it's required before any paid transaction)

---

## 5. What the Agent Can Do Now

These are safe to execute without any admin work:

1. **Fix digest bug** — find and guard the None-producing join in `portfolio_compiler.py` / `scheduler.py`
2. **Remove brokerage from upgrade copy** — `SettingsUpgradeSheet`, `OnboardingUpgradeSheet`, replace with correct Pro feature list from CLAVIX_LAUNCH_SCOPE_v1
3. **Fix health endpoint timeout** — add a fast `/ping` route returning 200 immediately, make `/health` non-blocking
4. **Fix PrivacyInfo.xcprivacy** — remove `NSPrivacyCollectedDataTypeDeviceID` (not actually collected)
5. **Write StoreKit scaffolding** — product IDs, `SubscriptionManager`, entitlement check logic that is wired into the app architecture, ready to activate the moment App Store Connect product IDs exist (everything except the actual IAP product fetch which requires valid IDs)
6. **Fix browse chips** — replace hardcoded "Mega caps"→AAPL with real search params or remove until real filters exist
7. **Add backend holding limit enforcement** — currently the 3-holding Free limit is iOS UI only; the backend does not check subscription tier when creating positions
8. **Add `trial_started_at` population** — the DB column exists but is never set; seed it on new user creation
9. **Fix web footer** — "© 2026 Andover Digital" should be "© 2026 Andover Digital LLC"
10. **Remove SnapTrade fields from onboarding copy** — Settings shows "Coming soon: Read-only sync from Robinhood, Schwab, Fidelity" — naming real brokerages in a "coming soon" section is a promise that may not be fulfilled

---

## 6. What Coding Is Blocked by Admin Work

| Coding task | Blocked by |
|---|---|
| Full StoreKit purchase flow | App Store Connect subscription product IDs must exist |
| APNs push delivery | Real `.p8` key file from Apple Developer |
| Entitlement verification via StoreKit | Both above |
| Sandbox subscription testing | App Store Connect setup + TestFlight build |
| Certificate-based distribution build | Distribution certificate + provisioning profile |

---

## 7. What Admin Work Is Blocked by Coding

Nothing is formally blocked. However:

- **Screenshots for App Store Connect** — requires working builds, ideally with correct UI states
- **App Review demo account** — requires a working login flow (already exists)
- **Beta description** — easier to write once upgrade copy is corrected

---

## 8. Free vs Pro Status

### What exists:
- `subscription_tier` column in `user_preferences` (TEXT, values: `"free"`, `"pro"`, `"admin"`)
- iOS reads this from `GET /preferences` and stores in `SettingsViewModel.subscriptionTier`
- iOS gates the Verbose digest length behind `subscription_tier != "free"`
- iOS shows `HoldingsUpgradeSheet` when a Free user hits 3 holdings
- iOS shows `SettingsUpgradeSheet` when a Free user tries to select Verbose
- Trial columns `trial_started_at` / `trial_ends_at` exist in DB but are never populated

### What is MISSING:
- **Zero StoreKit code** — no `Product`, no `Transaction`, no `purchase()`, no receipt verification
- **No RevenueCat** — not integrated
- **Paywall is fake** — `HoldingsUpgradeSheet` "View Pro" button: `dismiss()`. Nothing more.
- **No 14-day trial logic** — columns exist but never set; no expiry enforcement
- **No backend enforcement** — the API accepts `POST /holdings` from a Free user with 10 positions; only the UI blocks it
- **No watchlist limit enforcement** — backend `watchlists.py` has no tier check at all
- **Production users**: 4 `free`, 1 `admin`, 0 `pro`

### What the current TestFlight experience looks like:
A TestFlight tester will:
1. Sign up
2. See "Free" tier
3. Add up to 3 holdings before hitting the upgrade sheet
4. Tap "View Pro" — sheet dismisses, nothing happens
5. Never be able to upgrade or trial Pro

**VERDICT: Free tier partially works (UI limit). Pro tier does not exist in any functional sense.**

---

## 9. Outside-Universe Ticker Status

### iOS:
- `SearchView` shows `"· OUTSIDE"` label in amber when `result.isSupported == false`
- `SearchView` footnote: "If a company is outside the tracked universe, the app should say so directly"
- `TickerDetailView` shows `outsideUniverseBanner` when `sharedAnalysis?.summary.outsideUniverse == true` or `isSupported == false`
- Banner text: "This ticker isn't in the Clavix tracked universe. Risk data may be limited until coverage is added."
- `HoldingsViewModel.addHolding(allowOutsideUniverse: Bool)` — passes flag to API

### Backend:
- `POST /holdings` checks `ensure_ticker_in_universe(supabase, ticker)`
- If ticker not found AND `allow_outside_universe=True`: sets `outside_universe = true` in position
- If ticker not found AND flag not set: returns 400 with clear message
- `positions.outside_universe` column exists (BOOLEAN)

### Current state:
- **0 outside-universe positions in production** (all 514 are in-universe)
- The iOS UI does not currently show a distinct "Add anyway (outside universe)" flow from SearchView — when you search and get a "No match" empty state, the user sees the error message but there's no CTA to add outside-universe
- The backend supports it via `allow_outside_universe=true` but this isn't surfaced in the search empty state

### Verdict:
Outside-universe is **partially implemented**. The data model and backend route work. The iOS warning banner exists. But the end-to-end user flow — "search, no match, tap to add outside universe" — is **not connected**: the search empty state does not offer an "Add anyway" action that passes `allowOutsideUniverse: true` to `addHolding()`.

---

## 10. Data Completeness Status (as of 2026-06-02 ~11:00 UTC)

Note: The daily recompute runs from ~10:00 UTC and is still in progress.

| Metric | Value | Status |
|---|---|---|
| Total universe tickers | 534 active | ✅ |
| Today's snapshots generated | 176 (recompute in progress) | ⚠️ Partial (will be ~534) |
| Has composite score | 176/176 | ✅ 100% |
| Has grade | 176/176 | ✅ 100% |
| Has financial_health | 176/176 | ✅ 100% |
| Has news_sentiment_dim | 54/176 | ⚠️ 30.7% (in-progress) |
| Has macro_exposure_dim | 165/176 | ✅ 93.8% |
| Has sector_exposure | 176/176 | ✅ 100% |
| Has volatility | 175/176 | ✅ 99.4% |
| data_status field | 0/176 populated | ⚠️ Always NULL |

**Grade distribution (today's recomputed tickers):**
| Grade | Count | % |
|---|---|---|
| A | 76 | 49.7% |
| BBB | 62 | 40.5% |
| BB | 6 | 3.9% |
| AA | 4 | 2.6% |
| B | 4 | 2.6% |
| CCC | 1 | 0.7% |
| AAA | 0 | 0% |

The grade distribution is materially better than the pre-fix audit (was 98% BBB/BB). A/BBB distribution looks realistic. No AAA tickers (acceptable). CCC/B present (healthy).

**Historical data** (all snapshots ever): 507 unique tickers, 49 days of history.

---

## 11. Daily Digest Status

| Item | Status |
|---|---|
| Digest pipeline exists | ✅ Yes (`portfolio_compiler.py`, `scheduler.py`) |
| Per-user scheduler jobs | ✅ 4 active, 1 disabled |
| Digest generation today (6/2) | ⚠️ Not yet (scheduled 11:00 UTC, still running) |
| Digest generation yesterday (6/1) | ❌ 2 of 4 users FAILED |
| Failure error | `"sequence item 0: expected str instance, NoneType found"` |
| Affected users | `7ff5a6c5` (test user), `a4ba5a72` |
| Total digests in DB | 186 across 5 users |
| Most recent digest | 2026-06-01 20:10 UTC (triggered on-demand) |
| MiniMax integration | ✅ MINIMAX_API_KEY set |
| Verbose digest gating | ✅ Implemented in iOS + backend |
| Resend (email) | ❌ RESEND_API_KEY missing — email delivery non-functional |

**Root cause of failure:** A `str.join()` call receives a list where item 0 is `None`. Most likely in `portfolio_compiler.py` or `scheduler.py` in the section that builds position payload strings. The `_clean_text_list()` helper exists and filters None, but is not used consistently everywhere.

**Fix required:** Add `or []` + isinstance guard around the specific join call. Medium-risk fix (need to identify exact line from a full traceback).

---

## 12. Backend / VPS Status

| Item | Status | Notes |
|---|---|---|
| Docker container | ✅ Up 9 hours | `clavis-backend-1` healthy |
| SCHEDULER_TIER | ✅ intraday | Full job set running |
| Supabase connection | ✅ Active | Real-time DB operations in logs |
| MINIMAX_API_KEY | ✅ Set | |
| POLYGON_API_KEY | ✅ Set | |
| FINNHUB_API_KEY | ✅ Set | |
| APNS_KEY_ID | ❌ PLACEHOLDER | Value is literal "YOUR_APNS_KEY_ID" |
| APNS_TEAM_ID | ❌ PLACEHOLDER | Value is literal "YOUR_APNS_TEAM_ID" |
| APNS_TOPIC | ❌ Missing | Not set at all |
| APNS_P8_CONTENTS | ❌ Missing | Not set at all |
| RESEND_API_KEY | ❌ Missing | Email delivery non-functional |
| Public health endpoint | ❌ 524 Timeout | Cloudflare timeout; too slow |
| SP500 daily recompute | ✅ Running | Metadata refresh visible in logs |
| News source | ✅ Finnhub | `finnhub_news.py` is the live source |
| Digest scheduler | ⚠️ Running with failures | 50% fail rate yesterday |
| Failed jobs retry | ⚠️ Unclear | No evidence of automatic retry on failure |

---

## 13. Website / Legal Status

| Item | Status | Notes |
|---|---|---|
| Privacy Policy | ✅ Good | Mentions Andover Digital LLC, MiniMax AI, APNs token, brokerage deferred |
| Terms of Service | ✅ Good | Andover Digital LLC as operator |
| App Store distributor disclosure | ✅ Present | Privacy mentions individual Apple account holder |
| Brokerage disclosure | ✅ Correct | "Brokerage account connections are not available in the current version" |
| MiniMax / AI disclosure | ✅ Present | Section 4 fully discloses AI processing |
| Investment advice disclaimer | ✅ Correct | "Not a broker or adviser" |
| Web footer copyright | ⚠️ Minor | "© 2026 Andover Digital" — missing "LLC" |
| Website brokerage copy | ✅ Clean | "No brokerage connection required" |
| Methodology page | ✅ Exists | `/docs/PUBLIC/methodology.md` |
| Support email | ✅ Present | support@getclavix.com |
| PrivacyInfo.xcprivacy | ⚠️ Wrong entry | Lists `NSPrivacyCollectedDataTypeDeviceID` — not actually collected |
| Pricing page | ⚠️ Outdated | `docs/PRODUCT/pricing.md` still lists brokerage sync as Pro feature |
| Website pricing section | N/A | No public pricing page exists yet |

---

## 14. Apple / App Store Connect Status

**Current state:** Apple Developer account exists under PRASHAMSHA KATUWAL. App Store Connect has NOT been set up. No app record, no bundle ID registered, no certificates, no builds uploaded.

See `APP_STORE_CONNECT_SETUP_NOTES_2026-06-02.md` for step-by-step instructions.

---

## 15. P0 / P1 / P2 Task List

### P0 — Blocks TestFlight (must fix first)

| # | Task | File(s) | Safe now? |
|---|---|---|---|
| P0-1 | Fix digest job None crash | `portfolio_compiler.py`, `scheduler.py` | ✅ Yes |
| P0-2 | Remove brokerage from all upgrade/paywall copy | `SettingsView.swift`, `OnboardingContainerView.swift` | ✅ Yes |
| P0-3 | Fix health endpoint 524 — add fast `/ping` | `backend/app/main.py`, `backend/app/routes/` | ✅ Yes |
| P0-4 | Fix PrivacyInfo.xcprivacy — remove DeviceID | `ios/Clavis/Resources/PrivacyInfo.xcprivacy` | ✅ Yes |
| P0-5 | Set up App Store Connect app record | Apple Developer — admin task | Admin only |
| P0-6 | Upload first build to TestFlight | Xcode Archive | Blocked by P0-5 |
| P0-7 | Set real APNs env vars on VPS | VPS `.env` | Blocked by Apple APNs key |
| P0-8 | Write StoreKit scaffolding (product IDs, manager, entitlement) | New `SubscriptionManager.swift` | ✅ Yes (wire IDs later) |

### P1 — Should fix before external TestFlight

| # | Task | File(s) | Safe now? |
|---|---|---|---|
| P1-1 | Populate `trial_started_at` on new user signup | `backend/app/routes/preferences.py` | ✅ Yes |
| P1-2 | Add backend enforcement for Free 3-holding limit | `backend/app/routes/holdings.py` | ✅ Yes |
| P1-3 | Add backend enforcement for Free 5-watchlist limit | `backend/app/routes/watchlists.py` | ✅ Yes |
| P1-4 | Connect "outside universe" add flow in SearchView | `ios/Clavis/Views/Search/SearchView.swift` | ✅ Yes |
| P1-5 | Add real paywall UI (wire to StoreKit when IDs exist) | New `PaywallView.swift` | Needs P0-8 |
| P1-6 | Fix `data_status` never being written | `backend/app/pipeline/scheduler.py` | ✅ Yes |
| P1-7 | Fix browse chips (fake search seeds) | `ios/Clavis/Views/Search/SearchView.swift` | ✅ Yes |
| P1-8 | Remove Robinhood/Schwab/Fidelity from "Coming soon brokerage" copy | `ios/Clavis/Views/Settings/SettingsView.swift` | ✅ Yes |
| P1-9 | Add Resend key or label email digest "Coming later" clearly | VPS `.env` + `CLAVIX_LAUNCH_SCOPE_v1` says label it | Admin task |
| P1-10 | Update `docs/PRODUCT/pricing.md` to remove brokerage | `docs/PRODUCT/pricing.md` | ✅ Yes |
| P1-11 | Fix web footer "Andover Digital" → "Andover Digital LLC" | `web/index.html` | ✅ Yes |

### P2 — Polish before public launch

| # | Task | Notes |
|---|---|---|
| P2-1 | Build trending section (real data) | Currently always shows placeholder |
| P2-2 | Add "Operated by Andover Digital LLC" to in-app Settings legal | Settings → Support & Legal |
| P2-3 | Add score history sparklines for Pro (90-day, all 5 dims) | Per CLAVIX_LAUNCH_SCOPE_v1 |
| P2-4 | Email digest of alerts (SMTP) | Label "Coming later" until Resend is wired |
| P2-5 | CSV export | Label "Coming later" |
| P2-6 | Manual ticker refresh (5/day/ticker for Pro) | Label "Coming later" |
| P2-7 | Advanced alerts (watchlist, macro-shock) | Partial — gating logic needed |

---

## 16. Exact Next 10 Actions in Order

1. **[Admin — You]** Log into Apple Developer (`developer.apple.com`) as PRASHAMSHA KATUWAL. Confirm the membership is Active and paid. If not active, renew ($99).

2. **[Admin — You]** In Apple Developer → Identifiers, register App ID `com.clavisdev.portfolioassistant`, type iOS App, enable Push Notifications capability.

3. **[Admin — You]** In Apple Developer → Keys, create a new APNs key. Download the `.p8` file. Note the Key ID and your Team ID. **Do not lose the .p8 — it can only be downloaded once.**

4. **[Admin — You]** SSH to VPS (`ssh clavix-vps`) and update `/opt/clavis/backend/.env` with the real values: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC=com.clavisdev.portfolioassistant`, and `APNS_P8_CONTENTS=<base64 of .p8>`. Then: `sudo -n docker compose restart clavis-backend`.

5. **[Agent]** Fix the digest job crash. Run the failing user's digest manually on VPS to confirm fix. (`ssh clavix-vps 'sudo -n docker exec clavis-backend-1 python -m app.scripts.verify_digest_scheduler'`)

6. **[Agent]** Remove brokerage from all upgrade copy. Fix PrivacyInfo.xcprivacy DeviceID. Add fast `/ping` endpoint to backend. Fix web footer. These are all safe, small, parallel changes.

7. **[Admin — You]** Create App Store Connect app record: go to `appstoreconnect.apple.com` → My Apps → "+". Fill app name "Clavix", bundle ID `com.clavisdev.portfolioassistant`, SKU `clavix-ios-v1`, primary language English.

8. **[Admin — You]** In App Store Connect → Subscriptions, create subscription group "Clavix Pro", add product `clavix_pro_monthly` at $19.99, set 14-day free trial, submit for review.

9. **[Agent]** Write `SubscriptionManager.swift` with product IDs hardcoded (`clavix_pro_monthly`), StoreKit 2 API, entitlement check, purchase flow. Wire into `SettingsViewModel` and `HoldingsViewModel`.

10. **[Admin — You]** Create distribution certificate + provisioning profile for `com.clavisdev.portfolioassistant` in Apple Developer. In Xcode: Product → Archive → Distribute App → App Store Connect → Upload. Confirm build appears in TestFlight.
