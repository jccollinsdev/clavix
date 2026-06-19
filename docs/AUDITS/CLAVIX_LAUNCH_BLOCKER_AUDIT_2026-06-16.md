# Clavix — Critical Launch-Blocker Audit (2026-06-16)

**Reviewer stance:** adversarial senior engineer. Goal: find every flaw between "TestFlight build uploaded" and "safe to charge real money on the public App Store."
**Method:** read the actual iOS source, Xcode project/build settings, backend middleware/routes, entitlements, privacy manifest, legal pages, and **live production data** (Supabase + `/health`) — not the prior session's self-report.
**Headline:** The plumbing is healthy, but there are **3 hard App-Review blockers**, a **monetization that is trivially bypassable**, and the product's central promise — "risk grades you can trust" — **is still broken in production and is worse than the prior session claimed.** Do not submit to public review yet.

> This document is deliberately critical. A "✅ what's actually fine" list is at the end so the criticism is calibrated, not alarmist.

---

## Severity legend
- **P0** — App Review will reject, or a core advertised feature is non-functional in the shipped binary.
- **P1** — Revenue / trust / security integrity. Will not get you rejected, but will lose money, lose users, or embarrass you.
- **P2** — Important correctness/compliance gap; fix before public launch.
- **P3** — Polish / post-launch hygiene.

---

## P0 — Hard blockers (rejection or broken core feature)

### P0-1. The entitlements file is orphaned — Sign in with Apple **and** Push ship without their entitlements
**This is the most important technical finding in the audit.**

Evidence:
- `ios/Clavis/Resources/Clavis.entitlements` declares only `com.apple.developer.applesignin`. It has **no `aps-environment` key** (push).
- The Xcode project references the file only as a *navigator fileRef* (`project.pbxproj:196,376`). There is **no `CODE_SIGN_ENTITLEMENTS` build setting in any configuration** — `grep -i ENTITLEMENTS project.pbxproj` returns only the fileRef, and the resolved `xcodebuild -showBuildSettings` output contains **no `CODE_SIGN_ENTITLEMENTS` key at all**.
- `grep -rn "aps-environment" ios/` → no matches anywhere.

Why it matters:
- An entitlements file that is not wired via `CODE_SIGN_ENTITLEMENTS` is **not applied to the signed app.** That means the TestFlight build `1.0 (1)` was very likely signed **without** the Sign in with Apple entitlement and **without** any push entitlement.
- **This is the real root cause of "0 push device tokens"** — not the `requestPermission()` ordering fix from this session. Even with permission granted, `registerForRemoteNotifications()` cannot mint a token without `aps-environment` in the signed entitlements; iOS calls `didFailToRegisterForRemoteNotificationsWithError`.
- It is also a strong candidate for the **`ASAuthorizationError error 1000`** on device. The session attributed that solely to a deallocated `ASAuthorizationController` and fixed the retain (good, keep it), but error 1000 is *also* the classic symptom of Sign in with Apple not being provisioned/entitled. If the entitlement is missing, the retain fix alone will not make Apple sign-in work end-to-end.
- Sign in with Apple is **advertised in the app and declared in the privacy manifest**. If it does not complete, that is an automatic **Guideline 4.0/2.1** rejection, and Google sign-in without working Apple sign-in is a **Guideline 4.8** rejection.

Fix (do via Xcode UI, not by hand-editing the file):
1. Target **Clavis → Signing & Capabilities → + Capability → Push Notifications**, and confirm **Sign in with Apple** is listed. Adding the capability is what makes Xcode write `CODE_SIGN_ENTITLEMENTS = Clavis/Resources/Clavis.entitlements` into **every** build config and inject `aps-environment`.
2. Re-archive. Then **prove it**: `codesign -d --entitlements :- <Clavis.app>` on the archived binary must show both `com.apple.developer.applesignin` and `aps-environment = production`.
3. Only then are "push works on device" and "Apple sign-in completes on device" actually testable.

---

### P0-2. Paywall has no functional Terms of Use / Privacy Policy links and incomplete auto-renew disclosure (Guideline 3.1.2)
Evidence — `ios/Clavis/Views/Paywall/PaywallView.swift:163-170`: the legal footer is a single non-interactive `Text(...)`. There are **no tappable links** to an EULA/Terms of Use or Privacy Policy on the purchase screen. `web/terms.html` and `web/privacy.html` exist but are never linked from the paywall.

Why it matters: Guideline 3.1.2 requires the paywall itself to display, with **functional links**: (a) title of the subscription, (b) length, (c) price (and per-unit price), and (d) functional links to the **Terms of Use (EULA)** and **Privacy Policy**. Missing functional links is one of the most common auto-rejections for subscription apps.

Fix: add two tappable links (Terms of Use, Privacy Policy → `getclavix.com/terms`, `getclavix.com/privacy`) on `PaywallView` and `ExpiredPaywallView`, plus an explicit auto-renew block ("Payment charged to Apple ID, auto-renews unless turned off ≥24h before period end, manage in Settings"). Also set the App Store Connect **App EULA** (or use Apple's standard EULA) and the metadata Privacy Policy URL.

---

### P0-3. "No credit card required" + unverified introductory-offer assumption
Evidence — `ios/Clavis/Views/Paywall/PaywallView.swift:119`: *"14-day free trial · no credit card required · cancel anytime."* The CTA "Start 14-day free trial" calls `subscriptionManager.purchase()` → `product.purchase()` on the auto-renewable `clavix_pro_monthly` (`SubscriptionManager.swift:54-88`).

Two problems:
1. **"No credit card required" is false** for a StoreKit subscription. Starting an auto-renewable subscription (even with an intro free trial) requires a payment method on the Apple ID. The claim is misleading (Guideline 2.3.1 / 3.1.2) and will also generate angry "I got charged" reviews.
2. **The 14-day free trial only exists if it is configured as an Introductory Offer on the App Store Connect product.** The code calls `purchase()` unconditionally and never checks `product.subscription?.introductoryOffer` or intro-eligibility. The launch plan (item A3) only says "create the product at $19.99" — it does **not** mention configuring the intro offer. **If the intro offer is not configured, tapping "Start 14-day free trial" charges $19.99 immediately.** That is a catastrophic copy/billing mismatch and a guaranteed rejection + chargebacks.

Fix: (a) delete "no credit card required"; (b) configure the 14-day free-trial **Introductory Offer** on `clavix_pro_monthly` in App Store Connect; (c) in code, render trial copy from `product.subscription?.introductoryOffer` so the UI can never promise a trial the product doesn't grant; gate the "free trial" label on `introductoryOfferEligibility`.

---

### P0-4. The two trials collide — reconcile the server trial with the StoreKit trial
Evidence: the backend grants a **server-side 14-day trial with no StoreKit involvement** on first preferences creation (`preferences.py:_get_or_create_prefs` sets `trial_ends_at = now + 14d`, `_effective_tier` returns `"trial"` while in window). `SubscriptionManager.checkCurrentEntitlement()` (`SubscriptionManager.swift:131-147`) treats server `trial` as `isPro = true`. Separately, the **paywall offers a StoreKit 14-day intro trial**.

Why it matters: a brand-new user is silently Pro for 14 days with no purchase, then the paywall offers *another* 14-day free trial via StoreKit. That is confusing, double-dips the trial, and makes "what unlocks Pro" non-deterministic. It also undermines P0-3 (the user may already be mid server-trial when they tap "Start free trial").

Fix: pick one source of truth. Recommended: StoreKit owns entitlement; the server `trial` tier is only set *from a verified StoreKit transaction* (see P1-2), not auto-granted on signup. If you keep a no-purchase server trial as the onboarding grace period, make the paywall copy reflect that ("X days left in your trial") and do not also start a StoreKit trial.

---

## P1 — Revenue / trust / security integrity

### P1-1. "Grades you can trust" is still broken in production — and worse than the prior session reported
The session log (`SESSION_2026-06-16.md`) claims the grade flicker was fixed via 3 bugs + a hysteresis bump to 3.0. **Live production data says otherwise.**

Live `ticker_risk_snapshots`, last 14 days (composite_score → letter):

| Ticker | Recent grade sequence (newest→oldest) | Verdict |
|---|---|---|
| **AAPL** | A(74) · BBB(68.4) · A(73) · A(74.8) · BBB(67) · BBB(60) · A(74.8) · A · A · BBB · A · BBB · BBB · BBB | **8 letter flips / 14 days**; the 3 most recent points flip A→BBB→A |
| **AMD** *(your own holding)* | BB(52.8) · B(49.6) · BB(53.8) · B(47.8) · **A(73.8)** · B(48) · B · B · BBB(68.2) · BB · A(70.2) · B · B · BBB · BB | **26-point single-day swing 06-12→06-13, crossing A→B (3 bands)** |
| **MSFT** | A · A · A · BBB · BBB · BBB · BBB · BBB · **B(45.2, safety 82.5)** · BBB · BBB · A · A | one-day dip to B then back; 37-pt composite/safety split on 06-05 |
| **KO** | A every day (74.8–76.0) | ✅ stable (defensive / limited-data name) |

Universe-wide, between the last two recompute days (503 tickers):
- **23 tickers (4.6%) changed letter grade in a single day**, max single-day composite delta **28.0**, two tickers swung ≥15 points.
- The median ticker is now stable (avg delta 0.64) — **but the violent movers are exactly the high-beta, news-heavy mega-caps users are most likely to hold and watch (AAPL, AMD, MSFT, NVDA).** A 20-name portfolio of popular tickers will visibly churn ~daily.

Why it matters: this is the entire value proposition. A user who watches AMD for a week sees it lurch A → B → BB → B. The hysteresis buffer of 3.0 is not large enough for dimensions that legitimately swing 25+ points (macro/volatility/news on high-beta names). **Fix this before a single real user watches a ticker for a week.** Per CLAUDE.md this requires a prod-distribution verification, not a one-line constant bump — likely smoothing the fast dimensions (macro especially) at write time, widening hysteresis only near band boundaries, and capping per-day composite deltas.

### P1-2. SPY and VOO — two identical S&P 500 ETFs — are graded two full bands apart on the same day
Evidence (06-16 live): **SPY = A (composite 70.5)** vs **VOO = BB (composite 59.6, safety 77.0)**. SPY and VOO track the same index; a user holding VOO and glancing at SPY will immediately see the model contradict itself. VOO also shows a 17-point composite/safety divergence. Both were stale for 15 days and only re-entered the refresh set today (P1-5), so this is freshly-computed, not stale, data.

Why it matters: internal inconsistency between near-identical instruments is the single most credibility-destroying thing a "ratings" product can show. Add a sanity check: instruments tracking the same index should not diverge by more than one band; investigate why VOO's composite collapses while its safety stays high.

### P1-3. Monetization is unenforced server-side — any authenticated user can self-grant Pro
Evidence:
- `backend/app/routes/preferences.py:295-322` — `PATCH /subscription-tier` accepts `{"subscription_tier":"pro"}` from the client and writes it to `user_preferences` after validating only that the string is in `{"free","pro"}`. **No StoreKit receipt, no App Store Server API verification.**
- `ios/.../SubscriptionManager.swift:211-223` — `syncTierToBackend()` literally carries the comment *"In production this should use the StoreKit receipt for server-side verification."* It just POSTs `"pro"`.

Why it matters: anyone with their own JWT (which the app hands them on login) can `curl -X PATCH .../preferences/subscription-tier -d '{"subscription_tier":"pro"}'` and unlock Pro forever, free. Combined with the fact that gating is otherwise client-side, **the paywall is decorative from a determined user's perspective.** This is a direct revenue leak.

Fix: verify entitlements server-side with the **App Store Server API** (or validate the signed transaction JWS) before writing `pro`. The client should send the transaction/JWS, not the desired tier. Minimum stop-gap: have the backend reject client-asserted `pro` and only set it from a verified Apple notification (App Store Server Notifications v2).

### P1-4. Composite vs safety score can still contradict each other in the UI
Evidence: the prior session reported "max disagreement 7.8." Live data shows larger splits returning: AAPL 06-16 composite 74.0 / safety 64.2 (9.8), MSFT 06-05 composite 45.2 / safety 82.5 (37.3), VOO 06-16 59.6 / 77.0 (17.4). The app surfaces both numbers; when they disagree by 30+ points the detail screen is self-contradictory.

Fix: confirm which number drives the headline grade, and either reconcile the two pipelines or stop showing the one that isn't authoritative.

### P1-5. Recompute freshness is not uniform — individual tickers silently miss days
Evidence: NVDA has only 5 snapshots in the last 16 days (missing 06-03 → 06-11, a 9-day gap), despite being a top-10 mega-cap. SPY/VOO were stale 15 days until today. The aggregate `/health` "completed" status hides per-ticker gaps.

Why it matters: a user opening NVDA sees a "fresh" grade that is actually 9 days old, with no staleness indicator. Add per-ticker freshness monitoring (alert when any active ticker's latest snapshot is >2 trading days old) and a UI "as of <date>" stamp.

---

## P2 — Important before public launch

### P2-1. Privacy manifest under-declares data collection (App Privacy label mismatch → ITMS-91xxx)
Evidence — `ios/Clavis/Resources/PrivacyInfo.xcprivacy` declares only Email, Name, UserID (linked, App Functionality) and one required-reason API (UserDefaults `CA92.1`). But the app also:
- Ships **Sentry** (`ClavisApp.swift:40`) → collects **Crash Data** and (with `tracesSampleRate 0.1`) **Performance Data**. Neither is declared.
- Ships a first-party **AnalyticsService** sending interaction events (`paywall_viewed`, `purchase_tapped`, etc.) → **Product Interaction / Other Usage Data**. Not declared.
- Mentions a "disk cache" feature → if it reads file timestamps/creation dates it needs the **`C617.1` File Timestamp** required-reason API; verify.

Why it matters: the binary's privacy manifest and the App Store Connect **App Privacy** answers must agree. A mismatch triggers Apple's automated email (ITMS-91053 "Missing API declaration") or App Privacy rejection. Update the manifest and the nutrition label together; confirm the Sentry and Supabase SPMs ship their own bundled manifests for the SDK-level collection.

### P2-2. Push permission is requested at cold launch, before the user signs in or sees value
Evidence — `ClavisApp.swift:31` (`AppDelegate.didFinishLaunchingWithOptions`) fires `requestPermission()` immediately on every launch. This prompts before onboarding/sign-in.

Why it matters: not a rejection, but it tanks opt-in (users deny a prompt with no context) — which *also* contributes to the 0-token problem. Move the prompt to after the user finishes onboarding / sees their first digest, with a pre-permission priming screen.

### P2-3. `ITSAppUsesNonExemptEncryption` is absent from Info.plist
Evidence — `Info.plist` has no `ITSAppUsesNonExemptEncryption`. The app uses only standard crypto (HTTPS, CryptoKit SHA-256 for the Apple nonce), which is exempt. Add `ITSAppUsesNonExemptEncryption = false` to skip the manual export-compliance question on **every** TestFlight/App Store upload.

### P2-4. No rate limiting on public/auth-adjacent endpoints
Evidence — only `admin/login` has a limiter (`admin_auth.check_login_rate_limit`). The public `POST /waitlist` and the authenticated `analytics`/`trigger` endpoints have none. There is no global throttle middleware.

Why it matters: `/waitlist` is unauthenticated and can be spammed (DB bloat / email abuse); `trigger-analysis` can drive paid-API cost (Polygon/Finnhub/MiniMax) if abused. Add a lightweight per-IP/per-user limiter (e.g. slowapi) on public and cost-bearing routes.

### P2-5. `/health` is public and leaks internal config + recompute error text
Evidence — `main.py:327-369`: `/health` is in `public_paths` and returns `apns/snaptrade/minimax/supabase` configuration state plus the **raw last-recompute `error_message`**. Anyone can read your infra posture and internal error strings.

Fix: return a bare `{"status":"ok"}` for the public probe and gate the detailed version behind admin auth (or strip `error`).

### P2-6. Team ID mismatch in the signing chain
Evidence — `project.pbxproj` Release configs use `DEVELOPMENT_TEAM = GYMG4MQS8F` (and the Debug app/test configs are **empty** `DEVELOPMENT_TEAM = ""`), but `LAUNCH_FINAL_REPORT_2026-06-16.md` instructs the user to select Team **`97N24DN2Z2`**. These are different teams.

Why it matters: the team that owns the bundle ID `com.clavisdev.portfolioassistant` and the App Store Connect app record must match the project's signing team, or archive/upload/capability provisioning silently breaks. Reconcile to one team; set it on **all** configs (the empty Debug team will block device builds).

### P2-7. Committed `Secrets.xcconfig`
Evidence — `ios/Clavis/Config/Secrets.xcconfig` is git-tracked (`.gitignore` only excludes `Secrets.local.xcconfig`) and contains the Supabase **anon** key + Sentry DSN. It is also currently **modified-but-uncommitted** in `git status`.

Assessment: the anon JWT and Sentry DSN are *public-by-design* (they ship inside the app binary anyway, and Supabase is RLS-protected), so this is **not a critical leak** — but it is hygiene debt: rotation requires a commit, and a tracked secrets file invites accidentally committing a real secret later. Confirm no `service_role` key ever lands here (it must not), and consider moving to CI-injected values. **Verify production Supabase RLS is actually enforced**, since the anon key is effectively public.

---

## P3 — Polish / post-launch
- **App icon alpha channel:** the `AppIcon-1024.png` is present in the asset set; confirm it has **no alpha/transparency** (silent rejection cause). Quick check before submit.
- `render.yaml` still in repo though backend is VPS/Docker — leave a comment so no one re-points the backend at Render.
- `NSAllowsLocalNetworking = true` in production ATS (`Info.plist:59`) — harmless but unnecessary for a prod app talking only to HTTPS; tighten.
- Large volume of stale planning docs (`roadtolaunch*.md`, multiple audit files) — archive the superseded ones so the current source of truth is unambiguous.
- `AppDelegate.application(open:)` posts a SnapTrade callback notification even though brokerage is deferred (`FeatureFlags.brokerageEnabled=false`) — dead path, fine to leave but note it.

---

## ✅ What is actually fine (calibration)
- Backend is healthy, fast, and observably deployed: live `/health` = ok, APNs/Supabase/MiniMax/SnapTrade configured, **today's recompute completed with no error**.
- **In-app account deletion exists** end-to-end (`SettingsView.DeleteAccountDetailView` → `DELETE /account` cascading delete incl. SnapTrade) — satisfies Guideline 5.1.1(v).
- **Restore Purchases** is implemented (`SubscriptionManager.restorePurchases` / `AppStore.sync`) — required by 3.1.1.
- Financial disclaimers exist and are shown in onboarding + settings + paywall ("informational only / not investment advice").
- StoreKit transaction verification (`checkVerified`) and `Transaction.updates` listener are correct on the *client* side (the gap is server-side, P1-3).
- Admin routes are properly gated by a session-cookie module with login rate limiting (the `/admin/*` JWT-middleware bypass is intentional and safe).
- CORS is a sane explicit allowlist (not wildcard-with-credentials).
- Privacy manifest **exists** (just incomplete, P2-1); app icon set is present; device family is correctly iPhone-only now.
- Crash surface is clean: the only `fatalError` is in a DEBUG-only fixture; API layer has sane timeouts + 401/transport retry.

---

## Recommended order of operations
1. **P0-1** (entitlements wiring) — nothing about push or Apple sign-in is real until this is fixed and verified in the archived binary. Re-archive, re-upload.
2. **P0-2 / P0-3 / P0-4** (paywall links + auto-renew disclosure, kill "no credit card required", configure & verify the intro offer, reconcile the two trials) — these are the review-rejection cluster.
3. **P1-3** (server-side receipt verification) — before you charge anyone, make the paywall non-bypassable.
4. **P1-1 / P1-2** (grade flicker + SPY≠VOO) — before any real user watches a ticker for a week. Verify on prod distribution per CLAUDE.md.
5. **P2-1 / P2-3** (privacy manifest + export-compliance flag) — cheap, removes upload friction and App Privacy rejection risk.
6. Everything else (P1-4/5, P2-2/4/5/6/7, P3) as cleanup during the TestFlight window.

---

## Verification appendix (how each finding was checked)
- Entitlements: `grep -i entitlements project.pbxproj`, `xcodebuild -showBuildSettings` (no `CODE_SIGN_ENTITLEMENTS`), `grep -rn aps-environment ios/` (none), read `Clavis.entitlements`.
- IAP/paywall: read `SubscriptionManager.swift`, `PaywallView.swift`, `ExpiredPaywallView.swift`.
- Backend auth/monetization: read `main.py`, `preferences.py`, `admin.py`, `config.py`.
- Privacy/compliance: read `Info.plist`, `PrivacyInfo.xcprivacy`, `Clavis.entitlements`; enumerated `web/` legal pages.
- Grade integrity: live `ticker_risk_snapshots` queries on prod Supabase (`uwvwulhkxtzabykelvam`), 14-day per-ticker + universe-wide single-day churn aggregate.
- Live state: `curl https://clavis.andoverdigital.com/health`.
