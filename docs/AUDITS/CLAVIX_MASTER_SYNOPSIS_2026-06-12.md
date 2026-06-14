# Clavix Master Audit Synopsis — 2026-06-12

**Auditor:** Claude Opus 4.8 (in-session, live evidence)
**Why this exists:** Owner returned after ~1 week away and needed a full re-orientation plus a launch-blocker map. This is the index; the three detailed reports are linked below.

- Backend & data: [`CLAVIX_BACKEND_AUDIT_2026-06-12.md`](CLAVIX_BACKEND_AUDIT_2026-06-12.md)
- App Store readiness: [`CLAVIX_APPSTORE_READINESS_2026-06-12.md`](CLAVIX_APPSTORE_READINESS_2026-06-12.md)
- QA pass + work-in-progress: [`CLAVIX_QA_AND_INPROGRESS_2026-06-12.md`](CLAVIX_QA_AND_INPROGRESS_2026-06-12.md)
- Prior baseline (still useful): [`CLAVIX_FULL_AUDIT_2026-06-03.md`](CLAVIX_FULL_AUDIT_2026-06-03.md)

---

## The one-paragraph picture

The app and backend are **fundamentally healthy and close to launch**. The service is up, security is clean, and the core per-user experience (digests, alerts, owned holdings) is fresh and working today. Since you left, **one backend job quietly broke**: the daily universe recompute now fails on an upstream Finnhub rate limit, so ~69% of the tracked universe is 8–10 days stale (this mostly shows in Search/Radar, not a user's own portfolio). Two known gaps remain unfinished: the **14-day Pro trial is computed but never enforced**, and **push has never been delivered** (no device tokens). You were mid-way through two things when you stopped: a **simulator QA pass** (only 1 of 18 screens done) and a brand-new **Sign in with Apple + Google** login flow (code-complete but uncommitted, unbuilt, and providers not configured). The remaining launch work is mostly Apple admin + finishing those two threads, not core product rework.

---

## What changed while you were away (regressions)

1. 🔴 **Universe recompute started failing daily.** Last full refresh was 2026-06-02. Now ~94–100 tickers succeed/day and ~400 fail on Finnhub 429s. 352 of 507 tickers are 8+ days stale. The commit labeled "recompute hardening" (`228422b`) did not fix it.
2. 🟠 **Trial windows are now expiring.** Two June testers hit `trial_ends_at = 2026-06-15` in 3 days, and they never actually got Pro because the trial is unenforced.

Everything else is stable or improved versus the 06-03 baseline.

---

## Launch blockers, ranked

### 🔴 P0 — must fix to launch (and to make the product honest)
1. **Universe recompute freshness (backend).** Throttle / spread / cache harder / consider paid Finnhub; capture `error_json`; retry only failed tickers. *Code + ops.*
2. **Apple admin (only you can do).** App Store Connect record, `clavix_pro_monthly` IAP + 14-day intro offer, Paid Apps Agreement/banking/tax, distribution cert + profile, archive + upload. *Admin.*
3. **Finish-or-hide the new auth feature.** Either build-verify + commit + configure Supabase/Apple/Google providers, **or** hide the Apple/Google buttons behind a flag and ship email/password first. Recommend the latter for the first TestFlight. *Code + admin.*

### 🟠 P1 — fix before broader testing / paid launch
4. **Make the 14-day trial grant Pro.** Wire `effective_tier` into backend gates (`holdings`, `watchlists`, `tickers`, `access_control`) and iOS (decode `effective_tier`); auto-downgrade is then automatic.
5. **Prove push on a real device.** Token registration → stored → test push. (Cannot be done in the simulator.)
6. **Finish the simulator QA pass** (screens 2–18), re-QA the redesigned login.

### 🟡 P2 — polish
7. Backfill AMD's five NULL dimensions (also clears the 1-user portfolio-rollup failure and the empty radar).
8. Security housekeeping: move `citext` out of `public`; toggle Supabase leaked-password protection.
9. Clean orphaned `data_generation_runs` rows; add a failure alert for the recompute job.
10. Commit the untracked launch docs + screenshot assets; gitignore `supabase/.temp/`; resolve root `package.json`.

---

## Recommended next 3 sessions

**Session 1 — Restore data freshness + decide the auth path.**
- Fix the recompute (throttle/cache so it stays under Finnhub's limit; add error capture + failed-ticker resume). Re-run, confirm the universe goes green again.
- Decide: hide auth buttons for now vs finish them. If hiding, do it and unblock the build.

**Session 2 — Make the trial real + finish QA.**
- Wire `effective_tier` end to end (backend gates + iOS), test the 4th-holding paywall and verbose digest as a trial user.
- Run the remaining QA screens; fix what surfaces.

**Session 3 — Ship to TestFlight.**
- Apple admin (ASC record, cert/profile, version bump), archive + upload.
- On device: verify push token + a sandbox StoreKit purchase. Then iterate.

---

## Health snapshot (live, 2026-06-12)

| Signal | Value |
|---|---|
| `/health` | ok; apns/snaptrade/minimax/supabase all configured |
| Container | up 8 days, on latest commit `228422b` |
| Digests today | 4 / 4 active users ✅ |
| Alerts today | 21 ✅ (17,077 total, 0 ever delivered ❌) |
| Universe fresh (≤1d) | 107 / 507 |
| Universe stale (8+d) | **352 / 507** ❌ |
| Users on Pro via trial | 0 ❌ |
| Device push tokens | 0 / 5 ❌ |
| Security advisors | clean (1 low WARN) ✅ |
