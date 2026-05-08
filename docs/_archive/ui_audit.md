# Clavis iOS — UI/UX Audit (Pre-TestFlight)

**Date:** 2026-04-26
**Scope:** Every iOS screen, the design system, and shared view models
**Goal:** Identify everything that prevents the app from feeling like a single, trustworthy fintech product before TestFlight submission
**Out of scope:** Net-new features, redesigns, marketing site, backend behavior

---

## 1. Executive Summary

The app has **strong foundations**: a real design system (`ClavisDesignSystem.swift`), a coherent dark color palette, a defined risk-grade scale, and dual-typeface typography (Inter for UI text, JetBrains Mono for numbers). The hero components — `ClavixGauge`, `GradeTag`, `RiskBar`, `ClavisLoadingCard` — are well-built.

But the screens feel like they were assembled in waves. The most visible problem is **design-system fragmentation**: two parallel header systems coexist (`CX2NavBar` vs `ClavixPageHeader`), section labels are written three different ways, and "filter pills" are re-implemented from scratch in three different files. On top of that, **backend language has leaked into user-facing copy** ("SnapTrade", "shared ticker cache", "coverage being assembled", raw `error.localizedDescription` strings, `analysis_state` capitalized at runtime), and a handful of MVP placeholders ("Pending", "v1.0.0", `—` em-dashes) make the product feel unfinished.

None of this requires redesign. Almost every issue is a copy fix, a token swap, or a delete-and-replace-with-existing-component. Fixing them is high-leverage and low-risk.

**Top three pre-TestFlight blockers:**

1. **Remove all "SnapTrade" references from user-facing copy** ([OnboardingContainerView.swift:394](ios/Clavis/Views/Onboarding/OnboardingContainerView.swift:394), [SettingsView.swift:108](ios/Clavis/Views/Settings/SettingsView.swift:108)). Users connect *their brokerage*, not a third-party SaaS.
2. **Stop exposing raw backend errors** to users. Replace every `error.localizedDescription` passthrough with a one-line, user-readable explanation + a retry CTA.
3. **Consolidate the two header systems and the three section-label styles.** Pick one header (recommend `ClavixPageHeader`) and one section label (recommend `CX2SectionLabel`). Delete the duplicates.

Everything else is polish. The bones are solid.

---

## 2. Design-System Findings

### 2.1 Component duplication (same job, multiple components)

| Job | Components in use | Recommendation |
|---|---|---|
| Top of screen header | `CX2NavBar`, `ClavixPageHeader`, `ClavisTopBar`, ad-hoc back buttons | **Keep `ClavixPageHeader`** for top-level tabs, **`CX2NavBar`** for pushed detail screens. Delete `ClavisTopBar`. |
| Section label | `CX2SectionLabel`, `ClavisSectionHeader`, inline `Text(...).uppercased()` | **Keep `CX2SectionLabel`** (one-line) and `ClavisSectionHeader` (with subtitle/accessory). Delete inline duplicates. |
| Primary CTA | `ClavisPrimaryButton`, `.buttonStyle(.borderedProminent)` | **`ClavisPrimaryButton` only.** `.borderedProminent` is the default fallback that crept into empty-state cards. |
| Inline secondary action | `ClavisSmallButton`, custom pills with `.overlay(RoundedRectangle...)`, `.buttonStyle(.bordered)` | **`ClavisSmallButton` only.** Add a `kind: .filter` variant for the filter-pill use case. |
| Empty state card | `DashboardEmptyStateCard`, `HoldingsEmptyState`, `AlertsEmptyStateCard`, `DigestEmptyStateCard` (all locally defined) | Promote to a shared `ClavisEmptyState(icon:title:body:cta:)` component. |
| Error card | `DashboardErrorCard`, `DigestErrorCard`, raw `Text(error)` blocks, `.alert("Error", ...)` | Promote to a shared `ClavisErrorCard(title:body:retry:)`. |
| Filter pill | Re-implemented in [HoldingsListView.swift:630](ios/Clavis/Views/Holdings/HoldingsListView.swift:630) and [AlertsView.swift:177](ios/Clavis/Views/Alerts/AlertsView.swift:177) | Add a shared `ClavisFilterPill` (or `.filter` variant of `ClavisSmallButton`). |

### 2.2 Tokens being bypassed

Every line below uses a hardcoded value where a token already exists.

**Typography (should use `ClavisTypography.*`):**

| File | Line | Hardcoded | Replace with |
|---|---|---|---|
| `Auth/LoginView.swift` | 27 | `.custom("Inter", size: 20).weight(.bold)` | `ClavisTypography.brandWordmark` |
| `Dashboard/DashboardView.swift` | 101 | `.system(size: 64, weight: .bold, design: .monospaced)` | new `ClavisTypography.portfolioHero` (52pt already defined as `portfolioScore`) |
| `Dashboard/DashboardView.swift` | 109 | `.system(size: 15, weight: .regular)` | `ClavisTypography.body` |
| `Tickers/TickerDetailView.swift` | 553 | `.system(size: 44, weight: .bold, design: .monospaced)` | new `ClavisTypography.tickerHero` |
| `Digest/DigestView.swift` | 272 | `.system(size: 22, weight: .semibold)` | `ClavisTypography.h2` |
| `Digest/DigestView.swift` | 311 | `.system(size: 14, weight: .regular)` | `ClavisTypography.bodySmall` |
| `Settings/SettingsView.swift` | 399 | `.system(size: 15, weight: .regular)` | `ClavisTypography.body` |
| `Onboarding/OnboardingContainerView.swift` | 115 | `.system(size: 30, weight: .bold)` | `ClavisTypography.h1` (28pt) or new `displayTitle` |
| `PositionDetail/PriceChartView.swift` | 28, 31, 69-91 | `.headline`, `.caption`, `.caption.weight(.semibold)` | `ClavisTypography.h2`, `ClavisTypography.footnote` |

**Spacing (should use `ClavisTheme.*`):**

| File | Line | Hardcoded | Replace with |
|---|---|---|---|
| `Auth/LoginView.swift` | 98 | `padding(.horizontal, 24)` | `ClavisTheme.extraLargeSpacing` |
| `Onboarding/OnboardingContainerView.swift` | 108, 110, 155 | `Spacer(minLength: 24)`, `spacing: 24` | `ClavisTheme.extraLargeSpacing` |
| `Onboarding/OnboardingContainerView.swift` | 574 | `padding(13)` | `ClavisTheme.cardPadding` (12) |

**Corner radius (should use `ClavisTheme.cornerRadius` = 12 or `innerCornerRadius` = 10):**

| File | Line | Hardcoded | Replace with |
|---|---|---|---|
| `Holdings/HoldingsListView.swift` | 552 | `cornerRadius: 10` | `ClavisTheme.innerCornerRadius` |
| `Tickers/TickerDetailView.swift` | 1078 | `cornerRadius: 10` | `ClavisTheme.innerCornerRadius` |
| `Alerts/AlertsView.swift` | 149 | `cornerRadius: 10` | `ClavisTheme.innerCornerRadius` |
| `Dashboard/DashboardView.swift` | 469 | `cornerRadius: 8` | `ClavisTheme.cornerRadius` |
| `Onboarding/OnboardingContainerView.swift` | 82 | `cornerRadius: 2` (progress bar) | `ClavisTheme.innerCornerRadius` or new `barCornerRadius` token (4) |
| `PositionDetail/PriceChartView.swift` | 40 | `Capsule()` | `RoundedRectangle(cornerRadius: ClavisTheme.cornerRadius)` (R-07 violation) |
| `Tickers/TickerDetailView.swift` | 669-677 | `Capsule()` chips | Same — R-07 violation |

### 2.3 Deprecated components still referenced or tempting to use

`ClavisCapsuleButton`, `ClavisStatPill`, `ClavisRingGauge` are marked `@available(*, deprecated, ...)` in the design system but the patterns they enable (capsule shapes, ring gauges) still appear in screen code (above). After this audit, **delete the deprecated types entirely** so future contributors can't reach for them.

### 2.4 Tokens that should be added

The audit surfaces values used in 2+ places that have no token:

- `portfolioHero` (52pt mono — already defined as `portfolioScore`, just rename usage)
- `tickerHero` (44pt mono — TickerDetailView)
- `displayTitle` (30pt — onboarding hero)
- `barCornerRadius` (4pt — risk bars, progress bars)
- `errorCardCornerRadius` — currently 8 in one place, 12 elsewhere
- `dividerColor` standardized via a `ClavisDivider` component (currently every screen does `Rectangle().fill(Color.border)`)

---

## 3. Screen-by-Screen Findings

### 3.1 [LoginView.swift](ios/Clavis/Views/Auth/LoginView.swift)

**What it does:** Email/password sign-in and sign-up.

| # | Severity | Issue | Evidence |
|---|---|---|---|
| L1 | P1 | Brand wordmark uses raw `.custom("Inter", ...)` instead of token | [line 27](ios/Clavis/Views/Auth/LoginView.swift:27) |
| L2 | P1 | "Forgot password?" has no loading state when tapped | [line 61](ios/Clavis/Views/Auth/LoginView.swift:61) |
| L3 | P2 | Status message uses `Color.clear.frame(height: 14)` as a passive layout placeholder — fragile | [line 126](ios/Clavis/Views/Auth/LoginView.swift:126) |
| L4 | P2 | Horizontal padding hardcoded (`24`) instead of token | [line 98](ios/Clavis/Views/Auth/LoginView.swift:98) |
| L5 | P2 | Terms footer fonts hardcoded (11pt / 14pt) | bottom of file |
| L6 | P2 | "Sign in" and "Sign up" used here; "Login" appears in file/code names — pick one for UI | line 74, 89 |

### 3.2 [OnboardingContainerView.swift](ios/Clavis/Views/Onboarding/OnboardingContainerView.swift)

**What it does:** Multi-step onboarding (welcome → DOB → risk ack → preferences → brokerage).

| # | Severity | Issue | Evidence |
|---|---|---|---|
| O1 | **P0** | "SnapTrade keeps this read-only..." exposes backend SaaS name | [line 394](ios/Clavis/Views/Onboarding/OnboardingContainerView.swift:394) |
| O2 | P1 | Custom checkbox built from primitives instead of native `Toggle` or `CX2Toggle` | [lines 258–270](ios/Clavis/Views/Onboarding/OnboardingContainerView.swift:258) |
| O3 | P1 | Three different brokerage CTA strings: "Connect your brokerage", "Connect brokerage", "Continue without brokerage" | lines 390, 468, 478 |
| O4 | P1 | Tone whiplash: "Pick what wakes you up." (casual) vs. "Required to confirm you meet minimum age requirements in your jurisdiction." (legal) within two screens | line 161, 320 |
| O5 | P2 | Progress bar uses `cornerRadius: 2` — too sharp, inconsistent with rest of app | [line 82](ios/Clavis/Views/Onboarding/OnboardingContainerView.swift:82) |
| O6 | P2 | Hero font hardcoded `.system(size: 30, weight: .bold)` | [line 115](ios/Clavis/Views/Onboarding/OnboardingContainerView.swift:115) |
| O7 | P2 | Error message ([line 349–353](ios/Clavis/Views/Onboarding/OnboardingContainerView.swift:349)) is plain `Text` — should use `ClavisErrorCard` |
| O8 | P2 | Welcome CTA "Get started" — vague; switch to "Continue" to match later steps | line 138 |
| O9 | P3 | Label casing inconsistent: "YOUR NAME" (uppercase) vs "Date of birth" (sentence case) | line 127, 159 |
| O10 | P3 | "Brokerage auto-import is not available right now." — no follow-up on when it will be | [line 419](ios/Clavis/Views/Onboarding/OnboardingContainerView.swift:419) |

### 3.3 [DashboardView.swift](ios/Clavis/Views/Dashboard/DashboardView.swift)

**What it does:** Portfolio score hero, "what changed", at-risk holdings, digest teaser.

| # | Severity | Issue | Evidence |
|---|---|---|---|
| D1 | **P0** | "Pending" used as score fallback — feels like backend leak; should show "Calculating…" or skeleton | DashboardViewModel line 31, [DashboardView.swift:101](ios/Clavis/Views/Dashboard/DashboardView.swift:101) |
| D2 | P1 | Empty state uses `.buttonStyle(.borderedProminent)` instead of `ClavisPrimaryButton` | [line 449](ios/Clavis/Views/Dashboard/DashboardView.swift:449) |
| D3 | P1 | Error card uses `RoundedRectangle(cornerRadius: 8)` — every other card uses 12 | [line 469](ios/Clavis/Views/Dashboard/DashboardView.swift:469) |
| D4 | P1 | Hero score uses `.system(size: 64, weight: .bold, design: .monospaced)` directly | [line 101](ios/Clavis/Views/Dashboard/DashboardView.swift:101) |
| D5 | P2 | Stat strip cards use raw `RoundedRectangle` + stroke instead of `.clavisCardStyle()` | lines 153–156 |
| D6 | P2 | Digest teaser CTA "Read digest →" — arrow glyph instead of native chevron | [line 295](ios/Clavis/Views/Dashboard/DashboardView.swift:295) |
| D7 | P2 | "Pending" / "Now" timestamp variants without explanation of which is which | lines 131–132 |
| D8 | P2 | Body text hardcoded `.system(size: 15, weight: .regular)` | [line 109](ios/Clavis/Views/Dashboard/DashboardView.swift:109) |

### 3.4 [HoldingsListView.swift](ios/Clavis/Views/Holdings/HoldingsListView.swift)

**What it does:** Categorized holdings list (watchlist, needs review, all) with search, sort, filter, add.

| # | Severity | Issue | Evidence |
|---|---|---|---|
| H1 | **P0** | "Limited data available from the shared ticker cache." — backend term in user copy | [line 735](ios/Clavis/Views/Holdings/HoldingsListView.swift:735) |
| H2 | **P0** | "Cached S&P ticker" — implementation detail in user copy | WatchlistCardRow [line 1239](ios/Clavis/Views/Holdings/HoldingsListView.swift:1239) |
| H3 | **P0** | "Analysis running. This position will populate when scoring finishes." — wordy and exposes backend lifecycle | [line 729](ios/Clavis/Views/Holdings/HoldingsListView.swift:729) |
| H4 | P1 | Filter pills hand-rolled instead of using a shared component | [lines 630–645](ios/Clavis/Views/Holdings/HoldingsListView.swift:630) |
| H5 | P1 | Empty state uses `.borderedProminent` | [line 886](ios/Clavis/Views/Holdings/HoldingsListView.swift:886) |
| H6 | P1 | Watchlist action labelled "Unstar" in one place, "Remove from watchlist" in another | line 358 vs 332 |
| H7 | P1 | Errors surfaced via `.alert("Error", ...)` instead of inline `ClavisErrorCard` (other screens use cards) | [line 194](ios/Clavis/Views/Holdings/HoldingsListView.swift:194) |
| H8 | P2 | Section labels written as inline `Text(...).uppercased()` instead of `CX2SectionLabel` | lines 103, 127, 162 |
| H9 | P2 | "Unsupported ticker" feedback is plain `Text(.riskF)` — no card affordance | [line 405](ios/Clavis/Views/Holdings/HoldingsListView.swift:405) |
| H10 | P2 | Trend uses Unicode "▲ / ▼ / —" instead of SF Symbol arrows | line 762, 766 |
| H11 | P2 | Search bar `cornerRadius: 10` hardcoded | [line 552](ios/Clavis/Views/Holdings/HoldingsListView.swift:552) |
| H12 | P3 | Add Position sheet has no `.presentationDetents` — full-screen modal feels heavy for a 3-field form | [line 188](ios/Clavis/Views/Holdings/HoldingsListView.swift:188) |
| H13 | P3 | Add Position uses "Cancel"; AddPositionProgress uses "Close" — pick one | toolbars |

### 3.5 [PositionDetailView.swift](ios/Clavis/Views/PositionDetail/PositionDetailView.swift)

**What it does:** Resolves position ID → ticker, delegates to TickerDetailView.

| # | Severity | Issue | Evidence |
|---|---|---|---|
| PD1 | P1 | Error displayed as plain VStack of `Text` instead of `ClavisErrorCard` | [lines 17–23](ios/Clavis/Views/PositionDetail/PositionDetailView.swift:17) |
| PD2 | P1 | Raw `error.localizedDescription` in user copy: "Failed to load position details: ..." | [line 44](ios/Clavis/Views/PositionDetail/PositionDetailView.swift:44) |
| PD3 | P3 | Skeleton uses `Color.surfaceSecondary` (alias) — pick one canonical name | lines 55–65 |

### 3.6 [PriceChartView.swift](ios/Clavis/Views/PositionDetail/PriceChartView.swift)

**What it does:** Price history chart + price-range metrics.

| # | Severity | Issue | Evidence |
|---|---|---|---|
| PC1 | P1 | Capsule pill (`Capsule()` + `.clipShape(Capsule())`) — violates spec R-07 | [lines 40–42](ios/Clavis/Views/PositionDetail/PriceChartView.swift:40) |
| PC2 | P1 | Prices formatted with `Int($0)` — loses precision; inconsistent with currency formatting in TickerDetailView | lines 71, 81, 91 |
| PC3 | P2 | Uses `.headline` and `.caption` system tokens instead of `ClavisTypography` | lines 28, 31, 69–91 |
| PC4 | P3 | "Flat" displayed for zero change vs "—" elsewhere — pick one fallback string | line 112 |

### 3.7 [TickerDetailView.swift](ios/Clavis/Views/Tickers/TickerDetailView.swift)

**What it does:** Hero card, dimensions, fundamentals, events, news, alerts.

| # | Severity | Issue | Evidence |
|---|---|---|---|
| T1 | **P0** | "Coverage is still being assembled for this ticker." — MVP language | [line 199](ios/Clavis/Views/Tickers/TickerDetailView.swift:199) |
| T2 | **P0** | "Shared ticker cache" appears in user-facing string | [line 65](ios/Clavis/Views/Tickers/TickerDetailView.swift:65) |
| T3 | **P0** | Backend states displayed verbatim: "Analysis run: queued/running/failed/completed" via `.capitalized` | [line 630](ios/Clavis/Views/Tickers/TickerDetailView.swift:630) |
| T4 | **P0** | "Last news refresh at" / "News refresh status" — backend column names in UI | lines 624, 641 |
| T5 | P1 | Custom back button with hardcoded "Holdings" label — breaks if entered from another tab | [line 29](ios/Clavis/Views/Tickers/TickerDetailView.swift:29) |
| T6 | P1 | State chips use `Capsule()` — R-07 violation | lines 669–677 |
| T7 | P1 | Hero score uses raw `.system(size: 44, weight: .bold, design: .monospaced)` | [line 553](ios/Clavis/Views/Tickers/TickerDetailView.swift:553) |
| T8 | P1 | Sparkline custom-rendered with Path instead of SwiftUI Charts (PriceChartView already uses Charts) | lines 760–805 |
| T9 | P1 | Risk dimension bars use `cornerRadius: 2` — sharp/inconsistent | lines 1125–1133 |
| T10 | P2 | "Open source article →" — arrow glyph for link affordance | [line 956](ios/Clavis/Views/Tickers/TickerDetailView.swift:956) |
| T11 | P2 | Metric grid uses `cornerRadius: 10` hardcoded | line 1078 |
| T12 | P2 | Multiple `Divider().overlay(Color.border)` instances — promote to `ClavisDivider` | line 851, etc. |
| T13 | P3 | "Already in holdings" notice tone-positive (`.riskA`) is inconsistent with neutral notices elsewhere | line 318 |

### 3.8 [DigestView.swift](ios/Clavis/Views/Digest/DigestView.swift)

**What it does:** Morning digest — overnight macro, sector overview, position impacts, watch list, urgent items.

| # | Severity | Issue | Evidence |
|---|---|---|---|
| DG1 | **P0** | "Latest morning summary for your portfolio." — fallback string with no real content cue | [line 263](ios/Clavis/Views/Digest/DigestView.swift:263) |
| DG2 | **P0** | "Run Fresh Review" CTA — internal jargon | [line 639](ios/Clavis/Views/Digest/DigestView.swift:639) |
| DG3 | P1 | Section labels written three ways: `CX2SectionLabel` (lines 309, 459) and inline `Text(...).uppercased()` (lines 128, 343, 391) within the same file | as cited |
| DG4 | P1 | Hero subtitle uses `.system(size: 22, weight: .semibold)` — should use `h2` | [line 272](ios/Clavis/Views/Digest/DigestView.swift:272) |
| DG5 | P1 | Status badge uses `.capitalized` runtime string instead of enum→label mapping | [line 280](ios/Clavis/Views/Digest/DigestView.swift:280) |
| DG6 | P2 | Macro section uses `.surfacePrimary` while rest of app uses `.surface` (aliases, but visually different intent) | [line 328](ios/Clavis/Views/Digest/DigestView.swift:328) |
| DG7 | P2 | Expandable narrative built from custom chevron toggle instead of `DisclosureGroup` | lines 489–517 |
| DG8 | P2 | `ProgressView().tint(.accentBlue)` regardless of risk context | [line 536](ios/Clavis/Views/Digest/DigestView.swift:536) |
| DG9 | P3 | Bullet points use literal `"• "` string prefix (consistent within file, but inconsistent with semantic markdown elsewhere) | line 322 |
| DG10 | P3 | Two error cards visible: `DigestErrorCard` (line 37) and `DigestTimeoutCard` (line 42) — could be one with variant | as cited |

### 3.9 [AlertsView.swift](ios/Clavis/Views/Alerts/AlertsView.swift)

**What it does:** Timeline of alerts with severity/type filters.

| # | Severity | Issue | Evidence |
|---|---|---|---|
| A1 | P1 | Filter pills re-implemented (third copy of the same pattern) | [lines 177–189](ios/Clavis/Views/Alerts/AlertsView.swift:177) |
| A2 | P1 | Timeline connector built from raw `Rectangle` — promote to component | lines 237–240 |
| A3 | P1 | Empty state has no CTA, while every other empty state has one (Dashboard, Holdings, Digest) | [line 387–399](ios/Clavis/Views/Alerts/AlertsView.swift:387) |
| A4 | P2 | Grade transition arrow uses `Image(systemName: "arrow.right")` — should match documented `chevron.right` (CX2Chevron) | line 272 |
| A5 | P2 | Summary cell counts use `.system(size: 11, weight: .medium)` instead of `ClavisTypography.label` | line 136 |
| A6 | P2 | Cell `cornerRadius: 10` hardcoded | line 149 |
| A7 | P3 | "No alerts" vs "No holdings yet" — empty-state titles use different patterns | line 390 |

### 3.10 [SettingsView.swift](ios/Clavis/Views/Settings/SettingsView.swift)

**What it does:** Digest, alerts, notifications, brokerage, account, about.

| # | Severity | Issue | Evidence |
|---|---|---|---|
| S1 | **P0** | "SnapTrade stays read-only here..." — backend SaaS name in user copy | [line 108](ios/Clavis/Views/Settings/SettingsView.swift:108) |
| S2 | **P0** | Version string "v1.0.0" hardcoded — should read from bundle, hidden in release if zero-config | [line 544](ios/Clavis/Views/Settings/SettingsView.swift:544) |
| S3 | **P0** | "Sign out" has no confirmation alert (`.alert` modifier missing) — destructive action unguarded | [line 639](ios/Clavis/Views/Settings/SettingsView.swift:639) |
| S4 | P1 | "Delete account" alert message is one short line — should restate consequence ("This cannot be undone") | [line 86](ios/Clavis/Views/Settings/SettingsView.swift:86) |
| S5 | P1 | "Export my data" gives no completion feedback (no toast, no inline state) | [line 334](ios/Clavis/Views/Settings/SettingsView.swift:334) |
| S6 | P1 | Disconnect-brokerage button enabled while a sync is in flight — should disable | [line 170](ios/Clavis/Views/Settings/SettingsView.swift:170) |
| S7 | P1 | Settings toggle row uses `.system(size: 15, weight: .regular)` instead of `ClavisTypography.body` | [line 399](ios/Clavis/Views/Settings/SettingsView.swift:399) |
| S8 | P2 | Manual `Rectangle().fill(Color.border)` dividers throughout — promote to `ClavisDivider` | line 424 |
| S9 | P2 | "Use manual sync" / "Use automatic sync" — toggle has no explanation of the difference | [line 149](ios/Clavis/Views/Settings/SettingsView.swift:149) |
| S10 | P2 | Brokerage status row is text-only ("Status: Connected") — a colored dot would read faster | line 121 |
| S11 | P3 | Quiet-hours From/To rows appear/disappear with no animation | lines 276–289 |

### 3.11 [SafariView.swift](ios/Clavis/Views/Shared/SafariView.swift)

| # | Severity | Issue | Evidence |
|---|---|---|---|
| SF1 | P3 | Tint uses `Color.accentBlue` (alias for `.informational`) — pick the canonical name | line 11 |

---

## 4. Cross-Cutting Findings

### 4.1 Backend / debug language leaking into UI

Every string below is shown to a user but reads like internal documentation:

| String | Location |
|---|---|
| "SnapTrade keeps this read-only..." | [OnboardingContainerView.swift:394](ios/Clavis/Views/Onboarding/OnboardingContainerView.swift:394) |
| "SnapTrade stays read-only here..." | [SettingsView.swift:108](ios/Clavis/Views/Settings/SettingsView.swift:108) |
| "Shared ticker cache" | [TickerDetailView.swift:65](ios/Clavis/Views/Tickers/TickerDetailView.swift:65) |
| "Limited data available from the shared ticker cache." | [HoldingsListView.swift:735](ios/Clavis/Views/Holdings/HoldingsListView.swift:735) |
| "Cached S&P ticker" | [HoldingsListView.swift:1239](ios/Clavis/Views/Holdings/HoldingsListView.swift:1239) |
| "Coverage is still being assembled for this ticker." | [TickerDetailView.swift:199](ios/Clavis/Views/Tickers/TickerDetailView.swift:199) |
| "Analysis running. This position will populate when scoring finishes." | [HoldingsListView.swift:729](ios/Clavis/Views/Holdings/HoldingsListView.swift:729) |
| "Analysis run: queued/running/failed/completed" (via `.capitalized`) | [TickerDetailView.swift:630](ios/Clavis/Views/Tickers/TickerDetailView.swift:630) |
| "Last news refresh at" / "News refresh status" | TickerDetailView.swift:624, 641 |
| "Failed to load position details: \(error.localizedDescription)" | [PositionDetailView.swift:44](ios/Clavis/Views/PositionDetail/PositionDetailView.swift:44) |
| "Failed to load: \(error.localizedDescription)" | HoldingsViewModel.swift:58 |
| "Pending" (used as a score) | DashboardViewModel.swift:31 |
| "Run Fresh Review" | [DigestView.swift:639](ios/Clavis/Views/Digest/DigestView.swift:639) |
| Coverage states "thin" / "stale" / "failed" surfaced verbatim | TickerDetailView.swift:76 |

**Fix pattern:** Map every backend status to a user-facing label in one place (e.g., `ClavisCopy.statusLabel(for: AnalysisState)`), and never call `.capitalized` on a backend string in a view body.

### 4.2 Inconsistent terminology

Pick one and replace globally.

| Concept | Variants in codebase | Recommended |
|---|---|---|
| User's positions | "Holdings", "Positions", "Portfolio" | **Holdings** (UI) — "Portfolio" only for the aggregate score |
| In-app notifications | "Alerts", "Notifications" | **Alerts** in-app; **Notifications** only for OS push settings |
| Daily summary | "Digest", "Morning digest", "Daily digest", "Morning summary" | **Morning Digest** |
| Brokerage | "Brokerage", "SnapTrade", "Connect account", "Linked account" | **Brokerage** |
| Auth verbs | "Sign in", "Login", "Sign up" | **Sign in / Sign up** |
| Score | "Risk score", "Safety score", "Grade" | **Risk Score** + **Grade** (letter); never "Safety Score" |
| Refresh action | "Refreshing", "Running", "Run", "Sync" | **Refresh** for analysis; **Sync** for brokerage |

### 4.3 Loading / empty / error pattern inventory

| Screen | Loading | Empty | Error |
|---|---|---|---|
| Dashboard | `ClavisLoadingCard` ✓ | `DashboardEmptyStateCard` (CTA) | `DashboardErrorCard` |
| Holdings | `ClavisLoadingCard` ✓ | `HoldingsEmptyState` (CTA) | `.alert("Error", ...)` ✗ inconsistent |
| Ticker | `ClavisLoadingCard` ✓ | none (graceful) | `DashboardErrorCard` reused |
| Digest | `ClavisLoadingCard` ✓ | `DigestEmptyStateCard` (CTA) | `DigestErrorCard` + `DigestTimeoutCard` (two variants) |
| Alerts | `ClavisLoadingCard` ✓ | `AlertsEmptyStateCard` ✗ no CTA | `DashboardErrorCard` reused |
| Settings | none ✗ silent saves | none | `SettingsMessageRow` (one-off) |
| Onboarding | inline text | n/a | plain Text ✗ |

**Fix:** Promote one canonical `ClavisEmptyState` and one `ClavisErrorCard`. Remove the `.alert` path. Add success toasts for Settings saves.

### 4.4 Risk-score presentation inventory

| Place | Visual | Grade letter | Numeric | Trend |
|---|---|---|---|---|
| Dashboard hero | none (just number) | `GradeTag` | 64pt mono | "Safe / Stable / Watch / Risky / Critical" word |
| Dashboard "Needs Attention" rows | `RiskBar` | `GradeTag` compact | `dataNumber` | em-dash `—` |
| Holdings rows | none | `GradeTag` standard | 15pt mono | Unicode ▲▼— |
| Ticker hero | none (just number) | `GradeTag` large | 44pt mono | delta string via custom function |
| Ticker dimensions | none | none | 13pt mono | none |
| Ticker fundamentals | none | none | 15pt mono bold | none |
| Watchlist row | none | `GradeTag` only | none | none |
| Alerts timeline | none | `GradeTag` compact | none | "arrow.right" between two grades |

**Inconsistencies:** trend symbols use `▲▼—` Unicode in one place and SF Symbols in another; numeric precision varies (int vs 1-decimal); RiskBar appears in some rows but not others.

**Recommendation:** Single `ClavisScoreView(size:showsBar:showsGrade:showsTrend:)` component used everywhere a score is displayed.

### 4.5 Sheet / modal behaviour inventory

| Trigger | Type | `.presentationDetents` | Dismiss | Drag indicator |
|---|---|---|---|---|
| Add Position | `.sheet` | none | "Cancel" toolbar | native |
| Add Position Progress | `.fullScreenCover` | n/a | "Close" toolbar | none |
| Brokerage Safari (onboarding) | `.sheet` | none | native | native |
| Settings → Safari links | `.sheet` (SafariView) | none | native | native |

**Issues:** No screen sets `.presentationDetents`. Cancel vs Close labels inconsistent. Add Position Progress blocks all interaction with no escape.

### 4.6 Non-native iOS patterns to remove

- Custom checkbox in onboarding ([OnboardingContainerView.swift:258](ios/Clavis/Views/Onboarding/OnboardingContainerView.swift:258)) → `Toggle`/`CX2Toggle`.
- Manual `Rectangle()` dividers everywhere → `Divider` or a `ClavisDivider` wrapper.
- Custom expandable sections in DigestView → `DisclosureGroup`.
- Hardcoded "Holdings" back-button label → standard `NavigationLink` back.
- Capsule pills (`Capsule()`) anywhere → `RoundedRectangle(cornerRadius: 12)` per spec R-07.
- "→" / "Open … →" arrows on links → standard `chevron.right` or rely on `NavigationLink`.

---

## 5. Severity Tables

**P0** = pre-TestFlight blocker (looks unfinished, leaks backend names, or jeopardizes trust).
**P1** = visibly inconsistent across screens or weakens hierarchy.
**P2** = polish (token swap, deprecated component).
**P3** = nice-to-have.

### P0 — must fix before TestFlight

**Status update (2026-04-26):** Complete in the current repo state.

| ID | Description | File |
|---|---|---|
| O1, S1 | Remove every "SnapTrade" reference from UI copy | OnboardingContainerView, SettingsView |
| H1, H2, H3, T1, T2 | Remove "shared ticker cache" / "cached S&P ticker" / "coverage being assembled" / "analysis running … will populate when scoring finishes" | TickerDetailView, HoldingsListView |
| T3, T4 | Stop showing raw backend states (`.capitalized`) and column names in TickerDetailView | TickerDetailView |
| PD2 | Stop exposing `error.localizedDescription` directly | PositionDetailView, HoldingsViewModel |
| D1 | Replace "Pending" score fallback with skeleton or "Calculating…" | DashboardViewModel, DashboardView |
| DG1, DG2 | "Latest morning summary…" placeholder + "Run Fresh Review" jargon | DigestView |
| S2 | Hide / source from bundle the "v1.0.0" string | SettingsView |
| S3 | Add confirmation alert before Sign out | SettingsView |

### P1 — should fix before TestFlight

| ID | Description |
|---|---|
| Header consolidation: pick `ClavixPageHeader` for top-level, `CX2NavBar` for detail; delete the rest |
| Section label consolidation: `CX2SectionLabel` everywhere (or `ClavisSectionHeader` when a subtitle/accessory is needed); delete all inline `Text(...).uppercased()` |
| Replace every `.buttonStyle(.borderedProminent)` with `ClavisPrimaryButton` (D2, H5, others) |
| Promote a single `ClavisFilterPill` and replace the three hand-rolled implementations (H4, A1) |
| Promote `ClavisEmptyState` and `ClavisErrorCard`; replace the four/three local copies |
| Replace `.alert("Error", ...)` in Holdings with inline error card (H7) |
| Standardize destructive-action confirmations (Sign out, Delete account, Disconnect brokerage) — all use `.alert` with consistent verb + consequence |
| Pick one trend-arrow style (SF Symbols) and remove Unicode ▲▼— |
| Onboarding: replace custom checkbox with `CX2Toggle`; standardize CTA copy ("Continue", "Connect brokerage") |
| Brand wordmark uses `ClavisTypography.brandWordmark` everywhere (L1) |
| Remove capsule pills in PriceChartView and TickerDetailView (PC1, T6) |
| Promote a `ClavisScoreView` to unify score+grade+bar+trend presentation |

### P2 — polish

| ID | Description |
|---|---|
| Replace every hardcoded font size with `ClavisTypography.*` |
| Replace every hardcoded `cornerRadius` with `ClavisTheme.*` |
| Replace every hardcoded spacing literal with `ClavisTheme.*` |
| Promote `ClavisDivider` and remove `Rectangle().fill(Color.border)` instances |
| Use `DisclosureGroup` instead of custom expanders (DG7) |
| Add `.presentationDetents([.medium, .large])` to Add Position sheet (H12) |
| Use `Color.informational` consistently (kill `accentBlue` alias) |

### P3 — nice-to-have

| ID | Description |
|---|---|
| Animate Quiet Hours From/To rows on toggle (S11) |
| Single fallback string for zero/flat ("—") across PriceChartView, HoldingsListView, TickerDetailView |
| Tighten onboarding tone — pick "warm-conversational" or "calm-professional", not both |

---

## 6. Recommended Shared Components / Tokens

### 6.1 New components to add

```swift
// One-line section label (already have CX2SectionLabel — adopt everywhere)
// Existing: CX2SectionLabel

ClavisDivider()                              // replaces Rectangle().fill(Color.border)
ClavisEmptyState(icon:title:body:cta:)       // replaces 4 per-screen empty cards
ClavisErrorCard(title:body:retry:)           // replaces 2 per-screen error cards + .alert paths
ClavisFilterPill(title:isSelected:action:)   // or: ClavisSmallButton(kind: .filter)
ClavisScoreView(score:grade:size:showsBar:showsTrend:)  // unifies all score displays
ClavisStatusDot(state:)                      // green/amber/red dot for Brokerage status, etc.
ClavisToast(text:tone:)                      // success/info confirmation for Settings saves
ClavisCopy.statusLabel(for: AnalysisState)   // single place that maps backend → UI strings
```

### 6.2 Tokens to add to `ClavisTheme` / `ClavisTypography`

```swift
// ClavisTypography
static let displayTitle  = inter(30, weight: .bold)   // onboarding hero
static let portfolioHero = mono(64)                   // dashboard hero (rename of portfolioScore use)
static let tickerHero    = mono(44)                   // ticker hero score
static let bodyMedium    = inter(14, weight: .regular)// digest body

// ClavisTheme
static let barCornerRadius: CGFloat = 4               // risk bars, progress bars
```

### 6.3 Tokens / components to delete (deprecated)

- `ClavisCapsuleButton`
- `ClavisStatPill`
- `ClavisRingGauge`
- `ClavisTopBar` (unused — `ClavixPageHeader` and `CX2NavBar` cover both jobs)
- Color aliases used only once: `accentBlue`, `surfaceSecondary` — keep `informational` and `surfaceElevated`.

### 6.4 Single-source copy file

Create `ClavisCopy.swift` (or expand the existing one — it's already referenced for `riskAcknowledgment`/`settingsDisclaimer`) with a `Status` namespace:

```swift
enum ClavisCopy {
    enum Status {
        static func label(for state: AnalysisState) -> String { ... }
        static func longExplanation(for state: AnalysisState) -> String { ... }
    }
    enum Errors {
        static let loadFailed = "Couldn't load the latest data. Pull down to retry."
        static let networkOffline = "You're offline. Showing the latest cached view."
        // ...
    }
}
```

This is the single chokepoint that prevents backend names / `.capitalized` strings from re-entering the UI.

---

## 7. Implementation Phases

### Phase 1 — Pre-TestFlight (blockers, ~1–2 days)

**Status update (2026-04-26):** Complete for the scoped P0 trust-polish pass in the current repo state.

- [x] Copy sweep for the Phase 1/P0 strings via `ClavisCopy`
- [x] Removed user-facing `SnapTrade` references
- [x] Replaced the hardcoded app version with bundle-driven version text
- [x] Added sign-out confirmation
- [x] Replaced direct raw error passthroughs on the scoped P0 surfaces with user-facing copy
- [x] Replaced the dashboard `Pending` score state and related P0 placeholder wording

1. **Copy sweep** — replace every P0 string with user-friendly copy via a new `ClavisCopy` module.
2. **Rip out "SnapTrade"** from all UI text.
3. **Hide version string** ([SettingsView.swift:544](ios/Clavis/Views/Settings/SettingsView.swift:544)) — read from `Bundle.main.infoDictionary["CFBundleShortVersionString"]`.
4. **Add Sign out confirmation alert.**
5. **Replace `error.localizedDescription` passthroughs** with `ClavisCopy.Errors.*`.
6. **Replace `.borderedProminent` buttons** with `ClavisPrimaryButton` (3 files).
7. **Standardize destructive-action alerts** (Delete, Disconnect, Sign out — all use the same pattern with explicit consequence sentence).
8. **Score fallbacks** — replace "Pending" with skeleton or "Calculating…".

**Outcome:** App no longer feels MVP. No backend names visible. All destructive actions guarded.

### Phase 2 — Design-system consolidation (~2–3 days)

1. **Header consolidation** — pick `ClavixPageHeader` (tab roots) + `CX2NavBar` (detail). Delete `ClavisTopBar`.
2. **Section label consolidation** — `CX2SectionLabel` everywhere; delete inline `Text(...).uppercased()`.
3. **Promote `ClavisEmptyState`, `ClavisErrorCard`, `ClavisFilterPill`, `ClavisDivider`** and replace the 4/3/3/many local copies.
4. **Promote `ClavisScoreView`** and route every score display through it.
5. **Replace Holdings `.alert("Error", ...)`** with inline `ClavisErrorCard`.
6. **Add success toasts** for Settings saves and "Export my data".

**Outcome:** Cross-screen consistency. No more "two ways to do the same thing".

### Phase 3 — Polish (~1–2 days)

1. **Token sweep** — replace every hardcoded font, spacing, and corner radius cited in §2.2 with the appropriate token.
2. **Capsule shapes → 12pt rounded rectangles** (PriceChartView, TickerDetailView state chips).
3. **Custom checkbox → CX2Toggle** in onboarding.
4. **Custom expander → DisclosureGroup** in DigestView.
5. **Sparkline → SwiftUI Charts** in TickerDetailView (already used in PriceChartView).
6. **Add `.presentationDetents`** to Add Position sheet.
7. **Trend arrows** → SF Symbols (`arrow.up.right`/`arrow.down.right`/`arrow.right`) everywhere.
8. **Delete deprecated components** from `ClavisDesignSystem.swift`.

**Outcome:** Code matches the design system spec. Future contributors can't reach for deprecated patterns.

### Phase 4 — Native-feel pass (~1 day)

1. **Standardize sheet behaviour** — every modal sets `.presentationDetents`, uses native dismiss, drags down to close.
2. **Standardize navigation back** — drop hardcoded "Holdings" back labels; use system back.
3. **Animate disclosure rows** (Quiet Hours From/To).
4. **Add haptics** to destructive confirmations.

---

## 8. Before-TestFlight Checklist

Print this. Tick as you go.

### Copy / language

- [ ] No "SnapTrade" anywhere in UI ([OnboardingContainerView.swift:394](ios/Clavis/Views/Onboarding/OnboardingContainerView.swift:394), [SettingsView.swift:108](ios/Clavis/Views/Settings/SettingsView.swift:108))
- [ ] No "shared ticker cache" anywhere
- [ ] No "Cached S&P ticker" anywhere
- [ ] No "Coverage is still being assembled" anywhere
- [ ] No `.capitalized` on backend status strings — every status mapped via `ClavisCopy.Status.label`
- [ ] No raw `error.localizedDescription` in user-visible text — every error routed through `ClavisCopy.Errors.*`
- [ ] No "v1.0.0" hardcoded — version reads from bundle
- [ ] "Holdings", "Morning Digest", "Brokerage", "Sign in / Sign up", "Risk Score" — terms standardized
- [ ] Onboarding tone consistent throughout

### Visual consistency

- [ ] One header component for top-level tabs (`ClavixPageHeader`)
- [ ] One header component for detail screens (`CX2NavBar`)
- [ ] One section-label component (`CX2SectionLabel`)
- [ ] One primary CTA component (`ClavisPrimaryButton`) — no `.borderedProminent`
- [ ] One filter-pill component
- [ ] One empty-state component
- [ ] One error-card component (no more `.alert("Error")` paths)
- [ ] One score-display component (`ClavisScoreView`)
- [ ] All capsule shapes replaced with 12pt rounded rectangles
- [ ] All trend arrows use SF Symbols (no `▲▼—` Unicode)

### Tokens

- [ ] No `.system(size: ...)` font literals in screen files (whitelist: brand wordmark already factored)
- [ ] No `cornerRadius: <number>` literals — all reference `ClavisTheme.*`
- [ ] No spacing literals (24, 16, 12, etc.) — all reference `ClavisTheme.*`
- [ ] No `Rectangle().fill(Color.border)` divider — use `ClavisDivider`

### Interaction

- [ ] Sign out shows confirmation alert
- [ ] Delete account shows confirmation alert with "This cannot be undone" line
- [ ] Disconnect brokerage shows confirmation alert; button disabled while syncing
- [ ] Export my data shows toast on completion
- [ ] Settings toggle changes show subtle confirmation (toast or inline)
- [ ] Add Position sheet uses `.presentationDetents([.medium, .large])`
- [ ] Score-pending UI is a skeleton, not a "Pending" string

### QA pass on every screen

- [ ] Login (sign in / sign up / forgot password)
- [ ] Onboarding (welcome → DOB → risk ack → preferences → brokerage)
- [ ] Dashboard (loading / empty / error / loaded)
- [ ] Holdings (loading / empty / error / loaded / search / filter / sort / add)
- [ ] Position Detail / Ticker Detail (loading / error / loaded / event detail / news link)
- [ ] Digest (loading / empty / error / timeout / loaded)
- [ ] Alerts (loading / empty / error / loaded / each filter)
- [ ] Settings (every section, every toggle, every destructive action)
- [ ] Offline (network monitor banner shows; retry works)

---

*End of audit. No fixes implemented yet — this document is the input to the polish PR.*
