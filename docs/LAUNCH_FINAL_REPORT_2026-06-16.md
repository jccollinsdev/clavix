# Clavix — Final Launch Readiness Report (2026-06-16)

**Author:** Claude (live-evidence audit, in-session)
**Basis:** verified against production today — VPS container, `/health`, live Supabase queries, endpoint probes. Supersedes the 2026-06-14 audit set for current-state facts.
**Launch model (locked):** free trial only, no perpetual free. Path = **internal TestFlight first** (you + your mom as tester), craft App Store copy/screenshots *during* TestFlight, then paid public launch.

---

## 1. Verified live state (today)

| Signal | Value | Verdict |
|---|---|---|
| `/health` | ok; apns, snaptrade, minimax, supabase all configured | 🟢 |
| `/ping` latency | 200 in 114 ms | 🟢 |
| Authed routes (`/preferences`) | 401 without token | 🟢 correct |
| `/analytics/event` (new) | 401 without token | 🟢 live |
| Container | running, **RestartCount 0**, stable ~15h | 🟢 |
| Deployed commit | `db086f9` (latest `main`) — backend is up to date | 🟢 |
| Backend Sentry DSN | **SET** on VPS | 🟢 error tracking live |
| iOS Sentry | SDK added + DSN in both xcconfig files | 🟢 (needs archive build to prove) |
| Migrations (06-15 ×5) | **all applied** to prod | 🟢 |
| Score columns | max disagreement **7.8** (was 35), **0 duplicate** rows, unique constraint present | 🟢 fixed |
| Launch ETFs (17) | QQQ, all XL* SPDRs, AGG, BND, VTI, IWM, SCHD → **all 1 day fresh** | 🟢 fixed |
| Recompute | today's run mid-flight, **565 jobs completed**, 1 failed yesterday, throttle holding | 🟢 |
| Universe freshness | 313 fresh today + run still in progress; only **4** truly stale (8d+) | 🟢 |
| Security advisors | 1 benign WARN (`citext` in public schema) | 🟢 |
| **Grade flicker** | AAPL still flips **A↔BBB day-to-day** (financial_health now frozen, but macro/volatility/sector still bounce + weak hysteresis at boundary) | 🔴 **still open** |
| SPY / VOO | stale 15 days (not in active refresh set) | 🟡 |
| Push device tokens | 0 (only testable on a real device build) | ⏳ pending device |
| Users | 2 | — |

**Bottom line:** Backend is healthy, fast, deployed, observable, and the 06-15 data-trust fixes (score unification, ETFs, dedupe, dead-column drop, fundamentals freeze) are confirmed live. **One trust issue remains open in code (grade flicker)**, and the rest of the path to launch is Apple paperwork + a device build. You are very close on plumbing.

---

## 2. CODE ITEMS — things I can do via MCP / CLI / coding (no Apple account needed)

### C1. Grade flicker / hysteresis at the grade boundary — 🔴 HIGH (the #1 trust fix)
The financial_health freeze worked (AAPL = 62 constant on recent days). But the **grade still flips A→BBB→A** because:
- `macro_exposure_dim` swings hard (35 → 85 → 100 across days), volatility and sector also bounce.
- The composite hovers at the A/BBB threshold (~70) and a 2-point move (68.4→70.6) flips the grade. The truth-doc hysteresis band is not holding at write time.

**Fix:** (a) apply the same smoothing used elsewhere to the slow dimensions (macro especially), and (b) enforce a grade-hysteresis buffer so the composite must clear the threshold by a margin before the letter grade changes. **Constraint:** CLAUDE.md forbids changing scoring formulas without verifying the output distribution on prod data first, so this is a focused, verified task — not a one-liner. This is the most important thing to fix before real users watch a single ticker for a week. *I can do this; say the word.*

### C2. SPY / VOO stale — 🟡 LOW (quick)
The two most-held ETFs in existence have 15-day-old snapshots; they're known tickers but not in the active refresh set. Add them to `is_active` / the refresh universe and trigger a refresh. ~10 minutes. *I can do this now.*

### C3. Archive-verify the never-archived code — 🟡 MEDIUM
Sign in with Apple/Google, Sentry init, the analytics client, and `ExpiredPaywallView` have only ever been **simulator-built**, never archived for device/Release. Compile issues (entitlements, `aps-environment` not dropped) surface only at archive time. This overlaps with the device build below.

> Note: everything else in `docs/REMAINING_CODE_WORK.md` (ETF backfill, iOS Sentry wiring, expired-trial lock, trial tier badge, foreground tier refresh, dead-column drop, funnel analytics, disk cache, REFRESH_CONCURRENCY env var) is **implemented and verified live**. No re-work needed.

---

## 3. ADMIN + CODE — needs your Apple account first, then a build/code step

### AC1. Device build (unblocks push + IAP testing) — **the current bottleneck**
The CLI can't provision because your Apple Developer account isn't authenticated in the terminal. One-time fix in Xcode:
1. `open ios/Clavis.xcodeproj`
2. Target **Clavis** → **Signing & Capabilities** → select your Team (`97N24DN2Z2`), keep "Automatically manage signing" on.
3. Select **Sansar's iPhone**, press **Run**.
After that, CLI builds work too, and push-token registration + sandbox purchase become testable on-device.

### AC2. Apple/Google sign-in on-device verification
Code is done and both providers are **enabled in Supabase** (verified). Apple Sign-In can't complete in the simulator (no Apple ID) — needs the device build (AC1) to confirm end-to-end, then it's done.

### AC3. Archive + upload to TestFlight
After AC1, archive and upload. Internal TestFlight needs **no App Review and no screenshots** — fastest path to your tester. Set Marketing Version 1.0.0, bump build number, confirm Push Notifications capability survives archive.

---

## 4. ADMIN ONLY — only you can do these (console/forms, I cannot)

**Longest lead — do first:**

### A1. App Store Connect reconnaissance (today)
Confirm, and write down: app record for Clavix exists? Membership active? Bundle ID `com.clavisdev.portfolioassistant` registered? This unblocks everything downstream.

### A2. Paid Apps Agreement + banking + tax  ← *your Thursday task (adding your mom)*
This is the gate for any real/sandbox purchase. You noted you need to add your mom as a user to complete the tax forms — that's this item. Until this is accepted, IAP purchases can't be tested for real.

### A3. Create `clavix_pro_monthly` IAP at $19.99
App Store Connect → Monetization → Subscriptions → group "Clavix Pro" → product ID **`clavix_pro_monthly`** (must match the StoreKit code exactly), 1-month duration, $19.99, US base price, English localization, review screenshot. Set to "Ready to Submit." (Full steps are in my previous message.)

### A4. Enroll in Apple Small Business Program
15% commission instead of 30% — roughly doubles your net per subscriber. One form.

### A5. Toggle leaked-password protection
Supabase Dashboard → Auth → Providers → Email. One toggle, security baseline.

### A6. Add tester(s) to internal TestFlight
App Store Connect → Users → add your mom (and yourself) as internal testers. No Beta App Review.

**During TestFlight (not blockers for the internal build):**

### A7. App Store listing assets
Screenshots (you have a set captured), listing copy, App Privacy nutrition labels (declare Apple + Google sign-in identifiers), export compliance answer, age rating, support + privacy URLs (getclavix.com). This is the work you do *while* the beta runs.

---

## 5. The honest critical path (shortest route to a tester)

1. **A1** — confirm Apple status (today; longest lead). *Admin*
2. **AC1** — device build via Xcode signing. *Admin+code*
3. **C1** — fix grade flicker before real eyes watch a ticker. *Code (I can do)*
4. **AC3** — archive + upload, **A6** add tester → tester has the app. *Admin+code / admin*
5. Then **A2 + A3** (Paid Apps + IAP) to test the purchase, **on-device push** check, and you're in a full "tests everything" beta.

Everything after that (App Store listing, public submission, paid data tiers) is sequencing, not discovery.

---

## 6. What I recommend doing right now (this session)
- **C2 (SPY/VOO)** — I can fix immediately.
- **C1 (grade flicker)** — the single most valuable code fix left; I can do it carefully with a prod-distribution check per the CLAUDE.md rule. This is what makes "ratings you can trust" actually true for your ICP.

The rest waits on your Xcode signing (AC1) and your Apple console work (A1–A6), which are genuinely yours to do.
