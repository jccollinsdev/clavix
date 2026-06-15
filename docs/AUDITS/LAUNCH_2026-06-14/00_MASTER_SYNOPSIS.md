# Clavix Launch-Readiness Audit, Master Synopsis (2026-06-14)

**Auditor:** Claude Opus 4.8 (in-session, live evidence)
**Why this exists:** Owner is preparing the first TestFlight beta (one tester lined up) and wants a full readiness picture before that: product vs spec, ICP fit, backend health and management, data freshness, endpoint responsiveness, frontend performance and scale, monetization and business viability, and every way the app can fail. This is the index. The detailed reports are linked below.

This audit supersedes the 2026-06-12 set. Two of the three biggest blockers from 06-12 have since been fixed in code and partly proven live.

---

## Sub-reports

1. [PRD vs build, and ICP fit](01_PRD_VS_BUILD_AND_ICP.md)
2. [Backend health and data freshness](02_BACKEND_DATA_FRESHNESS.md)
3. [Backend management and operations runbook](03_BACKEND_MANAGEMENT_RUNBOOK.md)
4. [Frontend responsiveness and scale](04_FRONTEND_PERF_SCALE.md)
5. [Monetization and business audit](05_MONETIZATION_BUSINESS.md)
6. [Failure modes, observability, and TestFlight readiness](06_FAILURE_MODES_TESTFLIGHT.md)
7. [Roadmap to launch](../../ROADMAP_TO_LAUNCH.md)

---

## The one-paragraph picture

The service is healthy and the core per-user loop (digest, alerts, owned-holding grades) works and is fresh. Since 06-12 you fixed the two worst things: the Finnhub rate-limit wall that was leaving 69% of the universe stale is gone (a throttle-to-60/min fix that is now proven by Saturday's full recompute succeeding), and the Apple/Google sign-in feature is committed. The universe went from 352 stale tickers to 4. What stands between you and a credible launch now is not outages, it is **three quieter, trust-level problems** plus **Apple admin you have not started**. The trust problems: per-ticker grades flicker day to day (AAPL went A, BBB, BBB, A, A across six days), the snapshot table carries two score columns that disagree by up to 35 points plus duplicate rows, and ETFs (which your ICP holds heavily) are almost entirely missing from the universe. None of these are visible at the aggregate level, which is why earlier audits called the data healthy; they show up the moment one sophisticated user watches one position for a week, which is exactly your ICP's behavior. On the business side the economics are excellent (break-even is roughly five paying subscribers against about $68/month of app infrastructure), but you have chosen a "free trial only, no perpetual free" model that the current build does not implement, so the gating needs a focused rework.

---

## Readiness verdict

| Track | Verdict | Gap |
|---|---|---|
| Internal TestFlight (you + the one tester) | Reachable in days | Apple admin (status unknown), build-verify the committed auth, archive and upload |
| A beta that tests everything you asked for (UX, paywall, push, Apple/Google) | About 2 to 3 focused sessions | Configure auth providers, create the IAP product, fix trial-to-Pro gating, prove push on device |
| Paid public launch | After the trust fixes | Grade stability, score-column unification, ETF coverage, observability, paid data tiers |

You are close on plumbing and further than you think on features. The work left is mostly correctness, Apple paperwork, and finishing two threads you already started.

---

## Top findings, ranked

### Fixed since 06-12 (verified live)
- **Universe freshness restored.** 498 of 507 tickers are 1 day old, only 4 are 8+ days stale (was 352). Root-cause fix (`a7d32eb4d`, throttle Finnhub to 60/min) is deployed and proven by the 06-13 full recompute completing 503/503 with zero failures, where the 06-06 run had failed 372.
- **Sign in with Apple and Google committed** (`a09f5563d`). Still needs provider configuration and on-device verification.
- **Account deletion made FK-safe** (`512c5ff0c`), which cleaned out old test accounts (the DB is now effectively a clean slate: one fresh tester, in trial as of today).

### Red, blocks an honest launch
1. **Grade flicker / dimension instability.** Per-ticker grades and dimension scores swing day to day in ways the methodology says they should not (financial health is supposed to be quarterly and slow; it bounces 62, 80, 88, 62). The anti-flicker hysteresis rule in the truth doc is not holding. This is the single most direct threat to the "ratings you can trust" promise. See report 2.
2. **Two disagreeing score columns plus duplicate rows.** `safety_score` and `composite_score` differ by up to 35 points on the same row (AMD 06-11: 83.5 vs 48.0), and AMD has two different snapshots for the same date. Any surface that reads the wrong column shows an incoherent score next to its grade. See report 2.
3. **ETFs almost entirely missing.** Only SPY and VOO have snapshots (both stale); QQQ, the sector SPDRs, AGG, BND, SCHD, VTI, IWM have none. The spec promises the top 50 ETFs. Your ICP holds ETFs. See reports 1 and 2.
4. **Apple admin not started / status unknown.** No confirmation of an App Store Connect record, IAP product, or Paid Apps Agreement. This is the longest-lead critical-path item and only you can do it. See report 6.

### Orange, blocks the monetization and push tests you want in the beta
5. **Trial does not grant Pro, and you want a trial-only model the build does not implement.** Feature gates read the raw `subscription_tier == "free"`, so a trial user is gated as free. You chose "free trial only, no perpetual free," which needs gating rework plus a hard paywall-on-expiry state. See report 5.
6. **Push has never been delivered.** Server key is configured, but zero device tokens and zero delivered alerts. Only provable on a physical device. See reports 2 and 6.
7. **No client-side observability.** The iOS app has no crash reporter and no analytics. If the beta build crashes for your tester, you will not know why. Backend has Sentry hooks (confirm the DSN is set). See report 6.

### Yellow, polish and scale
8. Frontend cold-launch slowness comes from an in-memory-only cache (every relaunch refetches everything) and wasted brokerage network calls on every holdings load despite brokerage being off. See report 4.
9. Single small droplet (1.9 GB RAM), no healthcheck-based auto-recovery, no uptime alerting, no failure alert on the recompute job. Fine for beta, plan before scale. See report 3.
10. Data APIs (Finnhub, Polygon) are on free tiers. Freshness currently survives only by throttling, which makes the recompute take about 140 minutes and stay fragile. Budget paid tiers before public launch. See reports 3 and 5.

---

## Live health snapshot (2026-06-14, Sunday)

| Signal | Value |
|---|---|
| `/health` | ok; apns, snaptrade, minimax, supabase all configured |
| Edge latency | `/health` and `/ping` about 50 to 75 ms; authed routes correctly 401 |
| Container | up via clean redeploys tonight, RestartCount 0, no OOM, no crash loop |
| Host | 1.9 GB RAM, about 1.4 GB available; disk 27% used; CPU idle |
| Universe fresh (<= 1 day) | 498 / 507 (was 155 / 507 on 06-12) |
| Universe stale (8+ days) | 4 |
| Grade bands (latest per ticker) | AA 12, A 320, BBB 135, BB 30, B 9, CCC 1 |
| Digests today | 3, latest 21:28 UTC |
| Alerts today | 11, delivered 0 |
| Users | 1 (fresh tester, trial 2026-06-14 to 2026-06-28) |
| Device push tokens | 0 |
| ETFs with any snapshot | about 2 (SPY, VOO), stale |
| Security advisors | clean (1 low warning, `citext` in public schema) |

---

## What to do next (the short version, full detail in the roadmap)

1. Find out where Apple actually stands (open App Store Connect). This unblocks the longest lead time.
2. Fix the trust trio: grade stability, score-column unification, ETF backfill. These are what make the product honest for your ICP.
3. Decide and implement the trial-only gating, create the IAP product, and wire trial-to-Pro so the paywall and purchase are testable.
4. Add a crash reporter and confirm backend Sentry, then archive a build and prove push and a sandbox purchase on a real device.
