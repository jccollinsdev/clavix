# Clavix Simulator QA Pass — 2026-06-04

**Auditor:** Claude Sonnet 4.6 (interactive session with Sansar Karki)
**Goal:** Screen-by-screen simulator QA in preparation for TestFlight build.
**Build commit:** `228422bd0` — feat: 14-day trial logic, recompute hardening, radar null guard, security housekeeping
**Prior audit:** `docs/AUDITS/CLAVIX_FULL_AUDIT_2026-06-03.md` (superseded here for UI/UX findings)
**Screenshots:** `docs/AUDITS/screenshots/sim-qa-pass-2026-06-04/`

---

## Session Configuration

- **Device:** iPhone 17 Simulator
- **Simulator ID:** 22AE0AD5-B089-46A3-8393-2F947D55D0FB
- **iOS:** Simulator default
- **Build source:** `/Users/sansarkarki/Documents/Clavis/ios/Clavis.xcodeproj`
- **Scheme:** Clavis
- **Bundle ID:** `com.clavisdev.portfolioassistant`
- **API base:** `https://clavis.andoverdigital.com`
- **Test user:** `7ff5a6c5-8e49-4c2f-be1c-bdc869926699` (sansarbikramkarki@gmail.com)
- **Holdings:** AMD / AAPL / SMCI

---

## Screen Checklist

- [x] Launch / Splash ✅
- [ ] Onboarding flow
- [ ] Login / Auth
- [ ] Home / Dashboard tab
  - [ ] Portfolio grade card
  - [ ] Holdings list
  - [ ] Each holding row: ticker, price, grade badge, score
  - [ ] Alerts section
  - [ ] Digest section
- [ ] Add holding — valid ticker
- [ ] Add holding — outside universe
- [ ] Add holding — free account 4th holding paywall
- [ ] Ticker Detail — owned holding (AAPL)
  - [ ] Hero card
  - [ ] Price chart
  - [ ] Five dimensions section
  - [ ] Tap each dimension row (methodology opens)
  - [ ] News/articles section
- [ ] Ticker Detail — AMD (limited/missing dimensions)
- [ ] Search tab — Radar screener empty/loaded state
- [ ] Search tab — direct search (AAPL, AMD, invalid, outside universe)
- [ ] Watchlist tab
- [ ] Digest tab
- [ ] Alerts tab
- [ ] Settings tab
- [ ] Paywall / Pro upgrade screen
- [ ] Final full smoke test

---

## Severity Reference

- **P0** — crash, cannot log in, data/security issue, blocks launch entirely
- **P1** — major TestFlight blocker, core feature broken, paywall broken, broken nav
- **P2** — important polish/UX/data bug, fix before wider TestFlight
- **P3** — visual polish, copy, minor spacing — can defer

---

## Bug Summary Table

| # | Screen | Severity | Description | Status |
|---|---|---|---|---|
| (populated as findings are recorded) | | | | |

---

## Findings

---

## Launch / Splash

Navigation path: App cold launch (logged out)

Simulator/device:
- Device: iPhone 17 Simulator
- iOS: 26.3
- Build source: Clavis.xcodeproj / scheme Clavis
- App build: commit `228422bd0` + splash fixes
- Account: none (logged out)
- Test user: n/a

### ✅ Works
- Screen loads instantly, no delay
- CLAVIX brand name correct in nav header
- "Create account" and "Sign in" buttons both tappable and responsive
- Terms of Service and Privacy Policy links present
- "Clavix is operated by Andover Digital LLC." visible
- Risk disclaimer present and legally safe
- No Clavis internal text visible
- No investment-advice language

### ❌ Bug / wrong
- (none)

### ⚠️ Looks off (visual only, not broken) — FIXED
- **Feature card was a single static "Morning Report" card** — not communicating full app value
  - Fix: replaced with 4-slide auto-advancing carousel (Morning Report / Five Dimensions / Bond Grades / Grade-change Alerts)
  - Verification result: **fixed** ✅
- **Em dashes in body copy** — user preference to remove
  - Fix: replaced `— macro, sector, financials, news, and volatility —` with colon + period split
  - Verification result: **fixed** ✅
- **Footer order** — "By continuing…" was below risk acknowledgment text
  - Fix: swapped order; terms link now appears first
  - Verification result: **fixed** ✅

### 🧪 Notes / questions
- Carousel auto-advances every 3.5s; swipeable. 4 dots visible below the card.
- Screenshot: `01-launch-splash-v2.jpg`

---
<!-- Next screens appended below -->

