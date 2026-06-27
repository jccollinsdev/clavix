# Onboarding "Analyze → Reveal" Redesign: Handoff

Last updated: 2026-06-25. Owner of next steps: whoever picks this up.

This document is a full handoff for the onboarding flow where a new user enters their
holdings, answers a few quick questions, and gets their first personalized portfolio
rating (the "aha" moment) right before the paywall. It covers what the flow does now,
every UI decision and why we made it, the constraints you must not break, the dead ends
we already walked down so you do not repeat them, and the open items.

If you read nothing else, read **Hard constraints** and **Lessons learned**.

## Files

- `ios/Clavis/ViewModels/OnboardingViewModel.swift` (flow state machine + reveal data builder)
- `ios/Clavis/Views/Onboarding/OnboardingContainerView.swift` (all onboarding views, ~1780 lines)
- `ios/Clavis/DesignSystem/` (tokens: `ClavisTypography`, the `Color.*` palette, `ClavixLayout`, `ClavixGradeBadge`)
- Methodology source of truth: `docs/CLAVIX_TRUTH.md` (grade bands, what each dimension means)

## What this app is (context you need before touching copy)

Clavix is an informational portfolio risk-rating app. It rates a holding or a portfolio
on a 0 to 100 safety score and a letter grade (AAA down to D). It does **not** make
recommendations, give personalized financial advice, or tell anyone to buy or sell. Every
piece of onboarding copy has to stay on the right side of that line. "Here is how your
book scores and why" is fine. "You should trim NVDA" is not.

The score is built from five risk dimensions, all oriented so **higher is safer/stronger**:

| Key  | Display name       | What it measures (current copy)                              | Backend field    |
|------|--------------------|--------------------------------------------------------------|------------------|
| FIN  | Financial Health   | balance-sheet strength and profitability                     | financialHealth  |
| NEWS | News Sentiment     | the tone of recent coverage                                  | newsSentiment    |
| MAC  | Macro Resilience   | how well it holds up against rates and the broad market      | macroExposure    |
| SEC  | Sector Resilience  | how diversified it is across sectors                         | sectorExposure   |
| VOL  | Price Stability    | how steady the price tends to be                             | volatility       |

Note the display names are deliberately the "safer = higher" framing. The backend fields
`macroExposure`, `sectorExposure`, `volatility` sound like risk (more = worse) but the
stored values are already inverted to safety scores (more = better). Do not re-invert them.

## The flow (state machine)

Two `OnboardingPage`s: `.welcome` and `.addPortfolio`. Inside `.addPortfolio` there is a
second, finer state machine, `AhaPhase`, with three cases:

```
AhaPhase: .input  ->  .questions  ->  .reveal
```

The live path a real user takes:

1. **Welcome screen** (`OnboardingWelcomeSetupView`, page `.welcome`). Logo grid, greeting,
   and the holdings entry table. The user types tickers + share counts here. The forward
   arrow calls `viewModel.continueToAnalysis()`. If that returns true, `nextPage()` moves
   to `.addPortfolio`.
2. `continueToAnalysis()` validates synchronously (at least one ticker with shares > 0, no
   unsupported tickers), then calls `enterQuestions()` (sets `ahaPhase = .questions`) and
   `startPreparingHoldings(...)`, which **resolves/scores the tickers in the background**
   while the user is on the questions screen. This is the key latency trick: the 1 to 2
   second network resolve happens under the questions, so there is no spinner between
   screens. Returns true.
3. **Questions screen** (`AhaQuestionsScreen`, phase `.questions`). Three quick questions
   (details below). "See my rating" calls `finishQuestions()`.
4. `finishQuestions()` awaits the background `prepareTask`, surfaces an unsupported-ticker
   error if one slipped through, otherwise calls `runAnalysis()`.
5. `runAnalysis()` builds the reveal data (`buildReveal`), persists the answers to
   UserDefaults (presentation only), kicks off holding persistence in the background, and
   sets `ahaPhase = .reveal`. **There is no separate "analyzing" phase or interstitial
   animation.** The build animation now lives inside the reveal screen's radar card.
6. **Reveal screen** (`AhaRevealScreen`, phase `.reveal`). Header animates from
   "Analyzing your portfolio" to "Your portfolio's results"; the radar assembles signal by
   signal; then the weakest-metric card, strongest-metric card, locked detail, and the
   trial CTA fade in. CTA leads to the paywall.

There is also a legacy `.input` screen (`AhaInputScreen`, "What do you own?" / "the
ledger") that is no longer on the live path (the welcome screen does entry now) but is
still compiled. Its "Grade my portfolio" button routes through `enterQuestions()` so it
behaves identically if it ever gets re-enabled. Leave it or delete it deliberately, but do
not let it diverge from the live path.

## Screen-by-screen decisions

### Welcome / holdings entry (`OnboardingWelcomeSetupView`, `OnboardingHoldingsEntry`)

- `OnboardingLogoGrid`: four rows of well-known company favicons in a brick layout that
  intentionally overflows the screen on both edges (tiles sized to 5.5 per row so 6 tiles
  clip at both sides) with a top-to-bottom fade mask. It is decoration that signals "we
  cover real companies." Favicons load from Google's favicon service by domain.
- Greeting uses the social first name if we have one ("Hey {name}, let's set up your
  portfolio."), else a neutral fallback.
- Entry table is a bordered card with a "YOUR HOLDINGS / SHARES" mono header, numbered
  rows (`01`, `02`, ...), ticker + shares fields, and an "Add position" row. Ticker field
  forces character autocapitalization and disables autocorrect.
- Forward action is a single 44pt square dark button with a right arrow, pinned bottom
  trailing. It shows a spinner while `isPreparingAnalysis` is true.

### Questions (`AhaQuestionsScreen`)

Header: eyebrow "YOUR PROFILE", title "How you invest.", sub "A few details so your rating
speaks to how you actually invest." (We deliberately softened this from earlier assertive
phrasings. See Lessons.)

Three question blocks, each a wrapping set of chips (`OnboardingChoiceChip` laid out by the
custom `FlowLayout`):

1. **"What matters to you?"** caption "Pick up to 3." Multi-select, capped at 3
   (`OnboardingViewModel.maxPriorities`). Options are the five dimensions with friendly
   labels: "Financial health", "News & headlines", "The economy", "Sector concentration",
   "Price swings". At the cap, unselected chips dim (`dimmed: true`, 0.55 opacity) but the
   user can still deselect a chosen one. Backed by `priorities: Set<OnboardingPriority>`.
2. **"What's your investment horizon?"** single-select: "Less than 1 year", "1 to 5 years",
   "More than 5 years". Concrete timeframes, not jargon like "I trade actively."
3. **"What's your risk tolerance?"** single-select: "Conservative", "Balanced", "Aggressive".

"See my rating" is enabled only when `questionsComplete` (at least one priority + timeline
+ risk tolerance all set). The disabled state is a bordered, `surfaceElevated`-filled
button with `textSecondary` text, not a washed-out grey (the earlier grey read as broken).

### Reveal (`AhaRevealScreen`)

Vertical stack, spacing 16:

1. **Header** that swaps on `analysisDone`:
   - Building: eyebrow "ANALYZING", "Analyzing your portfolio.", subtitle "Scoring your N
     holdings across five risk metrics."
   - Done: eyebrow "RISK PROFILE", "Your portfolio's results.", then a row with
     `ClavixGradeBadge(size: 44)` + big mono score `NN` + `/100` + a colored risk-tier
     label (e.g. "LOW RISK"), then a one-sentence `gradeDescriptor`.
2. **`AhaRiskProfileCard`**: the radar that builds signal by signal (see next section).
   Calls back `analysisDone = true` when the build finishes.
3. After done, fading in:
   - **Weakest-metric card** (`weakestCard` -> `metricCard`, amber/`warn` tone).
   - **Strongest-metric card** (`strongestCard`, green/`good` tone), only shown if the
     strongest dimension differs from the weakest.
   - **`AhaLockedDetail`**: locked "See what's driving {area} in {ticker}" teaser.
   - **CTA**: "Continue to 14-day trial" + "FREE FOR 14 DAYS · CANCEL ANYTIME" caption.

#### Grade meaning helpers (in `AhaRevealScreen`)

- `gradeTier(grade)`: AAA/AA = "Very low risk", A = "Low risk", BBB = "Moderate risk",
  BB = "Elevated risk", B = "High risk", else "Very high risk".
- `gradeTierColor(grade)`: AAA/AA/A = `.good`, BBB/BB = `.warn`, else `.bad`.
- `gradeDescriptor(reveal)`: one sentence combining portfolio shape + count of key risks
  (dimensions scoring < 55), spelled out as one/two/three. Example: "A resilient, balanced
  portfolio with one key risk to watch." It does not repeat the grade letter or tier word.

#### Metric deep-dive cards (`metricCard`)

Each card has: eyebrow (WEAKEST / STRONGEST METRIC) in the tone color, the metric name,
the average `NN/100` in the tone color, a `metricMeaning` line ("Measures {explanation}.
Each holding is scored 0 to 100, where higher is stronger, then averaged."), a "BY HOLDING"
breakdown (only when there is more than one holding) with a ticker + mini progress bar +
value per holding, and a `narrative` sentence that names the culprit/leader holding and the
`band` word (weak / below-average / moderate / solid / strong). The per-holding values come
from `weakestBreakdown` / `strongestBreakdown` on the reveal, which are real per-ticker
dimension scores, sorted worst-first (weakest) or best-first (strongest).

## The radar (`AhaRiskProfileCard` + `AhaRiskRadar`)

This is the centerpiece and the part most likely to bite you, so it gets its own section.

### Why a radar

We tried a row of horizontal bars first. The user called it "hideous, gives absolutely
nothing." A five-axis radar reads as "there is real multi-dimensional math here" at a
glance, and it has a natural shape (a lopsided polygon) that makes a weak axis obvious.

### How it builds

`AhaRiskRadar` is a **pure renderer**: it draws exactly the `values: [Double]` array it is
handed, plus a `highlights: [String: Color]` map for which axes to emphasize. It has no
animation logic of its own.

`AhaRiskProfileCard` owns the animation. It keeps `@State displayed: [Double]` (starts all
zeros) and steps it frame by frame, mutating the array so the Canvas redraws each time.
`SwiftUI`'s `withAnimation` does **not** interpolate values inside a `Canvas` that reads an
array of state, so we drive it manually with `await sleep(...)` between frames. This is
deliberate; do not try to replace it with implicit animation, it will not work.

Sequence (`run()`):
1. Wait 0.35s.
2. For each dimension in order: set `activeIndex = i`, call `scanAxis(i)`, wait 0.08s.
3. Clear `activeIndex`, set `finished = true`, wait 0.15s, call `onComplete()`.

`scanAxis(i)` is tuned to read as "real computation, then settling," not jitter for its own
sake. Current tuning (after several rounds of "too jittery" / "too smooth" / "a little
smoother"): 16 scan frames, a center that ramps from 0.3 to 1.0 of the target, a random
spread that starts at 48 and narrows with `(1 - t*t)`, damping factor 0.46 toward each jump
target (higher damping = smoother), 0.044s per frame, then a small overshoot (+7) and a
4-step settle onto the true value. If you get another "too jittery/too smooth" note, this
function and those constants are the only thing to touch.

`statusArea` under the radar shows, during the build, a green pulse dot + "Analyzing
{dimension}" + the dimension explanation + the live value; when finished it shows a single
`textTertiary` line: "Each holding scored across five risk metrics, then weighed into one
score."

### Highlights (the two-color rule)

`highlightMap`:
- While building: the active axis is highlighted in `.textPrimary` (neutral, just "this is
  the one being computed now").
- When finished: weakest axis (`blindSpot.key`) in `.warn` (amber), strongest axis in
  `.good` (green), everything else neutral. Highlighted axes get a larger vertex dot and a
  semibold, colored label.

The user explicitly asked for **both** extremes highlighted, not just the strongest. If you
ever see only one color on the finished radar, that is the regression to catch.

### Reduce Motion + fallback

- Reduce Motion or fewer than 3 dimensions: skip the animation, set `displayed` to the real
  averages, mark finished, call `onComplete()` immediately.
- Fewer than 3 dimensions also swaps the radar for a stack of `AhaSignalRow` bars (a radar
  needs at least a triangle). The fallback rows highlight the focus/weakest row in `.warn`.

## The reveal data builder (`OnboardingViewModel.buildReveal`)

Static function, takes the resolved `[TickerSearchResult]` plus the user's `priorities` and
`timeline`. Returns an `AhaReveal?`. Key points:

- `score` = mean of per-holding `resolvedSafetyScore`. `grade` = `PortfolioMath.grade(forScore:)`.
  **These are objective and must never be touched by personalization.**
- `dimensions`: for each of the five dims, average the per-holding values pulled from
  `r.sharedAnalysis?.riskDimensions`. `blindSpot` = lowest-average dimension.
- `focus` (presentation only): among the dimensions the user said they care about, the
  lowest-scoring one (most worth flagging); falls back to `blindSpot` if they picked none.
  `focusIsConcern` records whether it came from a stated priority.
- `strongest`: highest-average dimension distinct from the weakest where possible.
- `weakestBreakdown` / `strongestBreakdown`: real per-holding `MetricContribution`s
  (ticker + value) for the weakest/strongest dimension, sorted worst-first / best-first.
  These power the "BY HOLDING" bars and the culprit/leader narrative.
- `sourceCount`: sum of real `sharedAnalysis?.sourceCount` across holdings. Currently **not
  shown** in the UI (see Lessons on the "big number" saga).

## Hard constraints (do not break these)

1. **Personalization is presentation-only.** The questions steer what the reveal leads with
   and how it is framed, never the grade or score math. Two users with the same holdings
   must get the same grade regardless of their answers. The `buildReveal` signature takes
   `priorities`/`timeline` only to choose `focus`, never to reweight `score`.
2. **Never fabricate numbers.** Every number shown (scores, per-holding values, any counts)
   must come from real backend data. We were asked more than once for an impressive "148
   data points / 11,234 articles" line and refused to invent it. If you want a big real
   number, surface a genuine backend count (see Open items), do not make one up.
3. **No recommendations / no advice.** Informational framing only. No "buy/sell/trim."
4. **No em dashes** in any copy or docs (project-wide preference). Use commas, colons,
   periods, or parentheses. The same goes for en dashes.
5. **Grade bands are canonical.** 71 maps to A. This surprised the user ("isn't that BB?")
   but it is correct per `docs/CLAVIX_TRUTH.md` (90+ AAA, 80-89 AA, 70-79 A, 60-69 BBB,
   50-59 BB, 40-49 B, ...). Do not "fix" it.

## Design system tokens used

- Type: `ClavisTypography.inter(size, weight:)` for UI text, `ClavisTypography.mono(size)`
  for numbers/codes/eyebrows, `ClavisTypography.label` for tracked eyebrows.
- Color: `.textPrimary` / `.textSecondary` / `.textTertiary` / `.ink2`, surfaces
  `.surface` / `.surfaceElevated` / `.backgroundPrimary`, `.border`, semantic `.good`
  (green), `.warn` (amber), `.bad` (red).
- Layout: `ClavixLayout.cardRadius`, `ClavixLayout.controlRadius`. Cards are
  `Color.surface` with a 1pt `.border` stroke and the card radius.
- `ClavixGradeBadge(grade, size:)` renders the letter grade chip.
- `OnboardingStickyBar(step:total:)` is the top progress bar (step 1 or 2 of 2).
- Chips/buttons use a 4pt corner radius (`RoundedRectangle(cornerRadius: 4)`), selected =
  `textPrimary` fill + `backgroundPrimary` text, unselected = `surface` + `border`.

## Lessons learned (the dead ends, so you do not repeat them)

- **The interstitial "analyzing" animation is a trap.** Fast enough to not bore = too fast
  to read; slow enough to read = boring. We removed the standalone analyzing phase entirely.
  Its two real jobs (cover the resolve latency, build anticipation) are now done by the
  background prepare task + the questions screen + the in-card radar build. Do not bring
  back a full-screen multi-second "computing" theater.
- **Terminal/streaming-text aesthetics read as "hacker," not as our brand.** An early
  version streamed dossier text. The user: "feels kinda hacker, not our font." Everything is
  cards, Inter/mono, and our palette now. Keep it that way.
- **Horizontal bars underwhelm; the radar lands.** Bars were "hideous, gives absolutely
  nothing." The radar communicates multi-dimensional analysis far better.
- **The "big impressive number" saga.** The user wanted a large number ("148 data points,
  11,234 articles") to make the math feel substantial. We will not fabricate, so we tried
  the real `sourceCount`. Across a 2-holding book that was "only 12 sources," which
  underwhelmed, so we removed it. The honest fix is a real backend count (Open items), not
  a fake one. Hold this line.
- **"Always news sentiment weakest" is a real data artifact, not fake personalization.** The
  news dimension is sparse/low in the backend for most tickers (alphabetical coverage cliff,
  see the news-coverage audit). So the weakest metric is often NEWS regardless of holdings.
  That is a backend coverage problem, not something to paper over in the UI.
- **Copy kept drifting too assertive; the user pulled it back every time.** "Your portfolio
  risk profile" became "Your portfolio's results." "Before we rate it" was cut. "You said
  news sentiment..." felt "sketchy" and was removed. Lean toward neutral, observational,
  slightly understated. When in doubt, less assertive.
- **Manual sim driving is off-limits for the assistant.** The user wants to test by hand.
  Standing instruction: "don't try to manually test, just relaunch in XCode sim every time
  so that I can manually test." Build and relaunch, then stop.
- **One macOS gotcha (sim only, no app impact):** the iOS Simulator's keyboard can get
  hijacked by the macOS press-and-hold accent menu. Fix is
  `defaults write com.apple.iphonesimulator ApplePressAndHoldEnabled -bool false` then
  relaunch Simulator. This is a local convenience only, nothing to do with the app.

## Open items / standing offers (none are approved yet)

- **Real backend count for a genuine "big number."** Surface a real `data_points` /
  `articles_analyzed` / per-dimension sub-factor count (financial ratios, beta, article
  counts) via the API so the deep-dive and methodology copy can show an honest, substantial
  number. This needs backend work and was offered but not approved. Do not start without a
  go-ahead.
- **News coverage breadth.** The NEWS dimension being chronically weakest is a backend
  coverage issue (most tickers past the alphabet's start have little/no news). Tracked
  separately in the news-coverage audit. The onboarding UI cannot fix this; it just honestly
  reflects it.
- **Legacy `AhaInputScreen`.** Decide whether to keep the old "ledger" input screen or
  delete it. It is off the live path but still compiled and wired to route through
  `enterQuestions()`.

## Build / test

The assistant builds and relaunches; the user tests manually. To relaunch in the simulator
use the XcodeBuildMCP tools (`session_show_defaults` first to confirm project/scheme/sim are
set, then `build_run_sim`, usually with empty args). Confirm it compiles before relaunching.
Do not drive the simulator UI on the user's behalf.

Manual path to verify: welcome -> add a ticker + shares -> arrow -> three-question screen ->
pick a concern + horizon + risk -> "See my rating" -> reveal with the radar building signal
by signal, then the weakest/strongest metric cards (with per-holding bars when there is more
than one holding), then the locked teaser and trial CTA. Worth checking: a single holding
(breakdown bars hidden, narrative uses that holding), three or more holdings, and Reduce
Motion on (radar settles instantly, still reaches the finished state).
