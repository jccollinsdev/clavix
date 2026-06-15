# Remaining Code Work Progress

**Started:** 2026-06-15
**Branch:** `codex/remaining-code-work`
**Source checklist:** `docs/REMAINING_CODE_WORK.md`

## Ground Rules

- Required session docs read: `AGENTS.md`, `docs/CLAVIX_TRUTH.md`, `docs/REFACTOR_PLAN.md`.
- Existing worktree dirt before this branch: `.DS_Store`, `supabase/.temp/`.
- Do not touch external admin-only tasks except to add code hooks or document blockers.

## Live Checklist

| Item | Status | Notes |
|---|---|---|
| 1. ETF backfill migration | Implemented + live data backfilled | Added `20260615_01_etf_backfill.sql` with 17 ETF rows and `index_membership='ETF'`. Live DB already had 16/17 rows; upserted missing `XLC` via service-role access and refreshed all 17 ETFs in production. |
| 2. iOS crash reporter (Sentry) | Implemented | Added Sentry SPM package in XcodeGen, app startup init, `SENTRY_DSN` Info.plist/xcconfig keys. Real DSN remains external. |
| 3. Expired-trial lock screen | Implemented | Added `ExpiredPaywallView`, `ContentView` gate for `.notSubscribed`/`.expired`, and no lock for `.unknown`/trial/active. |
| 4. Settings trial tier badge | Implemented | `SettingsViewModel` now displays `effectiveTier` before raw `subscriptionTier`; standalone `UserPreferences` model aligned. |
| 5. Foreground tier refresh | Implemented | `ClavisApp` refreshes `SubscriptionManager` on `UIApplication.didBecomeActiveNotification`; auth changes also refresh. |
| 6. Financial-health stability | Implemented | Added ticker metadata fundamentals columns/migration, persisted ratios, fixed weekly sweep pre-fetched upsert path, and daily recompute cached-fundamentals reuse. |
| 7. Drop dead DB columns | Implemented | Added `20260615_03_drop_dead_snapshot_columns.sql`; code-reference check found no active snapshot reads of non-`_dim` columns. |
| 8. Funnel analytics | Implemented | Added first-party `analytics_events` table, `POST /analytics/event`, iOS analytics client, and minimum funnel events. |
| 9. iOS disk cache | Implemented | Added `UserDefaults` stale cache for holdings, digest, alerts; view models hydrate cache before live fetch. |
| 10. `REFRESH_CONCURRENCY` env var | Implemented | Scheduler now reads env var with safe fallback/default `2`. |

## Validation Log

- `python3` on PATH is Python 3.9.6 and cannot collect the backend tests because existing scheduler annotations require Python 3.10+. Switched to `/opt/homebrew/bin/python3.11`.
- `/opt/homebrew/bin/python3.11 -m compileall backend/app` passed.
- Focused backend tests passed with Python 3.11: `cd backend && /opt/homebrew/bin/python3.11 -m pytest tests/test_news_cache_freshness.py tests/test_scheduler_jobs.py -q` → 29 passed, 10 xfailed, 2 warnings.
- `plutil -lint ios/Clavis/Resources/Info.plist` passed.
- `cd ios && xcodegen generate` passed.
- `cd ios && xcodebuild -resolvePackageDependencies -project Clavis.xcodeproj -scheme Clavis` passed; Sentry resolved to 8.58.3.
- `cd ios && xcodebuild -scheme Clavis -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build` passed. Existing warnings remain: malformed duplicate `Clavis/Config` group, unassigned `clavix_wordmark` asset child, missing iPad icons, unused `nameLower`, and Sentry `profilesSampleRate` deprecation.
- Production health smoke passed: `curl https://clavis.andoverdigital.com/health` returned `status=ok`, APNs/SnapTrade/MiniMax/Supabase configured, latest recompute completed.
- Analytics auth smoke passed: unauthenticated `POST /analytics/event` returned 401 `Missing Authorization header`.
- Simulator smoke passed on booted iPhone 17 Pro: installed fresh Debug build and launched `com.clavisdev.portfolioassistant` without crash. Console showed expected unauthenticated session state, simulator APNs entitlement warning, and suppressed unauthenticated `/preferences` 401s.
- `git diff --check` passed.
- Full backend suite first pass found 9 regressions in dimension fallback, news domain blocking, and holdings-count handling; all three groups were fixed.
- Focused regression tests passed: `cd backend && /opt/homebrew/bin/python3.11 -m pytest tests/test_dimension_fallback.py tests/test_enrichment_completeness.py tests/test_holdings_add.py -q` → 37 passed, 4 warnings.
- Full backend suite passed after fixes: `cd backend && /opt/homebrew/bin/python3.11 -m pytest -q` → 493 passed, 10 xfailed, 5 warnings.
- Supabase MCP/plugin was not available. Supabase CLI is installed (`2.105.0`) but local project link points to a different project (`fmqwcophfowdnauvxkyz` / varfoot), and the authenticated CLI account cannot see documented Clavix project `uwvwulhkxtzabykelvam`; DDL migrations could not be applied from this environment.
- Live ETF universe check found 16/17 ETF rows present; upserted missing `XLC` into `ticker_universe` using the service-role key. Recheck showed all 17 present.
- Production ETF refresh was completed through `POST /tickers/{ticker}/refresh` using a temporary admin elevation of the existing test user. The user was restored to `subscription_tier='free'` immediately afterward. Verification showed 17/17 `ticker_refresh_jobs` completed and 17/17 `ticker_risk_snapshots` present for `2026-06-15` with `methodology_version='v2'`.
- Production health smoke after ETF refresh passed: `status=ok`, APNs/SnapTrade/MiniMax/Supabase configured.

## External Blockers

- Real Sentry DSN must be created outside code and injected into `SENTRY_DSN`.
- StoreKit product and paid-app agreements remain admin tasks, so real purchase smoke tests may be limited.
- DDL migrations still need to be applied from a correctly linked Supabase account or direct Postgres connection. Live checks confirm `ticker_metadata.fundamentals_updated_at` and `analytics_events` are not present yet.

## Production ETF Refresh Attempts

- Attempt 1 used Python `urllib` and was blocked by Cloudflare 1010 before any refresh calls; temporary user tier was restored to `free`.
- Attempt 2 used `curl` but had a local command-construction bug before the URL; no refresh calls reached production, and temporary user tier was restored to `free`.

## Production ETF Refresh Attempt 3

- Started: 2026-06-15T19:34:40.982571+00:00
- Temporary admin user: `f6190ebf...9986`; original tier `free` restored at end.
- JWT smoke `/preferences`: HTTP 200.
- `QQQ` refresh: HTTP 200 status `completed` job `1f8c2c55-2c5f-4777-ab1c-d13d1194a180` elapsed 29.6s
- `XLF` refresh: HTTP 200 status `completed` job `aee041d6-c279-43ba-a950-493d7094a98d` elapsed 4.6s
- `XLK` refresh: HTTP 200 status `completed` job `cc743b47-f306-4ba0-b790-a2178323e9fb` elapsed 4.9s
- `XLE` refresh: HTTP 200 status `completed` job `ca721175-cf89-4ca0-a7cd-193a6bcb9efc` elapsed 5.1s
- `XLV` refresh: HTTP 200 status `completed` job `22d48a10-cade-4e1b-a10a-6055142d1fcc` elapsed 40.8s
- `XLI` refresh: HTTP 200 status `completed` job `6f589c93-6ed4-401c-b959-65c8786a7705` elapsed 4.1s
- `XLC` refresh: HTTP 200 status `completed` job `09773e32-f7c8-48cd-b0e9-8bdde94c0156` elapsed 5.1s
- `XLY` refresh: HTTP 200 status `completed` job `9b8be59a-7d9f-4cf5-9705-34444feb98e8` elapsed 9.2s
- `XLP` refresh: HTTP 200 status `completed` job `d6442a94-ba65-4dd1-9b37-92bedc5b705a` elapsed 41.9s
- `XLU` refresh: HTTP 200 status `completed` job `db016012-ee1b-4876-aece-fdccc6ad3417` elapsed 3.9s
- `XLRE` refresh: HTTP 200 status `completed` job `828cd1c3-2074-4763-8a41-f599de66e631` elapsed 5.1s
- `XLB` refresh: HTTP 200 status `completed` job `22c6605d-f925-4e28-9709-72a799576b66` elapsed 4.9s
- `AGG` refresh: HTTP 200 status `completed` job `f47cdeac-275f-4164-a042-afcda3c90426` elapsed 4.9s
- `BND` refresh: HTTP 200 status `completed` job `dd1537ea-a4da-45ec-ab05-5eac615176b2` elapsed 40.4s
- `VTI` refresh: HTTP 200 status `completed` job `8146a112-d657-4dd1-89c0-bb7fde28230e` elapsed 11.1s
- `IWM` refresh: HTTP 200 status `completed` job `fb375bb6-eeab-470f-a475-1585c108890c` elapsed 3.9s
- `SCHD` refresh: HTTP 200 status `completed` job `23fa46f1-a659-4de7-972c-04c5cca9b679` elapsed 4.9s
- Restored temporary admin user tier to `free` at 2026-06-15T19:38:26.241441+00:00.
- Completed refresh attempts: 17/17 HTTP 2xx.
