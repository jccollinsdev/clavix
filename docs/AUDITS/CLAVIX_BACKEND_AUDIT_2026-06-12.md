# Clavix Backend & Data Audit — 2026-06-12

**Auditor:** Claude Opus 4.8 (in-session, live evidence)
**Scope:** Production VPS, FastAPI backend, Supabase data freshness, scheduled jobs, the daily backfill/recompute pipeline, trial logic, push delivery, security.
**Evidence basis:** Live `/health` + `/ping`, live `docker ps`/`docker logs`/`docker inspect` on the VPS, live production Supabase SQL, backend source, Supabase security advisors.
**Context:** Owner returning after ~1 week away. Goal is launch ASAP.

---

## 0. Executive summary

The backend is **alive and healthy at the service level**, and the **per-user experience (digests, alerts, owned holdings) is fresh and working**. But there is **one serious, ongoing data problem**: the daily universe recompute job has been failing every day for at least the last 4+ days, leaving **69% of the tracked universe (352 of 507 tickers) 8+ days stale**. The root cause is an upstream **Finnhub free-tier 429 rate limit**.

Two other backend issues block the paid launch story rather than break the app: the **14-day Pro trial is computed but never enforced** (no user gets Pro during trial), and **push notifications have never been delivered** (zero device tokens registered).

Security is clean (one low informational warning).

| Area | Status |
|---|---|
| VPS / container / health | ✅ Healthy, stable (up 8 days, on latest commit) |
| Per-user digests | ✅ 4/4 active users generated today |
| In-app alerts | ✅ 21 today, generating normally |
| News/sentiment enrichment pipeline | ✅ Running (2h interval) |
| **Universe recompute (full breadth)** | ❌ **Failing daily; 69% of universe 8+ days stale** |
| 14-day Pro trial | ❌ Computed but not enforced anywhere |
| Push delivery (APNs) | ❌ 0 device tokens, 0 alerts ever delivered |
| Security (Supabase advisors) | ✅ Clean (1 low WARN) |

---

## 1. Service health (✅)

- `GET /health` → `{"status":"ok","apns":"configured","snaptrade":"configured","minimax":"configured","supabase":"configured"}` (fast).
- `GET /ping` → `{"ok":true}` (fast, no DB).
- Container `clavis-backend-1`: **Up 8 days**, started `2026-06-03T23:38:30Z`. Stable, no crash-looping.
- VPS git HEAD = `228422b` (matches local `main`). The backend is fully deployed with the latest code, including the `/tickers/screen` radar endpoint (verified live: returns 401 without auth, i.e. the route exists).
- Pipeline activity confirmed in logs: `[BULK_ENRICH] Enrichment complete: 197 articles updated` at 18:00 UTC; `_run_bulk_sentiment_enrichment` scheduled on a 2h interval and executing successfully. Supabase REST calls returning 200/2xx throughout.

**Conclusion:** nothing is down. The problems below are data-pipeline and feature-completeness issues, not outages.

---

## 2. Per-user data freshness (✅ fresh)

The data that a TestFlight user actually sees for *their own* portfolio is current.

- **Digests:** 230 total, latest `2026-06-12 11:11 UTC`, **4 generated today**. All 4 active users' digest jobs (`scheduler_jobs`) show `last_run_status = completed` for today, next run `2026-06-13 11:00`. The 50%-of-users digest crash from the 06-02 audit stays fixed.
- **Alerts:** 17,077 total, latest `2026-06-12 11:11 UTC`, **21 today**.
- Owned-holding refresh runs on demand and via per-user jobs, so AAPL/SMCI/etc. for the test user are fresh.

So the core "open the app, see my portfolio" path is in good shape.

---

## 3. 🔴 P0 — The universe recompute is failing daily (data going stale)

This is the most important backend finding.

### 3.1 Evidence

`job_runs` for `daily_composite_recompute_universe` (out of ~503 universe tickers):

| Date | Status | Processed | Failed | Wall time |
|---|---|---|---|---|
| 2026-06-09 | failed | 98 | 405 | ~2h17m |
| 2026-06-10 | failed | 97 | 406 | ~2h20m |
| 2026-06-11 | failed | 100 | 403 | ~2h19m |
| 2026-06-12 | failed | 94 | 409 | ~2h20m |

Snapshot freshness, latest snapshot per ticker (`ticker_risk_snapshots`):

| Freshness | Tickers |
|---|---|
| 0–1 days (fresh) | 107 |
| 2–3 days | 9 |
| 4–7 days | 39 |
| **8+ days stale** | **352** |

The **last full-universe recompute was 2026-06-02** (504 tickers). Since then the job completes only ~90–100 tickers/day before everything else fails, and the same ~352 names have not been re-scored in 8–10 days.

### 3.2 Root cause (confirmed from logs + source)

Backend logs during the 06-12 10:00–12:20 UTC window are full of:

```
429 rate limit, sleeping 5.0s before retry 1
429 rate limit, sleeping 10.0s before retry 2
429 rate limit, sleeping 20.0s before retry 3
429 rate limit, sleeping 40.0s before retry 4
```

That message comes from `backend/app/services/ticker_metadata.py:117` (`_retry_request`), which wraps **Finnhub** calls (`/stock/profile2`, `/stock/metric`, `/quote` — ~3 calls per ticker). The recompute (`backend/app/jobs/composite_recompute.py`) iterates the full universe; after roughly the first ~100 tickers the **Finnhub free-tier per-minute quota is exhausted**, so every subsequent ticker hits 429, burns 5+10+20+40s of backoff across 4 attempts, then is marked `failed`. The backoff is also why the job takes ~2h20m instead of minutes.

In short: **not a code crash, an upstream API quota ceiling.**

### 3.3 Secondary observation

`job_runs.error_json` is **NULL** for the failed recompute runs, even though commit `228422b` was labeled "recompute hardening." Failures are counted but not captured, so there is no machine-readable error trail and no alert fired. The "hardening" did not actually make the job resilient to the 429 wall.

### 3.4 Remediation options (pick one or combine)

1. **Throttle to stay under the quota.** Lower batch size / raise inter-batch delay in `composite_recompute.py` (currently `DEFAULT_BATCH_SIZE = 15`, `DEFAULT_INTER_BATCH_DELAY_SECONDS = 5`) and/or widen the metadata cache TTL so most tickers are served from cache and only a slice actually call Finnhub. 503 tickers × 3 calls at 60/min ≈ 25 min if perfectly spaced; today it bursts and dies.
2. **Spread the universe across the day or across several runs** (e.g. 100 tickers/run, 5 runs at staggered times) so each run stays under the minute/day limit.
3. **Upgrade Finnhub to a paid tier** (higher rate limit). Simplest if budget allows; removes the ceiling for the whole pipeline.
4. **Reduce calls per ticker** (only fetch the Finnhub fields not already fresh in `ticker_metadata`; the cache reuse logic at `_reuse_cached_metadata` exists but evidently is not sparing enough calls).

Also add: capture the exception into `job_runs.error_json`, and resume/retry only the *failed* tickers on a later pass instead of re-walking from the top.

**Note:** because owned holdings and digests refresh on their own paths, this staleness is mostly visible in **Search / Risk Radar screener** results for arbitrary S&P names, not in a user's own portfolio. It is still a real product-quality issue for a "data you can trust" app and should be fixed before public launch.

---

## 4. 🟠 P1 — The 14-day Pro trial is not enforced

The trial is half-built: dates are set, an effective-tier is computed, but nothing consumes it.

- `backend/app/routes/preferences.py:39 _effective_tier()` correctly returns `"trial"` when `now < trial_ends_at` for a free user, and `_get_or_create_prefs()` sets `trial_started_at` / `trial_ends_at = +14d` on first login. The GET `/preferences` response includes `effective_tier`.
- **But every gate reads the raw `subscription_tier`, not `effective_tier`, and only checks `== "free"`:**
  - `holdings.py:_get_subscription_tier` (3-holding limit)
  - `watchlists.py:_get_subscription_tier` (5-watchlist limit)
  - `tickers.py:_user_subscription_tier` (refresh limit)
  - `services/access_control.py`
- iOS never reads `effective_tier` either. All ViewModels gate on raw `subscriptionTier` (`AuthViewModel`, `DigestViewModel`, `SettingsViewModel`, `HoldingsViewModel`), which is always `"free"`. `APIService` decodes `subscriptionTier` and `trialEndsAt` but drops `effective_tier`.
- Even if something did check it, `_effective_tier` returns the string `"trial"`, which no gate recognizes as unlocked (`tier in ("pro","admin")` only).

**Live confirmation:** all 5 `user_preferences` rows have `subscription_tier` = `free` (one system user = `admin`). Two June testers have `trial_ends_at` of `2026-06-15` (still inside the window) yet are gated as free right now. No user has ever received Pro features via the trial.

**Fix:** decide the model (recommend: treat trial as Pro at access time), then make the gates and iOS honor it:
- Backend: have the gate helpers return / compare against `_effective_tier(prefs)`, and treat `trial` (and `pro`/`admin`) as unlocked.
- iOS: decode `effective_tier` and gate on `effective_tier != "free"` (or compute from `trialEndsAt`).
- Add the downgrade path: after `trial_ends_at`, `_effective_tier` already returns `free`, so expiry is automatic once gates honor it.

---

## 5. 🟠 P1 — Push notifications have never been delivered

- APNs **key** is configured server-side (`/health → apns:configured`).
- **0 of 5 users have an `apns_token`**, and **0 of 17,077 alerts** have a non-null `delivered_at`.
- Root cause is not the server: no real device has registered a token. Simulators cannot get real APNs tokens. This must be verified on a **real TestFlight device**: confirm `registerForRemoteNotifications` fires, the permission prompt appears, the token POSTs to `/preferences` device-token endpoint, and a test push arrives.

This is a verification/admin task, not a code fix, but until it is proven on device, push is effectively non-functional.

---

## 6. Other backend findings (P2 / housekeeping)

- **`daily_portfolio_rollup_per_user` fails for 1 user** intermittently (06-12: 4 ok / 1 failed; 06-10 same; 06-09/06-11 clean). Most likely the test user's **AMD** position, which has a composite score but all five dimensions NULL (carried-over P2 from the 06-03 audit). Backfilling AMD's dimensions should clear both the rollup failure and the empty-radar render.
- **`error_json` never captured** for failed `job_runs` (see §3.3). Add capture + a failure alert.
- **`data_generation_runs`** holds orphaned `status = running` rows from `2026-05-16` that never completed. This is a legacy/abandoned tracking table (the live pipeline uses `job_runs`); the orphans are cosmetic but should be marked failed or cleaned.
- **`tldr_backfill`** has a history of failing (non-critical enrichment backfill).
- **Grade distribution is healthy** (latest-per-ticker): AA 8, A 297, BBB 163, BB 30, B 7, CCC 2 (507 total). No BBB pileup. (Caveat: computed from latest-available snapshots, so it partly reflects 06-02 data for the stale 352.)

---

## 7. Security (✅)

- Supabase security advisors: **no ERROR/CRITICAL lints.** One **WARN**: `citext` extension installed in the `public` schema ([remediation](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public)).
- The previously-flagged "RLS enabled, no policy" internal tables (`data_generation_runs`, `data_generation_run_items`, `gnews_wrapper_resolution`, `waitlist_signups`) now carry documented "service_role only" comments and are no longer flagged.
- Standing user task (CLAUDE.md): toggle **leaked-password protection** in Supabase → Auth → Providers → Email. Still pending.

---

## 8. Backend launch checklist (ordered)

1. **[P0]** Fix the universe recompute 429 wall (throttle / spread / upgrade Finnhub / cache harder) and restore daily full-universe freshness. Capture `error_json` and retry only failed tickers.
2. **[P1]** Make the 14-day trial actually grant Pro (wire `effective_tier` into backend gates + iOS).
3. **[P1]** Verify push end to end on a real device (token registration + test push).
4. **[P2]** Backfill AMD dimensions; fix the 1-user portfolio-rollup failure.
5. **[P2]** Security housekeeping: move `citext` out of `public`; toggle leaked-password protection.
6. **[P2]** Clean orphaned `data_generation_runs` rows.
