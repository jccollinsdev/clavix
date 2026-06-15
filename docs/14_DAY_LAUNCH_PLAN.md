# Clavix 14-Day App Store Launch Plan

**Created:** 2026-06-15
**Goal:** App Store submission by Day 10, live by Day 12-14 (depending on App Review speed)
**Basis:** Launch-readiness audit in `docs/AUDITS/LAUNCH_2026-06-14/`
**Hours per day:** 8h

---

## Pre-start: Before Day 1 begins

Log into App Store Connect and answer these four questions. Everything else depends on the answers:

1. Does an app record for Clavix exist?
2. Is the Paid Apps Agreement signed, with banking and tax forms complete?
3. Does IAP product `clavix_pro_monthly` exist?
4. Is the Apple Developer membership active?

Banking and tax processing takes 2-5 days. If it is not done, start it immediately or the whole timeline slips.

---

## Day 1

**Morning (4h): Apple admin**
- Complete everything in App Store Connect: app record if missing, Paid Apps Agreement, banking (routing + account), W-9 or W-8, Small Business Program enrollment (15% commission; takes up to 7 days to activate, start now).
- Create the IAP product `clavix_pro_monthly` at $19.99/mo. Set it to "cleared for sale."

**Afternoon (4h): Score column unification (backend)**
- Pick `composite_score` as the one true column everywhere. Audit every API response field and confirm none reads `safety_score` for user-facing output.
- Add a Supabase migration: `UNIQUE (ticker, snapshot_date)` on `ticker_risk_snapshots`, then dedupe existing duplicate rows (keep the latest).
- Confirm AMD shows one row per date after the migration, composite_score and grade agree.

---

## Day 2

**Morning (4h): Grade stability fix (backend)**
- Enforce hysteresis at write time: before writing a new grade, check the previous day's grade and require a threshold delta to flip. Slow dimensions (financial_health) should only update from fresh quarterly data, not re-derive every run.
- Deploy to VPS, watch the next recompute, spot-check AAPL: grade should not flip between A and BBB within 48 hours.

**Afternoon (4h): Observability**
- Add UptimeRobot (free) on `/health`, 5-minute check, email alert on failure. Takes 10 minutes.
- Add a job-failure alert: after `daily_composite_recompute_universe` completes, if `error_json` is non-null or status is not "completed", fire an email. Wire it into the existing job runner.
- SSH to VPS and confirm `SENTRY_DSN` is set in the container env: `sudo -n docker exec clavis-backend-1 env | grep SENTRY`. If missing, set it and restart.

---

## Day 3

**Morning (4h): ETF backfill (backend)**
- Add the top 15 ETFs to the universe (QQQ, XLF, XLK, XLE, XLV, XLI, XLC, XLY, XLP, XLU, XLRE, XLB, AGG, BND, VTI). These need ETF-specific financial-health handling (no P/E, use AUM and expense ratio).
- Trigger a targeted backfill for those tickers. Verify at least QQQ and XLK have a snapshot_date row by end of day.

**Afternoon (4h): iOS crash reporter**
- Add Sentry iOS SDK via Swift Package Manager.
- Initialize in your `@main` App struct, pointing at the same Sentry DSN.
- Trigger a test crash in the simulator, confirm it lands in Sentry. Do not ship a beta without this.

---

## Day 4

**Morning (4h): iOS trial-only gating (part 1)**
- In `SubscriptionManager`, confirm `isPro` is `true` during trial.
- Find every feature gate that reads `subscriptionTier == "free"` and replace with `!SubscriptionManager.shared.isPro`.
- Remove the 3-holding and 5-watchlist freemium caps entirely.

**Afternoon (4h): iOS trial-only gating (part 2)**
- Add the "expired and not subscribed" lock screen. When `now > trial_ends_at` and `isPro == false`, show a full-screen paywall with no dismiss.
- Fix paywall copy: "14-day free trial, no credit card required" is correct for server-granted trial. Make sure copy is consistent everywhere it appears.

---

## Day 5

**Morning (4h): iOS performance (disk cache)**
- Add a simple Codable disk cache in `APIService`: on every successful response, write to a file keyed by URL. On cold launch, return cached value immediately and refresh in the background.
- Target the three heaviest cold-launch calls: holdings list, today's digest, and grades for the portfolio.

**Afternoon (4h): iOS brokerage gate + ticker detail**
- In `HoldingsViewModel.loadHoldings`, wrap `fetchBrokerageStatus` and `syncBrokerage` in `if FeatureFlags.brokerageEnabled`. Removes two-plus wasted round trips from every holdings load.
- In `TickerDetailView`, confirm risk, price history, news, and methodology fetch concurrently with `async let`. Convert any sequential fetches.

---

## Day 6

**Morning (4h): Apple/Google sign-in setup (admin + config)**
- In Supabase Dashboard, enable the Apple provider: generate the client secret JWT using your Apple Developer key (need key ID, team ID, and a Sign in with Apple key).
- Enable the Google provider: create an OAuth 2.0 client in Google Cloud Console with the Supabase callback URL.
- Enable Sign in with Apple on the App ID in Apple Developer Portal.

**Afternoon (4h): Build + fix compile errors**
- Build the app in Xcode. The new auth commits (AppleSignInCoordinator, AuthenticationServices, CryptoKit) have never been compiled. Fix every error.
- Run in the simulator, confirm email/password auth works end to end.

---

## Day 7

**Morning (4h): Apple/Google sign-in (iOS side)**
- Wire `AppleSignInCoordinator` to the sign-in button.
- Wire Google sign-in and confirm the callback URL is handled correctly.

**Afternoon (4h): Full simulator QA pass**
- Core loop: add a holding, see grades, drill into a ticker, read the digest, add a watchlist item.
- Trial state: confirm a fresh user gets full access, lock screen appears at trial expiry.
- Paywall: purchase button present, UI correct.

---

## Day 8

**Morning (4h): Archive and upload**
- Set Marketing Version 1.0.0 in Xcode. Bump build number.
- Archive and upload to App Store Connect (takes 10-20 minutes to process).
- Add your one tester under App Store Connect Users for internal TestFlight. No Beta App Review needed.

**Afternoon (4h): On-device validation (real iPhone)**
- Install on your real iPhone from TestFlight.
- Push notifications: accept the permission prompt. Check Supabase `user_preferences` to confirm the APNS token landed. Send a test push and confirm delivery.
- Apple sign-in: complete the full flow on device. Fix any issues.

---

## Day 9

**Morning (4h): Sandbox purchase**
- In App Store Connect, create a sandbox tester account (Settings > Sandbox > Testers).
- On the device, sign into the sandbox account in Settings > App Store.
- Launch the app, hit the paywall, purchase `clavix_pro_monthly`. Confirm the entitlement flips to Pro, app unlocks, and survives a restart.
- Test restore purchases.

**Afternoon (4h): Screenshots**
- Capture the 6.7-inch set (iPhone 17 sim or real device): holdings tab, digest tab, ticker detail, radar screen, paywall. Five screens minimum.
- Capture the 6.1-inch set as well.

---

## Day 10

**Morning (4h): App Store listing**
- Complete the listing: app name "Clavix", subtitle, description (lead with ICP value prop, no investment advice language). Keywords.
- Support URL (getclavix.com or a dedicated page). Privacy policy URL (must be live on the web).
- Age rating: Finance, no mature content. Export compliance: no custom encryption.
- App Privacy nutrition label: email, name, financial info (holdings), usage data if analytics on. Be complete; finance apps get flagged for incomplete labels.

**Afternoon (4h): Final check and submit**
- Read the app description out loud. Remove any language implying investment advice, guaranteed returns, or predictions.
- Confirm "Informational, not advice" disclaimer is visible in the app.
- Submit for App Review.

---

## Days 11-14: App Review

Finance apps typically take 2-4 days. Most common rejection reasons and same-day fixes:

| Rejection reason | Fix |
|---|---|
| Subscription terms not clear | Add trial length and price to paywall disclosure block |
| "Investment advice" language | Remove "recommend," "should buy," "will perform" from all user-visible strings |
| App Privacy label mismatch | Add any data type you missed |
| Missing privacy policy | Confirm URL is live and loads on a device outside your network |
| IAP not testable by reviewer | Confirm IAP product is live and sandbox account works |

If rejected: read the reason, fix it same day, reply in Resolution Center, resubmit if a new build is needed.

---

## Risks that can blow this timeline

1. **Paid Apps Agreement / banking not done on Day 1:** if not resolved by Day 3, you cannot submit a paid app. Start it today.
2. **App Review rejection:** one rejection adds 2-3 days. Finance apps reject roughly 30-40% on first submission. Clean copy and a complete App Privacy label cut this risk.
3. **Apple Small Business Program:** takes up to 7 days to activate. Enroll on Day 1. If not active by launch, you pay 30% on early conversions instead of 15%.
4. **ETF backfill and grade stability:** these do not block the TestFlight build but do block a trustworthy public launch. Backend work can continue in parallel with iOS work.

---

## Honest expectation

If banking is already done and there are no App Review rejections: live on the App Store by **Day 12-13.**
If banking needs setup or review rejects once: add 3-5 days, putting you at Day 16-18.

The things in your control (code, listing, screenshots) are achievable in the time. App Review speed is not in your control. Submit early, respond to rejections same day.

---

*See also: `docs/AUDITS/LAUNCH_2026-06-14/00_MASTER_SYNOPSIS.md` and `docs/ROADMAP_TO_LAUNCH.md`*
