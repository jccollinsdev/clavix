# Clavix: Remaining Code Work Before Launch

**Created:** 2026-06-15  
**Purpose:** Complete inventory for any agent picking up this codebase cold. Covers every coding task remaining before public TestFlight and App Store launch. Admin/user-only tasks are out of scope here.

**Codebase layout:**
- `ios/Clavis/` — SwiftUI app (Xcode scheme: Clavis, target iPhone 17 sim)
- `backend/app/` — FastAPI backend (Python)
- `supabase/migrations/` — DB migrations (applied via `mcp__supabase__apply_migration`)
- Production VPS: `sansar@134.122.114.241`, deployed via `ssh clavix-vps 'cd /opt/clavis && sudo -n git pull origin main && sudo -n docker compose restart backend'`
- Supabase project ID: `uwvwulhkxtzabykelvam`

**What is already done (do not re-do):**
- StoreKit 2 full purchase flow: `ios/Clavis/Services/SubscriptionManager.swift` (complete)
- Google Sign-in: working in production (confirmed via `auth.identities`)
- Apple Sign-in: iOS code complete (`SupabaseAuthService.swift`, `AuthViewModel.swift`) — needs Supabase provider enabled (admin task, not code)
- APNs p8 key: loaded in backend (`/health` returns `apns: configured`)
- Trial detection: `SubscriptionManager.checkCurrentEntitlement()` calls server, gets "trial", sets `isPro = true` correctly
- Trial holding/watchlist cap fix: `backend/app/routes/holdings.py` and `watchlists.py` both call effective-tier logic that honors `trial_ends_at`
- Weekend scheduler guard: all CronTriggers in `scheduler.py` have `day_of_week="mon-fri"`
- Snapshot upsert fix: `_upsert_ticker_snapshot` in `ticker_cache_service.py` uses `(ticker, snapshot_date)` unique key
- Health endpoint: `/health` returns `last_recompute.status + completed_at` from `ticker_refresh_jobs`

---

## P0: Required before any TestFlight build

### 1. ETF backfill

**Problem:** QQQ, XLF, XLK, XLE, XLV, XLI, XLC, XLY, XLP, XLU, XLRE, XLB, AGG, BND, VTI, IWM, SCHD are not in the `ticker_universe` table. Users whose portfolios contain these tickers get "not supported" errors.

**What to do:**

Option A (preferred — migration): Write a Supabase migration that inserts the ETFs directly into `ticker_universe`. Each row needs:
```sql
INSERT INTO ticker_universe (ticker, company_name, exchange, sector, industry, index_membership, is_active, priority_rank, updated_at)
VALUES
  ('QQQ', 'Invesco QQQ Trust', 'NASDAQ', 'Technology', 'ETF', 'ETF', true, 1, now()),
  ('XLF', 'Financial Select Sector SPDR', 'NYSE', 'Financials', 'ETF', 'ETF', true, 2, now()),
  -- ... etc
```

The `index_membership = 'ETF'` value is important — it signals to the pipeline that this is an ETF.

Option B (script): Call `ensure_ticker_in_universe(supabase, "QQQ")` for each ETF via the admin API or a one-off script. This auto-populates from Finnhub metadata.

**Financial health handling for ETFs:** `_build_financial_health_inputs()` in `backend/app/services/ticker_cache_service.py` line 400 already handles this correctly — ETFs return no P/E or debt ratios, so `ratios_available < 2` → `limited_data: True` → financial health excluded from composite. No code change needed in the pipeline itself.

**After inserting into ticker_universe:** Trigger a structural refresh for each ETF via the admin API to populate their first snapshot:
```bash
# For each ETF ticker:
curl -X POST https://clavis.andoverdigital.com/trigger-analysis -H "Authorization: Bearer <admin_token>" -d '{"ticker": "QQQ"}'
```

**Files to modify:**
- Create `supabase/migrations/YYYYMMDD_etf_backfill.sql`

---

### 2. iOS crash reporter (Sentry)

**Problem:** No crash reporting exists. If the app crashes in TestFlight, there is no signal.

**What to do:**

Step 1 — Add Sentry SDK via Swift Package Manager:
- URL: `https://github.com/getsentry/sentry-cocoa` (minimum version 8.0.0)
- In Xcode: File > Add Package Dependencies > paste URL > add `Sentry` target

Step 2 — Store the DSN in `ios/Clavis/Config/Secrets.xcconfig` (existing file) and `ios/Clavis/Config/Secrets.local.xcconfig`:
```
SENTRY_DSN = https://YOUR_KEY@o123.ingest.sentry.io/PROJECT_ID
```

Step 3 — Initialize in `ios/Clavis/App/ClavisApp.swift`. The `@main` struct is `ClavisApp`. Add to `AppDelegate.application(_:didFinishLaunchingWithOptions:)`:
```swift
import Sentry

// Inside didFinishLaunchingWithOptions:
SentrySDK.start { options in
    options.dsn = Bundle.main.infoDictionary?["SENTRY_DSN"] as? String
    options.tracesSampleRate = 0.1
    options.profilesSampleRate = 0.0
    options.environment = "production"
}
```

Step 4 — Add `SENTRY_DSN` to `ios/Clavis/App/Info.plist` as a variable pulled from xcconfig:
```xml
<key>SENTRY_DSN</key>
<string>$(SENTRY_DSN)</string>
```

**Note:** Create the Sentry project at sentry.io first and get the DSN. The Sentry DSN is not a secret (it's embedded in the app binary) but keep it out of git anyway by using xcconfig injection.

**Files to modify:**
- `ios/Clavis/App/ClavisApp.swift` (add import + init)
- `ios/Clavis/App/Info.plist` (add SENTRY_DSN key)
- `ios/Clavis/Config/Secrets.xcconfig` (add SENTRY_DSN=)
- `ios/Clavis/Config/Secrets.local.xcconfig` (add SENTRY_DSN=)

---

### 3. Expired-trial lock screen

**Problem:** When a user's trial expires (`SubscriptionManager.status == .notSubscribed` or `.expired`) and they haven't subscribed, the app shows `MainTabView` normally. They then get silent 403 errors when trying to add holdings or use pro features. There is no hard paywall lock screen.

**What to do:**

`ios/Clavis/App/ContentView.swift` — the `authRoot` computed property (lines 50-66) decides what to show after authentication. Currently:
```swift
} else if authViewModel.isAuthenticated {
    if authViewModel.hasCompletedOnboarding || allowDebugBypassLiveEntry {
        MainTabView()           // <-- shows even for expired trial users
    } else {
        OnboardingContainerView()
    }
}
```

Change to gate on `SubscriptionManager.status`:
```swift
} else if authViewModel.isAuthenticated {
    if authViewModel.hasCompletedOnboarding || allowDebugBypassLiveEntry {
        if case .notSubscribed = subscriptionManager.status {
            ExpiredPaywallView()    // new view — see below
        } else if case .expired = subscriptionManager.status {
            ExpiredPaywallView()
        } else {
            MainTabView()
        }
    } else {
        OnboardingContainerView()
    }
}
```

`ContentView` already has `@EnvironmentObject var authViewModel: AuthViewModel`. Add `@EnvironmentObject var subscriptionManager: SubscriptionManager` — it is already injected in `ClavisApp.swift` line 16.

**Create `ExpiredPaywallView`** (new file `ios/Clavis/Views/Paywall/ExpiredPaywallView.swift`):
- Full-screen paywall with messaging: "Your free trial has ended"
- Shows `PaywallView` content (already exists at `ios/Clavis/Views/Paywall/PaywallView.swift`)
- Shows "Restore purchases" button
- Shows logout option at bottom

The simplest implementation: just show `PaywallView(triggerContext: .generic)` full-screen with an additional "Sign out" button at the bottom.

**Edge case:** `status == .unknown` means the check hasn't completed yet — do NOT show the paywall in this case. Only gate on `.notSubscribed` and `.expired`. During the trial, `status == .trial(expiresAt:)` → `isPro = true` → show MainTabView.

**Files to create/modify:**
- `ios/Clavis/App/ContentView.swift` (modify `authRoot`)
- `ios/Clavis/Views/Paywall/ExpiredPaywallView.swift` (new)

---

## P1: Required for clean TestFlight experience

### 4. SettingsView tier badge shows "FREE" for trial users

**Problem:** `ios/Clavis/Views/Settings/SettingsView.swift` lines 403, 406, 409 display `viewModel.subscriptionTier.uppercased()` for the tier badge. `viewModel.subscriptionTier` reads the raw `subscription_tier` DB column (always "free" for trial users). Trial users see "FREE" badge when they should see "TRIAL".

**What to do:**

`ios/Clavis/ViewModels/SettingsViewModel.swift` line 26 has `@Published var subscriptionTier: String = "free"`. Line 63 sets it from `prefs.subscriptionTier`. The API response includes `effective_tier` — check if the `UserPreferences` model already decodes it.

Check `ios/Clavis/Models/UserPreferences.swift` for an `effectiveTier` field. If present, update `SettingsViewModel` line 63 to use `prefs.effectiveTier ?? prefs.subscriptionTier ?? "free"` instead. If not present, add `let effectiveTier: String?` to `UserPreferences`.

Then `planSummary` (SettingsView line 191) and the badge (lines 403–409) will show "TRIAL" correctly.

**Note:** `isFreeTier` is already fixed to use `SubscriptionManager.shared.isPro` — this is only about the display text of the badge.

**Files to modify:**
- `ios/Clavis/ViewModels/SettingsViewModel.swift`
- `ios/Clavis/Models/UserPreferences.swift` (if `effectiveTier` not present)

---

### 5. Foreground tier refresh

**Problem:** When a user's trial expires while the app is in the background, `SubscriptionManager.isPro` stays `true` until the next cold launch. The subscription manager never re-checks on app foreground.

**What to do:**

In `ios/Clavis/App/ClavisApp.swift` or `ios/Clavis/Services/SubscriptionManager.swift`, add a foreground observer:

In `SubscriptionManager.init()`:
```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(appDidBecomeActive),
    name: UIApplication.didBecomeActiveNotification,
    object: nil
)
```

Or in `ClavisApp.swift` body:
```swift
.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
    Task { await SubscriptionManager.shared.refresh() }
}
```

**Files to modify:**
- `ios/Clavis/Services/SubscriptionManager.swift` or `ios/Clavis/App/ClavisApp.swift`

---

### 6. Grade stability: financial_health day-to-day bounce

**Problem:** AAPL's financial health score bounces significantly (e.g., 62 → 80 → 88) across consecutive days despite no real fundamental change. This makes the app feel unreliable.

**Investigation needed — check these files:**

1. `backend/app/services/ticker_cache_service.py` — `_build_financial_health_inputs()` at line 400. It reads Finnhub fundamentals from `upsert_ticker_metadata`. Determine whether Finnhub returns slightly different values on different API calls.

2. `backend/app/jobs/fundamentals_sweep.py` — weekly Finnhub sweep. If the daily recompute re-fetches fundamentals every day (instead of using the weekly sweep's cached values), different Finnhub responses explain the bounce.

3. `backend/app/services/ticker_metadata.py` — check if fundamentals are cached/stored in Supabase or always live-fetched from Finnhub per recompute.

**Likely fix:** Fundamentals should be frozen at weekly cadence. The daily recompute should read from the stored Supabase metadata (from the weekly sweep) rather than calling Finnhub live on each run. Add a check: if `ticker_metadata.fundamentals_updated_at` is less than 7 days ago, use stored values rather than re-fetching.

Alternatively, apply the same EMA smoothing used for score history (`smooth_score_with_history` in `structural_scorer.py`) to the financial health input itself before scoring.

**Files to investigate/modify:**
- `backend/app/services/ticker_cache_service.py` (`_build_financial_health_inputs`, around line 400)
- `backend/app/services/ticker_metadata.py`
- `backend/app/jobs/fundamentals_sweep.py`

---

### 7. Drop dead DB columns

**Problem:** `ticker_risk_snapshots` still has `news_sentiment` and `macro_exposure` columns (non-`_dim` versions) that have been NULL for all rows since at least 2026-05-30. They waste space and confuse future queries.

**What to do:**

Create migration `supabase/migrations/YYYYMMDD_drop_dead_snapshot_columns.sql`:
```sql
ALTER TABLE public.ticker_risk_snapshots
  DROP COLUMN IF EXISTS news_sentiment,
  DROP COLUMN IF EXISTS macro_exposure;
```

**Verify first** that no code reads these columns:
```bash
grep -rn "\"news_sentiment\"\|\"macro_exposure\"" backend/app/ --include="*.py" | grep -v "_dim\|news_sentiment_dim\|macro_exposure_dim"
```

The `_dim` variants (`news_sentiment_dim`, `macro_exposure_dim`) are the real columns and must NOT be dropped.

**Files to create:**
- `supabase/migrations/YYYYMMDD_drop_dead_snapshot_columns.sql`

---

## P2: Pre-public-launch

### 8. Funnel analytics

**Problem:** No analytics events exist. When the beta goes live, you cannot tell whether users are reaching the paywall, starting trials, or converting to paid.

**Minimum viable events to add:**

| Event | Where to fire | File |
|---|---|---|
| `trial_started` | After `checkCurrentEntitlement()` returns "trial" for the first time | `SubscriptionManager.swift` |
| `paywall_viewed` | In `PaywallView.onAppear` | `PaywallView.swift` |
| `purchase_tapped` | Before `product.purchase()` | `SubscriptionManager.swift` `purchase()` |
| `purchase_success` | After `transaction.finish()` | `SubscriptionManager.swift` `purchase()` |
| `restore_tapped` | Before `AppStore.sync()` | `SubscriptionManager.swift` `restorePurchases()` |

**Recommended library:** Mixpanel or PostHog (PostHog is open source and has a Swift SDK). No analytics library is currently in the project. Add via SPM.

Alternatively, log events to the backend via a simple `POST /analytics/event` endpoint rather than adding a third-party SDK dependency. This keeps you in control of the data.

---

### 9. iOS disk cache (stale-while-revalidate)

**Problem:** Cold launch always shows empty state while fetching. If the network is slow or offline, users see nothing.

**What to do:**

`ios/Clavis/Services/APIService.swift` — for the main data calls (`fetchHoldings`, `fetchTodayDigest`, `fetchAlerts`), add a simple `UserDefaults` or file-based JSON cache:
1. On successful fetch, write the response JSON to a cache file keyed by endpoint
2. On next launch, read from cache immediately (show stale data)
3. Kick off the live fetch in background; replace stale data when it arrives

This is a quality-of-life feature, not a launch blocker. Do it after beta feedback confirms cold launch UX is a real pain point.

**Files to modify:**
- `ios/Clavis/Services/APIService.swift`

---

### 10. `REFRESH_CONCURRENCY` as env var

**Problem:** `REFRESH_CONCURRENCY = 2` is hardcoded in `backend/app/pipeline/scheduler.py` around line 4792. Cannot tune at deploy time without a code change.

**What to do:**

Change to:
```python
REFRESH_CONCURRENCY = int(os.getenv("REFRESH_CONCURRENCY", "2"))
```

Add `REFRESH_CONCURRENCY=2` to `/opt/clavis/.env` on the VPS.

**Files to modify:**
- `backend/app/pipeline/scheduler.py`

---

## Already done — do NOT re-implement

These were completed in the 2026-06-15 session (commits 71fcbbe26, 5f884ea04, 3448e44b7, plus earlier commits):

- Macro/sector snapshot CronTriggers: `day_of_week="mon-fri"` added
- `_upsert_ticker_snapshot`: uses `(ticker, snapshot_date)` unique key, normalizes `snapshot_type` to "daily"
- `_coerce_snapshot_date`: returns prior Friday on weekends
- `holdings.py` and `watchlists.py`: `_get_subscription_tier` honors `trial_ends_at`
- `polygon.py` `fetch_aggs`: caches empty results (removed `if results:` guard)
- `/health`: returns `last_recompute` from `ticker_refresh_jobs`
- `macro_regression.py` `_align_series`: skips dates with missing factor data instead of filling 0.0
- `Methodology.swift`: `limitedData` field added to `MethodologyNewsSentiment`
- `TickerDetailView.swift`: news_sentiment `isLimited` uses `methodology.limitedData` not `articleCount < 3`
- `RiskScore.swift`: `AIDimensions` uses `decodeFlexibleDoubleIfPresent`
- `DigestViewModel`, `HoldingsListView`, `SettingsView`, `OnboardingContainerView`: `subscriptionTier == "free"` feature gates replaced with `!SubscriptionManager.shared.isPro`
- `scheduler.py` `on_conflict`: changed to `"ticker,snapshot_date"` after 20260615 migration
- Three `snapshot_type` filters in scheduler hysteresis queries removed

---

## Admin tasks that unblock code tasks

These are NOT code tasks but block certain code paths from being testable:

| Admin task | Unblocks |
|---|---|
| Create `clavix_pro_monthly` IAP in App Store Connect at $19.99 | StoreKit `purchase()` — code is complete but needs a real product ID |
| Accept Paid Apps Agreement (banking + tax) | Real sandbox purchases |
| Enable Apple Sign-in provider in Supabase Dashboard → Auth → Providers | `signInWithApple()` in `SupabaseAuthService.swift` — code is complete |
| Enable Google provider redirect URI in Supabase (verify `clavix://auth/callback` is listed) | Needed if Google OAuth token refresh breaks |
| Toggle leaked-password protection in Supabase Dashboard → Auth → Providers → Email | Security baseline |
| Physical iPhone with push notification permission granted | APNs token registration (`PushNotificationManager.swift`) — untestable in sim |
