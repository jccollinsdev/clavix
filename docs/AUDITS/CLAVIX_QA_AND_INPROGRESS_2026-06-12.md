# Clavix QA Pass Status & Work-In-Progress — 2026-06-12

**Auditor:** Claude Opus 4.8 (in-session)
**Purpose:** Reconstruct exactly where the simulator QA pass stopped, what was completed, what remains, and what was being built afterward (the uncommitted auth work), so the owner can resume after ~1 week away.

---

## 0. Where things actually stand

You started a **screen-by-screen simulator QA pass** on 2026-06-04 (`CLAVIX_SIMULATOR_QA_PASS_2026-06-04.md`). It got through **only the first screen (Launch / Splash)** before pausing. Then work shifted to building a **Sign in with Apple + Google** login flow, which is **fully written but uncommitted and never compiled/tested**.

So two threads are open:
- **Thread A — QA pass:** ~1 of 18 screens done.
- **Thread B — Auth feature:** code-complete on the working tree, not built, not committed, providers not configured.

The login redesign (Thread B, +436 lines in `LoginView.swift`) also **supersedes the "Login / Auth" item** in the QA checklist, so that screen must be re-QA'd against the new UI once it builds.

---

## 1. QA pass — completed

**Launch / Splash (✅ done, with fixes):**
- Verified: instant load, correct CLAVIX branding, Create-account / Sign-in buttons responsive, Terms + Privacy links present, "operated by Andover Digital LLC" visible, risk disclaimer present and safe, no internal "Clavis" text, no investment-advice language.
- Fixed this session: static feature card → 4-slide auto-advancing carousel (Morning Report / Five Dimensions / Bond Grades / Grade-change Alerts); removed em dashes from body copy (owner preference); reordered footer so the terms link comes first.
- Screenshot: `docs/AUDITS/screenshots/sim-qa-pass-2026-06-04/01-launch-splash-v2.jpg`.

No bugs were logged in the summary table (it was left as the template row).

---

## 2. QA pass — remaining (not started)

Every other screen in the checklist is unchecked. In priority order for a launch-blocking pass:

**P0 / core flows**
- [ ] Onboarding flow (note: onboarding copy was redesigned earlier; re-verify the trust layer + the brokerage "coming soon" copy is feature-flagged off)
- [ ] **Login / Auth — must be re-done against the new Apple/Google UI** (Thread B), once it builds
- [ ] Home / Dashboard: portfolio grade card, holdings list, per-row (ticker/price/grade/score), alerts section, digest section
- [ ] Add holding — valid ticker
- [ ] Add holding — **free account 4th-holding paywall** (this exercises the tier gate; see trial note below)
- [ ] Add holding — outside universe ("Add as untracked" flow; per backend audit this path may still be unconnected in the UI)
- [ ] Ticker Detail — owned holding (AAPL): hero, price chart, five dimensions, tap each dimension → methodology, news/articles
- [ ] **Ticker Detail — AMD** (known to render an empty radar: all five dimensions are NULL; backfill or hide radar)

**P1 / secondary**
- [ ] Search tab — Risk Radar screener (empty + loaded; this is the new hero feature, endpoint is deployed)
- [ ] Search tab — direct search (AAPL, AMD, invalid, outside-universe)
- [ ] Watchlist tab
- [ ] Digest tab (verbose vs standard — verbose is a Pro feature, gated by tier)
- [ ] Alerts tab
- [ ] Settings tab
- [ ] Paywall / Pro upgrade (graceful "not available" until the ASC IAP product exists)
- [ ] Final full smoke test

**Cross-cutting things to watch during the pass**
- **Tier/trial:** the 4th-holding paywall and verbose-digest gating will currently behave as "everyone is free" because the trial is not enforced (see backend audit §4). Decide whether to fix the trial *before* this QA pass so the paywall paths are testable as intended, or to test as free-only for now.
- **Universe staleness:** Search/Radar results for arbitrary S&P names may show grades up to ~10 days old (backend audit §3). Owned holdings are fresh.
- **Simulator limitation:** push registration cannot be verified in the simulator; defer to a real device.

---

## 3. Work-in-progress — the uncommitted auth feature (Thread B)

**Uncommitted working-tree changes (9 files, +460/−155):**

| File | Change |
|---|---|
| `Views/Auth/LoginView.swift` | +436 lines: redesigned login with "Continue with Apple" + "Continue with Google" buttons |
| `Services/SupabaseAuthService.swift` | +109: `signInWithApple(idToken:nonce:)`, `signInWithGoogle()`, full `AppleSignInCoordinator` (nonce/SHA256/ASAuthorizationController) |
| `ViewModels/AuthViewModel.swift` | +34: `signInWithApple()` / `signInWithGoogle()`, silent Apple-cancel handling |
| `Resources/Clavis.entitlements` | **new** — `com.apple.developer.applesignin = [Default]` |
| `Clavis.xcodeproj/project.pbxproj` | `CODE_SIGN_ENTITLEMENTS` wired for both build configs |
| `ViewModels/OnboardingViewModel.swift`, `ViewModels/AlertsViewModel.swift`, `Views/Digest/MorningReportView.swift`, `Views/Settings/SettingsView.swift` | smaller edits (1–22 lines each) |

**State:** code-complete, but:
- ❌ never compiled (new `AuthenticationServices` / `CryptoKit` imports + entitlement)
- ❌ not committed
- ❌ Supabase Apple + Google providers not configured
- ❌ Apple Developer "Sign in with Apple" capability not enabled on the App ID
- ❌ Google Cloud OAuth client not created

**To resume Thread B (in order):**
1. Build-verify in the simulator (catch compile errors from the new imports/entitlement).
2. Configure Supabase Auth providers (Apple with bundle-ID audience; Google with OAuth client) + Google Cloud OAuth client + `clavix://auth/callback` redirect.
3. Enable Sign in with Apple on the App ID (Apple Developer portal).
4. Test both flows on a real device (Apple sign-in needs a device + Apple ID).
5. Commit.
6. Re-QA the Login/Auth screen.

Until 1–4 are done, the buttons will error on tap. If you want to ship a TestFlight build sooner, hide the Apple/Google buttons behind a flag and fall back to the existing email/password auth, then finish this thread in parallel.

---

## 4. Other uncommitted / untracked items

- `package.json` + `package-lock.json` at repo root (untracked) — confirm intent (Supabase CLI / tooling?), commit or gitignore.
- `supabase/.temp/` (untracked) — Supabase CLI scratch; should be gitignored.
- `docs/LAUNCH/` (4 files) and the two `docs/AUDITS/*2026-06-02/03/04*` docs are untracked — commit them so the launch plan is in history.
- 5 live screenshot imagesets in `Assets.xcassets` (untracked) — intended for the App Store listing; commit.

---

## 5. Suggested resume order

1. **Decide:** finish the auth feature now, or hide it and ship email/password first. (Recommend hiding it for the first internal TestFlight, finishing in parallel — it removes a configuration dependency from the critical path.)
2. Build-verify the working tree (whichever path), commit the launch docs + assets.
3. Resume the simulator QA pass screens 2–18.
4. In parallel, fix the trial enforcement so the paywall/verbose-digest QA items are meaningful.
