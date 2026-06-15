# Report 4: Frontend Responsiveness and Scale (2026-06-14)

You said several screens take a long time to load and asked how to fix it and whether the app will support many users. Short version: the backend edge is not your problem (50 to 75 ms), so the slowness is on the client and in the heavier authed endpoints. The fixes are concrete and mostly small.

---

## 1. Where the time actually goes

- **Edge latency is excellent.** `/health` and `/ping` answer in about 50 to 75 ms, and authed routes 401 in about 60 ms. So DNS, the Cloudflare Tunnel, and routing are fast. A slow screen is not "the server is far away."
- **The client has no persistent cache.** `APIService` keeps an in-memory cache only and explicitly sets `cachePolicy = .reloadIgnoringLocalCacheData`, with a comment that the OS URL cache is disabled on purpose. The in-memory cache is wiped on every app launch. So every cold start refetches holdings, grades, prices, and digest from scratch before anything paints. This is the most likely cause of "the app is slow when I open it."
- **Holdings load makes wasted brokerage calls.** `HoldingsViewModel.loadHoldings` fetches holdings (good), then spawns parallel tasks for watchlists and preferences (good), but also calls `fetchBrokerageStatus`, and on success `syncBrokerage` then refetches holdings and status again. Brokerage is deferred and off (`FeatureFlags.brokerageEnabled = false`), but that flag is only checked in the UI, not in the ViewModel. So every holdings load spends round trips on a feature that is disabled, and a sync that can add real latency.
- **Heavy detail screens aggregate several resources.** Ticker detail pulls risk, price history, news, and methodology. A recent commit (`9759404f`, "stop blocking price history on live Polygon backfill") already removed one blocking call, which confirms this screen was doing synchronous, upstream-bound work. Confirm the remaining sub-resources fetch concurrently rather than in sequence.
- **Very large view files.** `HoldingsListView` is 1,786 lines and `TickerDetailView` is 1,480. Large SwiftUI bodies recompute more than necessary and can cause scroll jank. This is polish, not the main cause.

---

## 2. The fixes, in order of perceived-speed payoff

1. **Add a persistent disk cache with stale-while-revalidate.** Persist the last-known holdings list, grades, and most recent digest to disk (a simple Codable cache or a small store). On cold launch, render the cached view instantly, then refresh in the background and update in place. This is the single biggest win: the app feels instant even when the network call is in flight. It also makes the app usable on a flaky connection, which matters for the commuting-investor moment.
2. **Gate brokerage calls behind the feature flag in the ViewModel.** Wrap the `fetchBrokerageStatus` and `syncBrokerage` block in `HoldingsViewModel` in `if FeatureFlags.brokerageEnabled`. This removes two-plus wasted round trips and a sync from every holdings load for free.
3. **Parallelize ticker-detail sub-resources.** Use `async let` or a task group so risk, price history, news, and methodology fetch concurrently, then assemble. The screen is only as slow as the slowest call instead of their sum.
4. **Replace spinners with skeletons.** Show the card and row layout as a skeleton while data loads. Perceived latency drops even when real latency does not. Pair with the disk cache so the skeleton is rarely seen after first run.
5. **Trim the giant views later.** Break `HoldingsListView` and `TickerDetailView` into smaller subviews so SwiftUI recomputes less. Polish-tier, do it after the beta.

---

## 3. Backend-side latency on authed routes

The 401 timing does not tell you how slow an authed call is once it does real work. Two things to verify with a real token (or in the simulator with the debug bypass):
- Whether any user-facing GET triggers on-demand upstream enrichment (a live Finnhub or Polygon call, or an LLM call) in the request path. Anything that does will be slow and quota-fragile. User-facing reads should serve precomputed data from Supabase and never block on an upstream provider. The price-history fix suggests this pattern existed; sweep for others.
- Whether the add-holding flow's analysis polling (`pollAnalysisRun`) has a sensible timeout and progress UI so a slow first analysis does not look like a hang.

---

## 4. Will it support many users?

For reads, yes, with room to spare. Grades, digests, and news are precomputed into Supabase and served fast behind Cloudflare, so read traffic scales with Supabase and the CDN, not with your single droplet. The places that do not scale for free:
- **The daily batch pipeline** on free data tiers. This scales with universe size and refresh cadence, not user count, but it is fragile today (140-minute throttled recompute). Paid Finnhub and Polygon tiers fix the fragility. See reports 3 and 5.
- **The single droplet** for any work that does happen per request, and as a single point of failure. Resize and add backups before public scale. See report 3.
- **Per-user digest generation** uses the LLM, so cost (not capacity) grows slowly with users. The news enrichment that dominates LLM usage is shared per ticker, not per user, so the marginal cost of one more user is small. This is a healthy cost structure. See report 5.

Net: the architecture is read-optimized and precomputed, which is the right shape for many users. Do the client cache work for perceived speed now, and the data-tier and droplet work before you actually have many users.

---

## 5. Frontend punch list
- Persistent disk cache with stale-while-revalidate (biggest win).
- Feature-flag the brokerage calls in `HoldingsViewModel`.
- Parallelize ticker-detail sub-resources.
- Skeleton loaders.
- Verify no user-facing GET blocks on an upstream provider.
- Add a crash reporter and lightweight analytics so you can see real load times in the field (see report 6).
