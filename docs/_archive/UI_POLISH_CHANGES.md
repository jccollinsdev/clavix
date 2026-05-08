# Clavix UI Polish — Production Pass

## 0. Phase 1 / P0 Trust Polish (2026-04-26)

Focused follow-up pass against `docs/ui_audit.md` Phase 1 / P0 only. This pass stayed intentionally small and production-facing: copy cleanup, status mapping, destructive confirmation, and version sourcing. No navigation, backend, or design-system refactor work was included.

- Expanded `ios/Clavis/App/ClavisCopy.swift` into the single copy/status/error chokepoint for user-facing language.
- Removed exposed backend/vendor wording from onboarding, settings, holdings, and ticker detail:
  - `SnapTrade` -> `Brokerage`
  - `shared ticker cache` / `Cached S&P ticker` -> user-facing market/tracker wording
  - `Coverage is still being assembled...` -> plain-language limited-data wording
- Replaced direct `error.localizedDescription` passthroughs across the Phase 1/P0 surfaces with user-facing fallback copy in:
  - `DashboardViewModel.swift`
  - `DigestViewModel.swift`
  - `HoldingsViewModel.swift`
  - `BrokerageViewModel.swift`
  - `SettingsViewModel.swift`
  - `AlertsViewModel.swift`
  - `TickerDetailView.swift`
  - `PositionDetailView.swift`
- Reworked raw backend state labels in `TickerDetailView.swift` so the UI now shows labels like `Updating`, `Current`, `Limited`, and `Needs attention` instead of runtime-capitalized backend strings and column-like wording.
- Replaced the dashboard's `Pending` score state with a `Calculating...` presentation and removed other `Pending` copy from digest/ticker freshness text.
- Improved awkward CTA and empty-state wording:
  - `Get started` -> `Continue`
  - `Run Fresh Review` -> `Generate Morning Digest`
  - `No Digest Yet` -> `No Morning Digest Yet`
  - empty-state `position` wording -> `holding`
- Added a sign-out confirmation alert in `SettingsView.swift`.
- Replaced the hardcoded `v1.0.0` About row with `Bundle`-driven version text.

Files touched in this pass:

- `ios/Clavis/App/ClavisCopy.swift`
- `ios/Clavis/ViewModels/AlertsViewModel.swift`
- `ios/Clavis/ViewModels/BrokerageViewModel.swift`
- `ios/Clavis/ViewModels/DashboardViewModel.swift`
- `ios/Clavis/ViewModels/DigestViewModel.swift`
- `ios/Clavis/ViewModels/HoldingsViewModel.swift`
- `ios/Clavis/ViewModels/SettingsViewModel.swift`
- `ios/Clavis/Views/Dashboard/DashboardView.swift`
- `ios/Clavis/Views/Digest/DigestView.swift`
- `ios/Clavis/Views/Holdings/HoldingsListView.swift`
- `ios/Clavis/Views/Onboarding/OnboardingContainerView.swift`
- `ios/Clavis/Views/PositionDetail/PositionDetailView.swift`
- `ios/Clavis/Views/Settings/SettingsView.swift`
- `ios/Clavis/Views/Tickers/TickerDetailView.swift`

Deep audit + polish across the onboarding, auth, and core app surfaces. Focus was
"MVP → production" fit-and-finish: padding, type hierarchy, component reuse,
dead code removal, and a few correctness fixes (score bands, deprecated APIs,
duplicate nav entries). No features were added or removed.

Below is every file touched and why.

---

## 1. Design system (`ios/Clavis/App/ClavisDesignSystem.swift`)

The design system had gaps that forced every screen to reinvent small
primitives. Fixed foundation first so downstream screens could become thinner.

- **Text color tokens.** `textTertiary` was too close to `textSecondary` —
  now `#5B6577` (darker, real hierarchy).
- **`CX2LargeTitle`.** Standardized to 28pt semibold with `-0.3` tracking and
  consistent top 4 / bottom 6 padding. Previously varied per screen.
- **`ClavisTopBar`.** Dropped the `scaleEffect(1.15)` hack — menu icon is now a
  real 18pt glyph. Title uses `Inter` 20 bold with `kerning(2.1)`.
- **New shared components** (to kill duplicated inline buttons/monograms):
  - `ClavisMonogram(size:cornerRadius:)` — reusable brand mark.
  - `ClavisPrimaryButton(title:isLoading:isEnabled:action:)` — 50pt filled.
  - `ClavisSecondaryButton(title:isEnabled:action:)` — 15pt text link.
  - `ClavisSmallButton(title:systemImage:kind:isEnabled:action:)` — chip button
    with `.neutral` and `.prominent` variants.

---

## 2. Auth / Login (`ios/Clavis/Views/Auth/LoginView.swift`)

Rewritten. Previous version used a fragile `GeometryReader` layout, had
clipped error messages, and hand-rolled buttons.

- Switched to `ScrollView` + `@FocusState` (email → password → submit).
- `.scrollDismissesKeyboard(.interactively)` + safe-area keyboard handling.
- Error/status message now has a reserved line so the form doesn't jump.
- "Forgot password?" disabled unless email is non-empty.
- Terms of Service and Privacy Policy are real `Link`s (not plain text).
- Uses shared `ClavisMonogram` and `ClavisPrimaryButton`.
- Added `submitLabel` + `onSubmit` handlers on both fields.

---

## 3. Onboarding (`ios/Clavis/Views/Onboarding/OnboardingContainerView.swift`)

Each step had its own private button struct, inconsistent top spacing, and
a couple of redundancies.

- Removed private `OnboardingPrimaryButton` / `OnboardingSecondaryButton`;
  every step now uses shared `ClavisPrimaryButton` / `ClavisSecondaryButton`.
- `OnboardingProgressHeader` now animates bar fills on step change, and the
  "Step X of Y" label uses `tracking(0.4)` for readability.
- `WelcomeStepView`: uses `ClavisMonogram(size: 64, cornerRadius: 16)`;
  removed forced `\n` in the title; simplified `isValid`.
- `DateOfBirthStepView`: removed the redundant formatted date line below
  the picker; picker is centered in an HStack with `.tint(.informational)`.
- `RiskAcknowledgmentView`: added `Spacer(minLength: 24)` top spacing for
  consistency with the other steps.

---

## 4. Dashboard (`ios/Clavis/Views/Dashboard/DashboardView.swift`)

The file carried six unused prototype card structs plus a broken hero
reference and a placeholder "7 days" label.

- Removed dead views: `DashboardMastheadCard`, `DashboardHeroCard`,
  `DashboardSnapshotCard`, `DashboardPlaybookCard`, `SinceLastReviewCard`,
  `ReviewMetricTile`, `DashboardChipRow`, `DashboardMetaPill`, `DigestPreviewCard`,
  `FlowLayout`, and typealias `CompactMetricReadout`.
- `DashboardPrototypeHeroCard`:
  - Removed the stray `if let previousScore { EmptyView() }` and its backing
    computed property (was doing nothing).
  - Removed the meaningless "7 days" label.
  - Refresh/Run replaced with `ClavisSmallButton` (neutral / prominent).
- `DashboardStatStrip`: the rightmost cell used an `opacity` trick to hide its
  divider. Replaced with an explicit `showDivider` flag — cleaner and actually
  correct at any scale.
- `DashboardWhatChangedCard`: the "See all" button was an empty closure. Now
  wired to navigate to the Alerts tab (`selectedTab = 3`).

---

## 5. Holdings (`ios/Clavis/Views/Holdings/HoldingsListView.swift`)

List had two competing sort affordances, a deprecated API, and several dead
structs.

- Removed duplicate sort menu (`Sort by X ▾`) over "All holdings"; the
  `HoldingsControlCard` already owns sort UI. Heading is now just
  `All holdings · N`.
- `AddPositionSheet`: `.autocapitalization(.allCharacters)` is deprecated —
  replaced with `.textInputAutocapitalization(.characters)` and added
  `.autocorrectionDisabled()`.
- Filter chip pills were `Capsule`, clashing with the rest of the app's
  rounded-rect language. Switched to `RoundedRectangle` at
  `ClavisTheme.innerCornerRadius` with 7pt vertical padding.
- `AddPositionProgressView`: status icon + container bumped from radius 8 to
  `ClavisTheme.cornerRadius` (12) — consistent with other cards.
- Removed dead code: `HoldingsSummaryCard`, `HoldingsTriageCard`,
  `HoldingsOverviewCard`, `HoldingsOverviewMetricRow`, `HoldingsSignalPill`,
  `AnimatedProgressBar`.

---

## 6. Alerts (`ios/Clavis/Views/Alerts/AlertsView.swift`)

Large chunk of legacy grouped-alerts UI that was no longer rendered.

- Removed dead views: `AlertsHeroCard`, `AlertsHeroStat`,
  `AlertsSeveritySummaryCard`, `AlertsSeverityPill`, `AlertCard`, and the
  `AlertGroupCard` typealias.
- Filter chips: `Capsule` → `RoundedRectangle(innerCornerRadius)`; font sized
  down from 15pt to 13pt — these are controls, not headings.
- `AlertsTimelineRow`: timestamp was a 15pt monospaced slab — now 11pt
  regular mono (same treatment as Dashboard "What changed"). Ticker line
  shrunk from 15pt to 12pt semibold mono — matches its true hierarchy as
  metadata, not a headline.

---

## 7. Digest (`ios/Clavis/Views/Digest/DigestView.swift`)

Multiple unused "v1" sections and an old hand-rolled Run button.

- Removed dead views: `DigestHeaderButton`, `DigestThesisCard`,
  `DigestScoreSummaryCard`, `DigestLeadCard`, `DigestPositionImpactsSection`
  (the public one — the active one is `DigestPrototypePositionImpactsSection`),
  `WhatChangedSection`, `ChangedRow`, `WhatToDoSection`, `PositionsSection`.
- Removed the unused `recentDigests` computed property in `DigestView`.
- `DigestHeroCard`: custom Run button replaced with `ClavisSmallButton`. Also
  dropped the duplicate "Informational only. Not financial advice." footer
  — it's already shown via `SettingsDisclaimerCard` and elsewhere; repeating
  it under the hero was noise.

---

## 8. Settings (`ios/Clavis/Views/Settings/SettingsView.swift`)

Small correctness + consistency fixes.

- **Score bands corrected** to match the authoritative ranges in
  `Models/RiskEnums.swift` (`Grade.from(score:)`):
  - A: 75–100 (was 80–100)
  - B: 55–74 (was 65–79)
  - C: 35–54 (was 50–64)
  - D: 15–34 (was 35–49)
  - F: 0–14  (was 0–34)
- **Account row** labeled "Profile" → "Email" (that's what it actually shows).
- **About section** had both a `NavigationLink` to the in-app `MethodologyView`
  and an external `SettingsLinkRow` to `getclavix.com/methodology`. Removed
  the external duplicate — the in-app view is authoritative.
- **`SignOutGroup`** now uses `SettingsActionRow` with the riskF tint so the
  destructive action matches other destructive rows (Delete account, Disconnect
  brokerage) instead of being a bespoke full-width destructive button.
- `ScoreExplanationView` / `MethodologyView` switched from `cardPadding` to
  `screenPadding` + `largeSpacing` — they're screens, not cards.

---

## 9. Chrome — ContentView & MainTabView (`ios/Clavis/App/ContentView.swift`)

- `OfflineStatusBanner` used raw `.red`, `.secondary`, and `Color(white: 0.14)`
  values that broke in dark mode and didn't match other cards. Rebuilt with
  design tokens (`textPrimary` / `textSecondary` / `riskD`, `Color.surface`,
  `Color.border`, `ClavisTheme.cornerRadius`) and added a `wifi.slash`
  icon.
- `LoadingView` was a bare spinner. Now shows the `ClavisMonogram` above a
  subtler `textSecondary`-tinted spinner — consistent with the login screen
  and gives brand presence on cold start.

---

## Net effect

- **10 files changed**, ~1,200 lines of dead code removed.
- Four new shared components (`ClavisMonogram`, `ClavisPrimaryButton`,
  `ClavisSecondaryButton`, `ClavisSmallButton`) now back all primary/secondary/
  chip buttons across onboarding, auth, dashboard, and digest.
- Score bands now agree with the underlying model.
- Every remaining card/chip shares the same corner-radius language (card 12,
  inner 10). No more `Capsule` / radius 8 / radius 6 outliers on key surfaces.
- Onboarding, login, and the five main tabs each have consistent top spacing,
  title sizing, and destructive/action row treatments.
