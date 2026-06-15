# Report 5: Monetization and Business Audit (2026-06-14)

Inputs you gave: monetization model = free trial only (no perpetual free); current costs = MiniMax $20/mo, Supabase $25/mo, VPS $14/mo, Dropbox Fax $9.99/mo, Zoho Mail $4/mo, Apple Developer $99/yr, domain $11/yr; not paying for Finnhub or Polygon (both free tiers); Apple App Store Connect status unknown.

---

## 1. Cost base

| Item | Monthly | Notes |
|---|---|---|
| MiniMax (LLM) | $20.00 | Scales slowly with users; most usage is shared per-ticker enrichment, not per-user |
| Supabase | $25.00 | Includes backups and PITR; the data backbone |
| DigitalOcean VPS | $14.00 | Single small droplet (1.9 GB RAM) |
| Apple Developer | $8.25 | $99/yr amortized |
| Domain | $0.92 | $11/yr amortized |
| **App infrastructure subtotal** | **$68.17** | The number that matters for unit economics |
| Dropbox Fax | $9.99 | Business overhead, not app infra; see note |
| Zoho Mail | $4.00 | Business overhead (support and sender address) |
| **All-in total** | **$82.16** | |

Notes:
- **Finnhub and Polygon are $0 today** because you are on free tiers. That is exactly why the recompute hit the 429 wall. This is the one cost line that will have to go up (see section 4). It is the single biggest financial decision between here and a reliable public launch.
- **Dropbox Fax** does not appear app-related. If it is not needed for the business (for example to receive a signed document), it is $120/yr you can cut. Worth a look.

---

## 2. Unit economics and break-even

Price: $19.99/month (the built product id `clavix_pro_monthly`).

Apple's commission:
- Standard is 30%, dropping to 15% after a subscriber's 12th consecutive paid month.
- **The Apple Small Business Program is 15% from day one** if your total proceeds are under $1M/year. You almost certainly qualify, and you should enroll. It roughly doubles your net per subscriber in year one.

Net revenue per subscriber per month:
- At 15% (Small Business Program): $19.99 x 0.85 = **$16.99**.
- At 30% (if not enrolled): $19.99 x 0.70 = **$13.99**.

Break-even on the $68/mo app infrastructure:
- At 15%: 68 / 16.99 = about **4 paying subscribers**.
- At 30%: 68 / 13.99 = about **5 subscribers**.
- All-in ($82, including fax and mail): about **5 to 6 subscribers**.

So the business breaks even at roughly five paying users. That is a very forgiving floor. The risk to the business is not cost, it is whether the product earns trust well enough to convert and retain (see reports 1 and 2).

Marginal cost per additional user is low: data-API calls are per ticker (shared universe), not per user, and the dominant LLM cost (news enrichment) is also shared per ticker. The only truly per-user LLM cost is the personalized digest prose. This is a healthy, mostly-fixed-cost SaaS structure: each new subscriber is almost pure margin until you outgrow the free data tiers and the small droplet.

---

## 3. Is it monetizable, and is trial-only the right model?

**Monetizable: yes, clearly, at this cost base.** A daily-habit product for an affluent ICP at $19.99/mo with a five-subscriber break-even is a sound shape. The open question is conversion and retention, which depend on the data-trust fixes, not on the price.

**Your choice, free trial only (no perpetual free): defensible, with two things to get right.**

Pros for this product and ICP:
- Higher intent. People who finish a 14-day trial of a risk tool and pay are committed daily users, which is what a habit product wants.
- Simpler gating. No per-feature free limits to maintain. During the trial everything is unlocked; after it, the app is behind a paywall. Less code than freemium.
- It forces the value question while the morning-briefing habit is fresh.

Cons to manage:
- **No free top-of-funnel.** A perpetual free tier is a growth and word-of-mouth engine; trial-only removes it. For an unknown brand this can suppress installs and makes paid acquisition or content or referrals more important. Acceptable for a premium, narrow-ICP product, but go in with eyes open.
- **The model is not what the build implements.** The build is freemium (3-holding and 5-watchlist free caps) with an unenforced trial. Trial-only needs: during the trial, everything unlocked (so the trial-to-Pro enforcement bug must be fixed); after the trial with no subscription, a hard paywall that locks the app (a state that does not exist yet); and removal or repurposing of the free-tier caps.

**Implementation shape for trial-only (recommended):**
- Keep the server-granted trial (no credit card to start). New user gets 14 days of full access. The backend already sets `trial_started_at` and `trial_ends_at` and computes an effective tier; make the gates honor it (treat trial and pro and admin as unlocked).
- Add an "expired and not subscribed" state. When `now > trial_ends_at` and there is no active StoreKit entitlement, present a full-screen paywall and lock the core features. iOS `SubscriptionManager.isPro` already flips to true during trial; wire the actual feature gates and a lock screen to it instead of to the raw `subscription_tier == "free"`.
- Because the free period is server-side and card-free, the StoreKit subscription itself does not need an Apple introductory free-trial offer. That keeps the funnel friction-free (no card during trial) and avoids the copy problem below.

**Copy bug to fix now:** the paywall says "14-day free trial, no credit card required." That is true only for a server-granted trial. If you instead used an Apple auto-renewing introductory offer, Apple **always** requires a payment method on file to start it, so "no credit card required" would be false and a likely review rejection. Decide which trial mechanism you are using and make the copy match. The recommended server-granted approach keeps the current copy honest.

---

## 4. The one real cost decision: paid data tiers

Today freshness survives only by throttling Finnhub to 60/min on the free tier, which makes the recompute take about 140 minutes and stay fragile. Polygon free is even more limited (single-digit calls per minute), and price-history latency has already been a UX issue. Before a paid public launch:
- Budget for paid Finnhub and paid Polygon. Confirm current pricing directly (it changes), but plan for roughly $30 to $80/mo combined to start. That moves break-even to about 7 to 9 subscribers, still trivial.
- This is the difference between "freshness depends on a throttle that barely fits" and "freshness is robust." For a product whose entire pitch is trustworthy data, that is worth the spend the moment you have paying users. For the beta, the free tiers plus the throttle plus the job-failure alert are acceptable.

---

## 5. Pricing sanity check

$19.99/mo for this ICP (45 to 65, $500K to $5M, currently paying for Seeking Alpha Premium and similar) is reasonable and arguably under-priced relative to the value (replacing 30 to 60 minutes of daily work). Considerations:
- **Add an annual plan.** Annual at a discount (for example $179/yr, about 25% off) improves cash flow and retention and is the standard lever for habit subscriptions. Worth adding before public launch, not before the beta.
- **Do not go cheap.** Dropping to $9.99 to chase volume fights the premium, trustworthy positioning and barely moves a five-subscriber break-even. The ICP is not price-sensitive at this level; they are trust-sensitive.
- Validate willingness to pay during the beta: does the tester convert at trial end, and what do they say about the price relative to what they replace.

---

## 6. Business punch list
- Enroll in the Apple Small Business Program (15% commission) before the IAP product goes live.
- Decide the trial mechanism (recommended: server-granted, card-free) and make the paywall copy match.
- Implement the trial-only gating (unlock during trial, hard paywall on expiry, remove free caps).
- Plan paid Finnhub and Polygon before public launch; keep free tiers plus throttle for the beta.
- Add an annual plan before public launch.
- Review whether Dropbox Fax is needed; cut it if not.
