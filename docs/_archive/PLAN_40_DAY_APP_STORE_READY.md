# Clavix — 40-Day App Store Ready Sprint Plan
**Target:** App Store-ready (not published) by Day 40  
**Day 14:** June 15 → Day 40: July 10–11  
**Owner:** Sansar Karki | **Delegated support:** Hermes (planning, scripts, docs, QA lists)

---

## How To Read This Plan

- **Sansar does:** Code, UI polish, video recording/editing, external account setup (Apple, Stripe, SnapTrade), final QA
- **Hermes does:** Write video scripts, draft App Store copy/privacy policy, maintain this plan, build QA checklists, draft social captions, map content calendar
- **Burst-friendly:** Days are grouped into 3-day sprints. You can compress a 3-day block into 1 intense day or spread across 3 lighter days.
- **Hard blockers in bold** — these require external approval or payment and have uncertain timelines.

---

## Phase 1: Foundation + External Unblock (Days 1–10)

Goal: Remove every external dependency that could stall later phases. Start content engine.

### Days 1–3: Apple + RevenueCat + SnapTrade Applications

| Task | Owner | Time |
|---|---|---|
| **Buy Apple Developer Program ($99)** | Sansar | 30 min |
| **Set up App Store Connect** (bundle ID: `com.clavisdev.portfolioassistant`) | Sansar | 1 hr |
| **Create RevenueCat account** + set up Clavix app + Pro product ($25/mo) | Sansar | 2 hr |
| **Submit SnapTrade developer application** | Sansar | 1 hr |
| Confirm legal entity decision (sole prop vs LLC — can defer if sole prop works) | Sansar | 30 min |
| Write script: "I'm building a credit-rating system for your stock portfolio" (TikTok #1) | Hermes | — |
| Write script: "40 days to App Store — here's my plan" (TikTok #2) | Hermes | — |

### Days 4–6: APNs + Stripe + Backend Contract Lock

| Task | Owner | Time |
|---|---|---|
| **Download APNs .p8 key from Apple Dev portal** + configure VPS | Sansar | 2 hr |
| Test push notification end-to-end (`POST /test-push` on device) | Sansar | 1 hr |
| Stripe account setup + webhook endpoint prep | Sansar | 2 hr |
| Backend: Finalize event-analysis contract across holdings/watchlist/ticker detail | Sansar | 3 hr |
| Content script: "How AI scores your portfolio from A to F" | Hermes | — |

### Days 7–9: UI Screenshot Parity + Final Spacing

| Task | Owner | Time |
|---|---|---|
| Run iOS Simulator screenshot pass against design handoff | Sansar | 3 hr |
| Fix final spacing/layout deltas (sticky headers, hero, chart tabs, driver titles) | Sansar | 3 hr |
| Validate AMD + HOOD ticker detail end-to-end | Sansar | 2 hr |
| Content script: "Day in the life of a 19-year-old building a fintech app" | Hermes | — |

### Day 10: Buffer + Plan Review

- Review Phase 1 completions, adjust Phase 2 if blockers slipped
- Hermes: Draft App Store metadata skeleton (title, subtitle, description, keywords)

---

## Phase 2: Hardening + Build-In-Public Momentum (Days 11–25)

Goal: App is functionally complete. Content engine runs 3-4x/week.

### Days 11–13: DB Cleanup + Scoring Finalization

| Task | Owner | Time |
|---|---|---|
| DB cleanup: drop legacy columns (`thesis_integrity`, `grade_reason`, `mirofish_used`, etc.) | Sansar | 2 hr |
| Run `scripts/clean_dirty_text_rows.py` on production DB | Sansar | 1 hr |
| Validate grade-history sparkline endpoint | Sansar | 2 hr |
| Re-run full S&P backfill quality check (spot-check 10 tickers) | Sansar | 3 hr |
| Content script: "The biggest lie in stock analysis apps" | Hermes | — |

### Days 14–16: SnapTrade Integration (If Approved)

| Task | Owner | Time |
|---|---|---|
| Configure SnapTrade client ID/secret on VPS | Sansar | 1 hr |
| Test brokerage OAuth flow in Simulator | Sansar | 2 hr |
| Test holdings sync endpoint (`POST /brokerage/sync`) | Sansar | 2 hr |
| iOS: Add brokerage badge to holdings rows + settings section | Sansar | 3 hr |
| If SnapTrade NOT approved yet: defer to Phase 4, replace with "manual add" polish | — | — |
| Content script: "Connecting your brokerage in 30 seconds" (or "Why I deleted Robinhood's notifications") | Hermes | — |

### Days 17–19: RevenueCat / StoreKit Wiring

| Task | Owner | Time |
|---|---|---|
| iOS: Add RevenueCat SDK + paywall sheet | Sansar | 4 hr |
| Backend: Add `/billing/webhook` Stripe handler | Sansar | 3 hr |
| Test free-vs-Pro tier enforcement (5-position limit) | Sansar | 2 hr |
| Content script: "Why this app costs $25/month" | Hermes | — |

### Days 20–22: Onboarding + Empty States + Error Handling

| Task | Owner | Time |
|---|---|---|
| Onboarding final pass: trust copy, notification permission timing, finish screen | Sansar | 3 hr |
| Empty states: Digest (first-time user), Holdings (no positions), Alerts (no alerts) | Sansar | 3 hr |
| Loading/error states: network failure, timeout, no connection | Sansar | 3 hr |
| Content script: "Behind the scenes: designing an app that doesn't suck" | Hermes | — |

### Days 23–25: Pull-to-Refresh + Haptics + App Icon

| Task | Owner | Time |
|---|---|---|
| Add pull-to-refresh on Dashboard + Holdings | Sansar | 2 hr |
| Haptic feedback on grade change alert tap | Sansar | 1 hr |
| **App icon design** (1024×1024) — outsource or use existing | Sansar | 2 hr |
| Content script: "The app icon I designed in 2 hours" | Hermes | — |

---

## Phase 3: Launch Assets + TestFlight (Days 26–35)

Goal: Everything needed for App Store submission is drafted, shot, or coded.

### Days 26–28: Screenshot Production + App Store Metadata

| Task | Owner | Time |
|---|---|---|
| Capture screenshots: 6.7" (iPhone 16 Pro Max) + 6.1" (iPhone 16) | Sansar | 2 hr |
| Screenshot text overlays (value prop on each frame) | Sansar | 2 hr |
| Finalize App Store title, subtitle, description, keywords | Hermes/Sansar | 1 hr |
| Write App Store reviewer notes | Hermes | — |
| Content script: "App Store screenshots are lowkey harder than the app" | Hermes | — |

### Days 29–31: TestFlight Internal Testing

| Task | Owner | Time |
|---|---|---|
| Upload build to App Store Connect | Sansar | 1 hr |
| Invite 5–10 internal testers (friends/family) | Sansar | 30 min |
| Draft TestFlight onboarding message | Hermes | — |
| Collect feedback + triage bugs | Sansar | ongoing |
| Content script: "I let my friends break my app for 3 days" | Hermes | — |

### Days 32–34: Privacy Policy + Legal + Trust Pages

| Task | Owner | Time |
|---|---|---|
| Finalize privacy policy (hosted on getclavix.com or inside app) | Hermes/Sansar | 2 hr |
| Add Terms of Service | Hermes | — |
| Verify legal/trust language in onboarding + Settings | Sansar | 1 hr |
| Content script: "The legal stuff nobody reads but everyone needs" | Hermes | — |

### Day 35: Pre-Submission QA Pass

- Hermes: Build QA checklist (fresh install, no network, notifications, account isolation, dark mode)
- Sansar: Run checklist, fix any P1 bugs
- Content script: "The final QA pass — 47 things I checked" | Hermes

---

## Phase 4: Final Polish + Buffer (Days 36–40)

Goal: Zero P1 bugs. Store submission is a button press away.

### Days 36–37: TestFlight Feedback Fixes

- Address any blocking feedback from internal testers
- Re-screenshot if UI changed
- Hermes: Update all App Store copy if features changed

### Days 38–39: Store Submission Prep

- Final build upload
- Screenshot upload to App Store Connect
- Metadata review
- Hermes: Draft launch announcement content (TikTok, IG, YouTube)

### Day 40: SUBMIT (or Ready to Submit)

- Press "Submit for Review" OR park at "Ready to Submit" if waiting on Stripe/SnapTrade final config
- Hermes: Deliver launch day content package (3 TikToks, 1 IG carousel, 1 YouTube script)

---

## Content Calendar (Hermes-Delegated)

**TikTok / Reels / Shorts (3–4x/week)**

| Day | Topic |
|---|---|
| 1 | "Building a credit-rating system for your portfolio" |
| 4 | "How AI scores stocks from A to F" |
| 7 | "40 days to App Store — my plan" |
| 11 | "The lie every finance app tells you" |
| 14 | "Day in the life: student founder edition" |
| 18 | "Why I charge $25/month for this" |
| 21 | "Behind the scenes: the UI that took 40 iterations" |
| 25 | "Designing the app icon" |
| 29 | "My friends broke my app (TestFlight)" |
| 33 | "47 things I checked before App Store" |
| 37 | "Launch week content" |
| 40 | "It's submitted" |

**YouTube (1x/week, 5–8 min)**

| Week | Topic |
|---|---|
| 1–2 | "Building Clavix from 0: the first 40 days" |
| 3 | "How I designed a fintech app UI (Figma → SwiftUI)" |
| 4 | "The tech stack powering my portfolio risk app" |
| 5 | "App Store review process: what actually happens" |

**IG (2x/week)**
- Carousel: "App screenshot evolution"
- Story: Daily build updates (quick phone recordings)
- Reels: Reuse best-performing TikToks

---

## Hard Blocker Risk Register

| Blocker | Phase | Mitigation |
|---|---|---|
| **Apple Dev account approval delayed** | P1 | Apply Day 1. If delayed >3 days, proceed with all other work. Can still code/test in Simulator. |
| **SnapTrade dev approval slow** | P2 | Apply Day 1. If not approved by Day 16, defer to post-App Store. App still works with manual entry. |
| **RevenueCat/Stripe tax forms** | P2 | Start account setup early. Can test with sandbox products before tax docs are finalized. |
| **Business entity complexity** | P1 | If sole proprietorship works for App Store, defer LLC to post-launch. |
| **TestFlight rejections** | P3 | Budget 2–3 days for rejection fixes (common: metadata, sign-in flow, missing demo account). |

---

## Daily Standup Format (Text Me This)

Every morning, message me:
1. What I did yesterday
2. What I'm doing today
3. Any blockers

I'll reply with today's top 3 tasks and any scripts/docs I owe you.

---

## Files Hermes Maintains

| File | Purpose |
|---|---|
| `PLAN_40_DAY_APP_STORE_READY.md` | This plan — updated weekly |
| `CONTENT_CALENDAR.md` | Detailed scripts and captions per post |
| `APP_STORE_METADATA.md` | Title, subtitle, description, keywords, reviewer notes |
| `QA_CHECKLIST.md` | Pre-submission QA steps |
| `DAILY_TASKS.md` | Rolling 3-day task list (regenerated every morning) |

---

*Plan version: 1.0 | Created: May 5, 2026 | Next review: Day 3*
