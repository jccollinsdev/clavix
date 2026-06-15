# Report 6: Failure Modes, Observability, and TestFlight Readiness (2026-06-14)

You asked to think about every way the app could go wrong, how you will track it, whether your tester can experience everything (including the paywall), and whether to load App Store screenshots now.

---

## 1. Observability: today you are flying blind on the client

- **The iOS app has no crash reporter and no analytics.** A grep for Sentry, Crashlytics, Firebase, Amplitude, Mixpanel, PostHog, and Bugsnag in the iOS sources returns nothing. If the beta build crashes on your tester's phone, you get no stack trace, no breadcrumb, nothing. For a beta whose entire purpose is to learn what breaks, this is the most important gap to close before you hand over a build.
- **The backend has Sentry hooks** in `main.py` and `config.py`. Confirm the DSN is set in the container and that a test error actually reaches Sentry. If it does, your server side is covered.

**Do before the beta build:**
- Add a crash reporter to iOS (Sentry has a clean SwiftUI SDK; Firebase Crashlytics is the free alternative). At minimum capture crashes and unhandled errors.
- Add lightweight event analytics for the funnel you care about: app open, onboarding complete, holding added, paywall shown, trial started, purchase attempted, purchase succeeded or failed, push permission granted. Without these you cannot tell whether the tester reached the paywall or why a purchase did not happen.
- Confirm backend Sentry receives events and tag releases on deploy.

---

## 2. Failure modes, and how each is detected

| # | Failure | Likelihood | Blast radius | Detected by today | Add |
|---|---|---|---|---|---|
| 1 | Recompute fails, universe goes stale | Medium (fragile throttle) | Search and Radar show old grades | Nobody, until a human looks | Job-failure alert + freshness SLO (report 3) |
| 2 | Backend hangs (not crashes) | Low | Whole app unusable | Nobody | External `/health` uptime monitor (report 3) |
| 3 | Droplet dies | Low | Full outage, no failover | Nobody | Uptime monitor + DO backups + rebuild runbook |
| 4 | iOS crash on the tester's device | Medium (new auth, large views) | That user blocked | Nobody | iOS crash reporter (section 1) |
| 5 | Push never arrives | High right now | Core alert value missing | Visible (0 delivered) | On-device token + test push (section 4) |
| 6 | Trial does not unlock Pro | Certain today | Tester cannot experience Pro | Known | Wire trial-to-Pro (reports 2, 5) |
| 7 | Purchase cannot complete | Certain without ASC product | Cannot test monetization | Known | Create IAP product or use a StoreKit config file |
| 8 | Auth button errors (providers not configured) | High | Login blocked | Nobody | Configure providers or hide buttons (section 4) |
| 9 | Grade flicker erodes trust | Active now | Silent churn | Nobody | Fix stability (report 2) + analytics on retention |
| 10 | Score column mismatch shown to user | Possible | Incoherent UI | Nobody | Unify score column (report 2) |
| 11 | Data-API quota exhausted at scale | Future | Freshness fails | Partial (429 logs) | Paid tiers + alert on 429 rate |
| 12 | Upstream news source blocked (saw a 451 from Jina) | Low | One enrichment source degraded | Logs only | Fallback already exists; monitor error rate |

The pattern across this table: most failures are currently detected by "you happen to open the app." The three additions in report 3 (uptime monitor, job-failure alert, confirmed Sentry) plus an iOS crash reporter close most of the detection gaps cheaply.

---

## 3. Can your tester actually experience everything? Honest per-feature answer

You chose "all of the above" for the beta (UX, monetization, push, Apple/Google). Here is what works on a TestFlight device today versus what must be done first.

| Feature | Experienceable now? | What is required first |
|---|---|---|
| Core UX (digest, holdings, grades, drill-down, search, radar) | Yes | Build-verify and upload |
| Email/password auth | Yes | Nothing |
| Apple/Google sign-in | No | Configure Supabase Apple and Google providers, enable Sign in with Apple on the App ID, create the Google OAuth client. Until then the buttons error. Either finish this or hide the buttons for the first build |
| Paywall (seeing it) | Yes, partially | It shows, but the purchase button stays disabled until an IAP product exists |
| Trial unlocking Pro | No | Fix trial-to-Pro gating (reports 2, 5). Today the tester is gated as free during trial |
| Actual purchase (sandbox) | No | Create `clavix_pro_monthly` in App Store Connect, accept the Paid Apps Agreement, test with a sandbox account. A StoreKit configuration file can test the purchase UI locally without ASC, but not the real sandbox flow |
| Push notifications | No | Prove on a physical device: permission prompt, token stored in `user_preferences.apns_token`, a test push delivered. Cannot be done in the simulator |

So for the tester to experience the full set you listed, the pre-beta work is: configure the auth providers, create the IAP product and accept the Paid Apps Agreement, fix trial-to-Pro gating, and verify push on the device. That is the same list the roadmap sequences. If you want a faster first build to validate UX only, hide the auth buttons, ship email/password, and follow with monetization and push.

---

## 4. The three on-device proofs you cannot skip
1. **Push:** install on a real iPhone, accept notifications, confirm a token lands in `user_preferences.apns_token`, send a test push, confirm arrival. This is the only way to clear the "0 delivered" status.
2. **Purchase:** with the IAP product live (or a StoreKit config file for the UI), run a sandbox purchase end to end and confirm the entitlement flips the app to Pro and survives a restart and a restore-purchases.
3. **Auth:** if shipping Apple/Google, complete both flows on a real device (Apple sign-in needs a device and Apple ID).

---

## 5. App Store screenshots: should you load them now?

Yes, but understand what it does and does not do for you.
- **For internal TestFlight** (you plus your one tester via App Store Connect Users), you do **not** need screenshots or App Review at all. You can upload a build and add the tester immediately. So screenshots are not blocking your first beta.
- **For external TestFlight** (a public link or testers outside your team) you need Beta App Review, which wants the basic metadata and is lighter than full review.
- **For the public App Store listing** you need the full screenshot set (6.7-inch and 6.5-inch at least), and yes, doing this early is worth it: you already added five live image sets to the asset catalog (`screen_today_live`, `screen_alerts_live`, `screen_detail_live`, `screen_holdings_live`, `screen_search_live`) plus QA screenshots, so the raw material exists. Loading them into App Store Connect now means the listing is ready and you are not scrambling at submission. It also forces you to look at the app the way a prospective buyer will, which often surfaces polish issues.
- One caveat: screenshots must reflect the real app and must not imply investment advice or guaranteed outcomes (Apple is strict on finance apps, and your own truth doc bans advice language). Use the live, clean screens you already captured.

Recommendation: load the screenshots and the listing metadata when you create the App Store Connect record (you need the record anyway). It is low effort now and removes a task from the critical path later. It does not gate the internal beta.

---

## 6. Observability and failure-mode punch list
- Add an iOS crash reporter before the beta build (highest priority here).
- Add funnel analytics (open, onboarding, add holding, paywall shown, trial start, purchase result, push opt-in).
- Confirm backend Sentry DSN is set and receiving, tag releases on deploy.
- Add the uptime monitor and job-failure alert from report 3.
- Decide auth path for the first build (finish providers, or hide buttons).
- Create the IAP product (or a StoreKit config file) so the purchase flow is testable.
- Load the App Store screenshots and metadata when you create the ASC record.
