# TestFlight Coding Tasks — 2026-06-02

Priority: P0 = blocks TestFlight | P1 = must fix before external TF | P2 = polish before public launch | P3 = post-launch

---

## P0 — Blocks TestFlight

### P0-1 — Fix digest job crash (50% of users)
**Files:** `backend/app/pipeline/portfolio_compiler.py`, `backend/app/pipeline/scheduler.py`  
**Error:** `"sequence item 0: expected str instance, NoneType found"`  
**Where:** The daily digest job for users `7ff5a6c5` and `a4ba5a72` fails at 07:00 ET. The crash is a Python `str.join()` receiving a list where an element is `None`. The `_clean_text_list()` helper exists but is not used in all join call sites.  
**Acceptance criteria:** Both user digest jobs run to `completed` status; `scheduler_jobs.last_run_status = 'completed'` for all active users.  
**Test command:** `ssh clavix-vps 'sudo -n docker exec clavis-backend-1 python -m app.scripts.verify_digest_scheduler'`  
**Safe now:** ✅ Yes  
**Blocked by:** Nothing  
**Deploy:** `ssh clavix-vps 'cd /opt/clavis && sudo -n git pull origin main && sudo -n docker compose restart clavis-backend'`

### P0-2 — Remove brokerage from upgrade/paywall copy
**Files:**
- `ios/Clavis/Views/Settings/SettingsView.swift` — `SettingsUpgradeSheet`: "Verbose digest, **brokerage sync**, and CSV import are part of Clavix Pro."
- `ios/Clavis/Views/Onboarding/OnboardingContainerView.swift` — line 372: "Pro will unlock unlimited positions, **brokerage sync**, verbose morning reports..."  

**Fix:** Replace with the correct Pro pitch from `CLAVIX_LAUNCH_SCOPE_v1.md §2`:  
> "Unlimited holdings & watchlist, verbose morning briefing, 90-day score history across all 5 dimensions, advanced alerts, and the deepest audit view. $20/mo, 14 days free."  

Remove CSV import from paywall too if not implemented (it isn't). Label it "coming soon to Pro" at most.  
**Acceptance criteria:** No user-visible text says "brokerage sync" as a purchaseable feature.  
**Safe now:** ✅ Yes

### P0-3 — Add fast `/ping` endpoint to fix Cloudflare 524
**File:** `backend/app/main.py` or new `backend/app/routes/ping.py`  
**Problem:** `GET /health` performs Supabase queries and is too slow for Cloudflare's 30s read timeout, causing 524 errors. The public URL is essentially unavailable for health checks.  
**Fix:** Add `GET /ping` that returns `{"ok": true}` immediately with no DB checks. Keep `/health` for internal ops monitoring.  
**Acceptance criteria:** `curl https://clavis.andoverdigital.com/ping` returns 200 in <1 second.  
**Safe now:** ✅ Yes  
**Deploy:** Required after git push.

### P0-4 — Fix PrivacyInfo.xcprivacy — remove DeviceID
**File:** `ios/Clavis/Resources/PrivacyInfo.xcprivacy`  
**Problem:** The file declares `NSPrivacyCollectedDataTypeDeviceID` as collected, but the app does NOT collect device IDs (no IDFA, no IDFV, no persistent device identifier). The APNs token is not a "device ID" in Apple's taxonomy — it's an identifier under `NSPrivacyCollectedDataTypeDeviceID` only if it's used as a stable device identity, not just for push routing.  
**Fix:** Remove the DeviceID entry. Add the APNs token separately if needed (Apple's guidance on APNs tokens changed in 2024 — check current guidance, but APNs tokens are typically not required to be disclosed if used only for push delivery).  
**Acceptance criteria:** PrivacyInfo.xcprivacy contains only: Email Address, Name, User ID. No DeviceID entry.  
**Safe now:** ✅ Yes

### P0-5 — Write StoreKit 2 SubscriptionManager scaffold
**Files:** New `ios/Clavis/Services/SubscriptionManager.swift`, edits to `SettingsViewModel.swift`, `HoldingsViewModel.swift`, `AuthViewModel.swift`  
**Problem:** Zero StoreKit code exists. Subscription tier is read from the backend, not from Apple's StoreKit receipts.  
**What to build:**
1. `SubscriptionManager` class with `@MainActor`, `@Published var isPro: Bool`
2. Product loading: `Product.products(for: ["clavix_pro_monthly"])`
3. Transaction listener that updates `isPro` state and calls backend to sync tier
4. `purchase()` method that initiates StoreKit purchase and handles result
5. `restorePurchases()` method
6. Replace current `subscriptionTier == "free"` checks in ViewModels with `SubscriptionManager.shared.isPro`

**Product ID to use:** `clavix_pro_monthly` (must match what is created in App Store Connect — see admin checklist D5)  
**Acceptance criteria:** StoreKit purchase flow compiles and runs (even before real product IDs exist, the code should gracefully handle "product not found" in StoreKit sandbox).  
**Safe now:** ✅ Yes (can build scaffolding before App Store Connect products exist; full sandbox testing requires admin task D4-D7)  
**Blocked on:** App Store Connect subscription product creation (admin task D4-D7) for sandbox testing

---

## P1 — Must fix before external TestFlight

### P1-1 — Populate trial_started_at on new user creation
**File:** `backend/app/routes/preferences.py` — `_get_or_create_prefs()` function  
**Problem:** `trial_started_at` and `trial_ends_at` columns exist in `user_preferences` but are never set. Every user is therefore permanently on `free` with no trial. The product promises a 14-day Pro trial.  
**Fix:** When creating new user preferences (first login), set:
```python
"trial_started_at": datetime.now(timezone.utc).isoformat(),
"trial_ends_at": (datetime.now(timezone.utc) + timedelta(days=14)).isoformat(),
"subscription_tier": "pro"  # or leave "free" and check trial window separately
```
**Decision needed:** Does the 14-day trial grant `pro` tier immediately, or do we check trial window at access-time? Recommend: set `subscription_tier = "pro"` for new users, auto-downgrade after day 15 (via a background job or check-at-login).  
**Acceptance criteria:** New user signup results in `trial_started_at` set and `subscription_tier = "pro"` for 14 days.  
**Safe now:** ✅ Yes

### P1-2 — Backend enforcement for Free 3-holding limit
**File:** `backend/app/routes/holdings.py` — `_create_holding_sync()`  
**Problem:** The 3-holding limit for Free users is enforced only in the iOS UI. The backend API accepts `POST /holdings` regardless of tier. A savvy user or third-party client can add unlimited holdings via the API.  
**Fix:** In `_create_holding_sync()`, before inserting:
```python
prefs = supabase.table("user_preferences").select("subscription_tier").eq("user_id", user_id).single().execute()
tier = (prefs.data or {}).get("subscription_tier", "free")
if tier == "free":
    count = supabase.table("positions").select("id", count="exact").eq("user_id", user_id).execute().count
    if count >= 3:
        raise HTTPException(403, "Free accounts are limited to 3 holdings. Upgrade to Pro for unlimited.")
```
**Acceptance criteria:** `POST /holdings` returns 403 for a Free user with 3+ existing positions.  
**Safe now:** ✅ Yes

### P1-3 — Backend enforcement for Free 5-watchlist limit
**File:** `backend/app/routes/watchlists.py`  
**Problem:** Same issue as P1-2. Free limit is 5 watchlist items. Backend does not check.  
**Fix:** Same pattern: check tier + count before insert.  
**Acceptance criteria:** Adding a 6th watchlist item as Free user returns 403.  
**Safe now:** ✅ Yes

### P1-4 — Connect outside-universe add flow from SearchView empty state
**File:** `ios/Clavis/Views/Search/SearchView.swift`  
**Problem:** When a user searches for a ticker not in the universe, they see "No supported ticker matched" with a footnote "If a company is outside the tracked universe, Clavix will say so once you open it." But there is no "Add anyway" CTA. The backend supports `allow_outside_universe=true` but it's never called from the UI.  
**Fix:** When results are empty AND trimmedQuery looks like a ticker symbol (all-caps, 1-5 chars): show a secondary action "Add as untracked holding" that calls `addHolding(allowOutsideUniverse: true)`.  
**Acceptance criteria:** A user can type "LUNR", get no results, tap "Add as untracked holding", and the position is created with `outside_universe = true`. The holding shows the limited-data banner in TickerDetailView.  
**Safe now:** ✅ Yes

### P1-5 — Write real PaywallView (wire to SubscriptionManager)
**File:** New `ios/Clavis/Views/Paywall/PaywallView.swift`  
**Blocked by:** P0-5 (StoreKit scaffold)  
**Problem:** Both upgrade sheets are stubs that dismiss without action.  
**Fix:** Build a real paywall sheet that:
- Shows the Pro feature list (from `CLAVIX_LAUNCH_SCOPE_v1.md`)
- Has "Start 14-day free trial" button → `SubscriptionManager.shared.purchase()`
- Has "Restore purchases" link
- Handles loading, error, success states
- Uses actual product price from StoreKit once loaded
**Acceptance criteria:** Tapping "View Pro" in any context presents a real purchase flow (sandbox in TF, real in production).

### P1-6 — Fix data_status never populated
**File:** `backend/app/pipeline/scheduler.py`  
**Problem:** All 176 today's snapshots have `data_status = NULL`. The column exists but is not being written.  
**Impact:** The iOS app may use `data_status` to determine display state (e.g., showing "Limited data" banners). Check whether the iOS app uses this field.  
**Fix:** Find where snapshots are written and ensure `data_status` is set to `"ready"`, `"thin"`, or `"failed"` appropriately.  
**Safe now:** ✅ Yes

### P1-7 — Fix browse chips (fake search seeds)
**File:** `ios/Clavis/Views/Search/SearchView.swift`  
**Problem:** "Mega caps" → `query = "AAPL"`, "Dividend aristocrats" → `query = "JNJ"`, "High-grade only" → `query = "MSFT"`. These are hardcoded shortcuts that don't actually filter by the advertised property.  
**Fix:** Either (a) remove until real backend filter params exist, or (b) replace with real queries when backend supports filter params. For now, option (a) is safer — replace chips with a single "Browse all" that loads popular tickers.  
**Safe now:** ✅ Yes

### P1-8 — Remove specific brokerage names from Settings "Coming soon" copy
**File:** `ios/Clavis/Views/Settings/SettingsView.swift` — FeatureFlags.brokerageEnabled == false branch  
**Current copy:** "Read-only position sync from Robinhood, Schwab, Fidelity, and others. No trading access."  
**Problem:** Naming specific brokerages in "Coming soon" copy creates user expectations and potential marketing claim issues if those integrations are not built.  
**Fix:** Replace with: "Read-only portfolio sync from your brokerage. Coming in a future update."  
**Safe now:** ✅ Yes

### P1-9 — Label "email digest of alerts" as Coming Later
**Files:** `ios/Clavis/Views/Settings/SettingsView.swift` if visible; anywhere email digest of alerts is mentioned  
**Problem:** Per `CLAVIX_LAUNCH_SCOPE_v1.md`, email digest requires SMTP (Resend). Resend API key is missing from VPS. Cannot ship this feature without it.  
**Fix:** If this feature is visible anywhere, label it "Coming later." Also update paywall copy to not list it as currently available Pro feature.  
**Safe now:** ✅ Yes

### P1-10 — Update pricing.md to remove brokerage
**File:** `docs/PRODUCT/pricing.md`  
**Problem:** Still lists "Brokerage sync" as a Pro feature and in the cost structure as "Usage-based."  
**Fix:** Remove brokerage row. Add "Coming later" note.  
**Safe now:** ✅ Yes

### P1-11 — Fix web footer
**File:** `web/index.html`  
**Current:** `© 2026 Andover Digital`  
**Fix:** `© 2026 Andover Digital LLC`  
**Safe now:** ✅ Yes (1-line change)

---

## P2 — Polish before public launch

### P2-1 — Add "Operated by Andover Digital LLC" to in-app Settings
**File:** `ios/Clavis/Views/Settings/SettingsView.swift` — Support & Legal section  
**Fix:** Add a text row: "Clavix is operated by Andover Digital LLC." before the legal links.

### P2-2 — Build real trending section
**File:** `ios/Clavis/Views/Search/SearchView.swift`  
**Current:** Always shows "Trending data has not populated yet."  
**Fix:** Either add a backend endpoint that returns most-viewed tickers, or replace the section with "Most discussed" based on alert volume.

### P2-3 — Score history for Pro (90-day, all 5 dims)
**Files:** `ios/Clavis/Views/Tickers/ScoreHistoryChart.swift`, backend history endpoints  
**Current:** History shown for composite only (30 days for Free). Pro needs 90-day all-dimension history.  
**Fix:** Backend already stores per-dimension data in `ticker_risk_snapshots`. API endpoint needs to expose it; chart needs to render it.

### P2-4 — Advanced alerts gating
**Files:** `ios/Clavis/Views/Alerts/AlertsView.swift`, `ios/Clavis/ViewModels/AlertsViewModel.swift`  
**Fix:** Gate watchlist alerts and macro-shock alerts behind Pro. Show upgrade prompt for Free users.

### P2-5 — Manual ticker refresh (Pro feature)
**Fix:** 5 refreshes/ticker/day for Pro users. Needs backend rate limiting + iOS UI button.

---

## P3 — Post-launch

- CSV export (portfolio + alerts)
- CSV import (bulk add positions)
- Email digest of alerts (once Resend is wired)
- Trending section with real data
- Organization Apple Developer account migration
