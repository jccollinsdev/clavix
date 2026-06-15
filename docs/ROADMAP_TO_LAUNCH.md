# Clavix Roadmap to Launch

**Owner:** Sansar / Andover Digital LLC
**Created:** 2026-06-14
**Basis:** the launch-readiness audit in `docs/AUDITS/LAUNCH_2026-06-14/` (start with `00_MASTER_SYNOPSIS.md`)
**Decisions locked this round:** monetization = free trial only (no perpetual free); beta goal = validate everything (UX, monetization, push, Apple/Google); Apple status = unknown.

This roadmap has four phases. Phase 0 is "find out where Apple stands and fix what makes the product honest." Phase 1 gets a build to your one tester. Phase 2 makes the full beta (paywall, push, auth) real. Phase 3 is the paid public launch. Each item lists who can do it (you only, or code) and why it is where it is.

---

## Phase 0: Truth and unblocking (do first, in parallel where possible)

Goal: stop the trust bleed and clear the longest-lead admin uncertainty. Nothing below requires a build.

### 0.1 Apple admin reconnaissance (you only, do today)
You said you do not know your App Store Connect status. This is the longest lead item, so resolve it first.
- Log into App Store Connect and check: is there an app record for Clavix? Does the IAP product `clavix_pro_monthly` exist? Is the Paid Apps Agreement (and banking and tax) accepted? Is the Apple Developer membership active and is the account the individual account for PRASHAMSHA KATUWAL?
- Walk `docs/LAUNCH/TESTFLIGHT_ADMIN_CHECKLIST_2026-06-02.md` and mark each item real or not.
- Enroll in the Apple Small Business Program (15% commission). This doubles your net per subscriber in year one.
- Output: a checked list of what exists, so Phases 1 and 2 know what is left.

### 0.2 Fix the data-trust trio (code) — this is what makes the product honest for your ICP
1. **Grade and dimension stability** (`02_BACKEND_DATA_FRESHNESS.md` 3.1). Reuse stable weekly and quarterly bases for the slow dimensions, enforce hysteresis at write time, and remove any heuristic fallback that writes fake dimension values when upstream fails. Verify on AAPL: no more A, BBB, BBB, A across a week, and financial health stops bouncing 62, 80, 88.
2. **Unify the score column** (3.2). Choose `composite_score` (it drives the grade), make every API field and iOS model read it, add a unique constraint on `(ticker, snapshot_date)`, dedupe existing rows, drop the dead `news_sentiment` and `macro_exposure` non-`_dim` columns.
3. **ETF backfill** (3.3). Add the top ETFs (QQQ, the sector SPDRs, AGG, BND, SCHD, VTI, IWM, and the rest of the top 50) with the ETF-specific financial-health handling, so common portfolios are covered.

### 0.3 Confirm the recompute fix holds (ops)
Watch the next weekday `daily_composite_recompute_universe` run and confirm it completes green now that the throttle is deployed. The weekly volatility job already proves the fix; this confirms the daily job too.

### 0.4 Minimum observability (ops + code, half a day)
- Add an external uptime monitor on `/health`.
- Add a scheduled-job failure alert (and capture `error_json`).
- Confirm backend Sentry DSN is set and receiving.
- Add an iOS crash reporter. (Do not ship a beta build without this.)

Exit criteria for Phase 0: Apple status known, grades stable on a spot check, one score column everywhere, top ETFs covered, recompute confirmed green, uptime and job alerts live, iOS crash reporting in the build.

---

## Phase 1: First build to your tester (internal TestFlight)

Goal: get a real build on the tester's phone. Internal TestFlight needs no App Review and no screenshots, so this can move fast once the build is clean.

### 1.1 Build-verify the committed work (code)
- Compile the now-committed Sign in with Apple and Google changes (new `AuthenticationServices` and `CryptoKit` imports and the entitlement have never been built). Fix any compile issues.
- Decide the auth path for this first build:
  - Recommended for speed: hide the Apple and Google buttons behind a flag, ship email/password, and finish the providers in Phase 2. This removes a configuration dependency from the critical path.
  - Or: finish the providers now (0.2 of Phase 2) and ship auth in the first build. Choose this only if you want auth in the very first tester session.

### 1.2 Trial-only gating (code) — required because you chose trial-only
- Make the backend gates honor the effective tier: treat trial, pro, and admin as unlocked; free is only the expired state.
- Add the "expired and not subscribed" hard-paywall lock state (does not exist yet).
- Wire iOS feature gates and the lock screen to `SubscriptionManager.isPro` instead of the raw `subscription_tier == "free"`.
- Remove or repurpose the freemium caps (3 holdings, 5 watchlist) since there is no perpetual free tier.
- Fix the paywall copy to match the chosen trial mechanism (recommended: server-granted, card-free, so "no credit card required" stays true).

### 1.3 Apple build setup (you only)
- App Store Connect app record (if 0.1 found none): name Clavix, SKU, category Finance, age rating, support and privacy URLs (getclavix.com).
- Distribution certificate and App Store provisioning profile.
- Set Marketing Version 1.0.0, bump the build number.
- Confirm the Push Notifications capability is still present at archive time (the new entitlements file declares Sign in with Apple; make sure `aps-environment` is not dropped).

### 1.4 Archive, upload, invite
- Archive and upload. Add the tester under Users in App Store Connect for internal TestFlight (no Beta App Review needed).

Exit criteria for Phase 1: the tester has the app, can sign in (email/password at minimum), use the core loop, and is inside a working 14-day trial that actually unlocks Pro.

---

## Phase 2: Make the full beta real (the "everything" you asked for)

Goal: the tester can experience monetization, push, and Apple/Google. These have on-device and admin dependencies, so they follow the first build.

### 2.1 Monetization end to end
- Create the IAP product `clavix_pro_monthly` in App Store Connect (or a StoreKit configuration file to test the purchase UI locally first).
- Accept the Paid Apps Agreement, banking, and tax forms.
- Test a sandbox purchase on the device: entitlement flips to Pro, survives restart, restore-purchases works, trial-to-paid transition is correct.
- Add an annual plan (can be Phase 3, but easy to do here).

### 2.2 Push on device
- On a physical iPhone: permission prompt fires, token lands in `user_preferences.apns_token`, send a test push, confirm arrival and that tapping it deep-links correctly.

### 2.3 Apple and Google sign-in (if not shipped in Phase 1)
- Configure the Supabase Apple and Google providers, enable Sign in with Apple on the App ID, create the Google OAuth client with the `clavix://auth/callback` redirect.
- Verify both flows on the device, then unhide the buttons.

### 2.4 Funnel analytics
- Add the events from `06_FAILURE_MODES_TESTFLIGHT.md` section 1 so you can see whether the tester reached the paywall, started the trial, and converted, and where anyone drops.

Exit criteria for Phase 2: the tester (and you) can complete a sandbox purchase, receive a push, and sign in with Apple and Google, and you can see the funnel in analytics.

---

## Phase 3: Paid public launch

Goal: open it up, with the reliability a paid trust product needs.

### 3.1 Data reliability for real users
- Move Finnhub and Polygon to paid tiers so freshness no longer depends on a fragile throttle (`05_MONETIZATION_BUSINESS.md` section 4). Break-even rises to about 7 to 9 subscribers, still trivial.
- Make the freshness SLO and the job-failure alert part of normal operations.

### 3.2 Resilience
- Enable DigitalOcean droplet backups and write the rebuild-from-repo runbook.
- Resize the droplet if recompute and live traffic start to contend.
- Confirm Supabase backup retention and run one test restore.

### 3.3 App Store listing and review
- Load the screenshot set you already captured and the listing metadata into App Store Connect.
- Complete App Privacy nutrition labels (include Apple and Google sign-in identifiers).
- Answer export compliance.
- Submit for App Review. Budget for a finance-app review that scrutinizes the "informational, not advice" framing and the subscription disclosure.

### 3.4 Pricing and growth
- Confirm the Small Business Program enrollment is active.
- Add the annual plan if not already.
- Plan a top-of-funnel approach, since trial-only removes the free-tier growth engine (content, referrals, the ICP communities in truth doc §3).

Exit criteria for Phase 3: live on the App Store, monitored, with robust data freshness and a working subscription business.

---

## The single most important sequence

If you do nothing else in order, do this:
1. Find out where Apple stands (0.1). It has the longest lead time.
2. Fix grade stability, the score column, and ETF coverage (0.2). This is what makes the product worth trusting for your ICP, and it is the thing prior audits missed.
3. Add the crash reporter and the two ops alerts (0.4). So the beta teaches you something instead of failing silently.
4. Then build, gate the trial correctly, and ship to the tester (Phase 1).

Everything after that (full monetization, push, auth, public launch) is sequencing, not discovery. The discovery work is Phase 0.
