# Clavix App Store Readiness Audit — 2026-06-12

**Auditor:** Claude Opus 4.8 (in-session)
**Scope:** Everything between "the app runs in the simulator" and "the app is live (or in external TestFlight) on the App Store." Covers Apple admin, StoreKit/IAP, push, privacy/legal, sign-in, build/signing, and the new Apple/Google auth work.
**Status legend:** ✅ done · ⚠️ partial / needs verify · ❌ not started · 👤 human/admin only
**Apple Developer account:** Individual, account holder **PRASHAMSHA KATUWAL** (see `docs/LAUNCH/TESTFLIGHT_ADMIN_CHECKLIST_2026-06-02.md`).

---

## 0. Executive summary

The **code side of launch is in good shape**: StoreKit 2 is scaffolded, the paywall exists, privacy/legal pages are live, the release build compiled green at the last checkpoint, and a brand-new (uncommitted) **Sign in with Apple + Google** flow is fully wired in source. The blockers are now concentrated in three buckets:

1. **Apple admin (👤 only you can do these):** App Store Connect record, the `clavix_pro_monthly` subscription product + 14-day intro offer, distribution cert/profile, archive + upload. Status unconfirmed this session; per the last audit these were **not yet set up**.
2. **Verify-on-device:** push token registration and a real StoreKit sandbox purchase can only be proven on a TestFlight device.
3. **Finish + commit the new auth feature** and configure its providers (Supabase + Apple Developer capability + Google OAuth client).

None of these are deep rewrites. The critical-path gate is the Apple admin work plus the in-flight auth feature.

---

## 1. Apple Developer & App Store Connect (👤 admin)

These are human-only and could not be verified from this session. Per `TESTFLIGHT_ADMIN_CHECKLIST_2026-06-02.md`, treat as **not confirmed done** until you check.

| Item | Needed for | Status |
|---|---|---|
| Apple Developer membership active ($99/yr) | Everything | ⚠️ confirm |
| App ID `com.clavisdev.portfolioassistant` + **Push** capability | Build + push | ⚠️ confirm |
| App ID + **Sign in with Apple** capability (NEW) | New auth | ❌ likely not yet (auth is new) |
| APNs Auth Key (.p8) created | Push | ✅ key is on VPS (`apns:configured`) |
| Distribution cert + App Store provisioning profile | Archive | ⚠️ confirm |
| ASC app record ("Clavix", SKU, category Finance, age 4+) | TestFlight + review | ❌ per last audit, not set up |
| Support/Marketing/Privacy URLs (getclavix.com) | External TF + review | ⚠️ confirm (pages exist) |
| App Privacy "nutrition labels" | External TF + review | ⚠️ confirm in ASC |
| Export compliance answer | Upload | ⚠️ per build |

**Action:** open App Store Connect and confirm the app record, then walk `TESTFLIGHT_ADMIN_CHECKLIST_2026-06-02.md` Parts 1–3.

---

## 2. In-App Purchase / subscription (⚠️ code ready, product missing)

- **Code:** `ios/Clavis/Services/SubscriptionManager.swift` is a full StoreKit 2 implementation (load products, `purchase()`, `Transaction.currentEntitlements`, listener, restore, verify). `PaywallView.swift` exists and is wired. ✅
- **Blocker:** the IAP product `clavix_pro_monthly` ($19.99/mo, 14-day free trial, "Clavix Pro" subscription group) **must be created in App Store Connect** (admin D4–D7). Until it exists, `Product.products(for:)` returns empty and the paywall degrades to a static "$19.99" / "not available on tap" state (no crash, but no purchase). ❌
- **Paid Apps Agreement + banking + tax forms** (admin D1–D3) must be accepted before any paid product is live. ⚠️
- **Important coupling:** the **14-day trial is also broken in the backend** (see `CLAVIX_BACKEND_AUDIT_2026-06-12.md` §4). Even once the ASC intro offer exists, the app currently grants no Pro access during the trial window. Both the StoreKit intro offer *and* the backend `effective_tier` enforcement need to agree.

---

## 3. Push notifications (⚠️ server ready, unproven on device)

- APNs key configured server-side (`apns:configured`). ✅
- **0 device tokens registered, 0 pushes ever delivered.** ❌ Must be proven on a real TestFlight device: permission prompt → token stored in `user_preferences.apns_token` → test push arrives. See backend audit §5.
- The new `Clavis.entitlements` (uncommitted) currently declares **Sign in with Apple** but **not** the APNs `aps-environment` entitlement. Confirm the Push Notifications capability is still present at archive time (it may be coming from the auto-managed signing / a separate entitlement). **Verify before archiving** so push is not silently dropped from the distribution build.

---

## 4. Privacy & legal (✅ mostly done)

- `PrivacyInfo.xcprivacy` was corrected (DeviceID removed) per the 06-02/06-03 work. ✅
- Privacy Policy, Terms, and Refund pages exist (`docs/legal/`, served on getclavix.com), including the individual-distributor disclosure for PRASHAMSHA KATUWAL. ✅
- "Operated by Andover Digital LLC" appears on the auth screen. ✅
- **Remaining:** App Privacy nutrition labels must be entered in ASC (admin). With the new auth feature, the data-collection disclosure should cover **Apple/Google sign-in identifiers** (email, name, user ID). ⚠️
- No buy/sell or investment-advice language (per CLAVIX_TRUTH rules) — auth/splash copy verified clean in the 06-04 QA pass. ✅

---

## 5. 🆕 Sign in with Apple + Google (uncommitted, unverified)

This is the work in flight (see `CLAVIX_QA_AND_INPROGRESS_2026-06-12.md`). It is **complete in source but uncommitted and never built/tested**, and it adds App Store requirements.

**What exists (uncommitted):**
- `LoginView.swift` (+436 lines): "Continue with Apple" and "Continue with Google" buttons → `authViewModel.signInWithApple()` / `signInWithGoogle()`.
- `AuthViewModel.swift`: both async methods, Apple cancellation handled silently.
- `SupabaseAuthService.swift` (+109 lines): `signInWithApple(idToken:nonce:)` via `OpenIDConnectCredentials(.apple)`, `signInWithGoogle()` via `signInWithOAuth(.google, redirectTo: clavix://auth/callback)`, plus a full `AppleSignInCoordinator` (nonce + SHA256 + ASAuthorizationController).
- `Clavis.entitlements`: `com.apple.developer.applesignin = [Default]`.
- `project.pbxproj`: `CODE_SIGN_ENTITLEMENTS` set for both configs.
- `Info.plist`: `clavix` URL scheme present (for the Google OAuth redirect).

**Why this matters for the App Store:** App Store Review Guideline **4.8** requires offering **Sign in with Apple** whenever you offer a third-party login (Google). Adding both together is the correct move and keeps you compliant. ✅ (instinct)

**What is still required to make it work / ship:**
1. **Build-verify** the uncommitted changes (they have never been compiled; `AuthenticationServices` + `CryptoKit` + the entitlement are new).
2. **Commit** the work (currently only on the working tree).
3. **Apple Developer portal:** enable **Sign in with Apple** capability on App ID `com.clavisdev.portfolioassistant`.
4. **Supabase Auth dashboard:** enable the **Apple** provider (with the iOS bundle ID as the client ID/audience for native token verification) and the **Google** provider (with a Google Cloud OAuth client ID + secret).
5. **Google Cloud console:** create the OAuth client and register the `clavix://auth/callback` redirect.
6. Verify both flows on a real device (Apple sign-in needs a real device/Apple ID; Google via the web auth session).

**Risk:** shipping this half-configured = a login button that errors. Either finish + verify it before the next build, or hide the buttons behind a flag until the providers are configured.

---

## 6. Build, signing & versioning (⚠️)

- Release/archive build errors were fixed (iPhone-only target) in commits `02e9bd0`, `dbb3532`, `eea7d4b`; the **committed** state compiled green at the 06-03/06-04 checkpoint. ✅
- The **uncommitted auth changes have not been build-verified.** ❌ (do this first)
- `DEVELOPMENT_TEAM = GYMG4MQS8F`, `CURRENT_PROJECT_VERSION = 1`. Set **Marketing Version = 1.0.0** and bump the **Build Number** before each upload. ⚠️
- App Store screenshots: 5 live imagesets were added to the asset catalog (`screen_today_live`, `screen_alerts_live`, `screen_detail_live`, `screen_holdings_live`, `screen_search_live`) plus QA screenshots under `docs/AUDITS/screenshots/`. These look intended for the listing. ✅ (in progress)

---

## 7. Readiness verdict

| Track | Verdict |
|---|---|
| **Internal TestFlight (you + family)** | Reachable quickly: needs ASC record + cert/profile + first archive/upload. Trial/push/recompute can follow. |
| **External TestFlight (beta testers)** | Adds Beta App Review + full App Privacy + the auth feature finished, or auth hidden. |
| **Paid public launch** | Adds: IAP product live + Paid Apps Agreement/banking/tax, **trial enforcement fixed**, push proven on device, **recompute freshness restored**, and a tax/legal note on the individual-vs-LLC seller name. |

**Critical path to a first TestFlight build:** (1) build-verify + commit the auth work (or hide it), (2) ASC app record + distribution cert/profile, (3) bump version, (4) archive + upload. Everything else is parallelizable after the build is processing.
