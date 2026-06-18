# Clavix — TestFlight Launch Plan
**Goal: Dad on TestFlight with payments working, App Store submission ready in 7 days.**
Last updated: 2026-06-18

---

## Tomorrow — TestFlight Launch Day

### App Store Connect (you)

- [ ] Confirm `clavix_pro_monthly` subscription product exists and shows "Ready to Submit" in App Store Connect → In-App Purchases
- [ ] Confirm 14-day Introductory Offer has been submitted for review on `clavix_pro_monthly` (being done today — verify it shows "Waiting for Review" tomorrow morning)
- [ ] Create a Sandbox Tester account for dad: App Store Connect → Users and Access → Sandbox → Testers → "+" → use a throwaway email, not dad's real one
- [ ] Confirm the new build (1.0 or 1.1 depending on what ASC assigned) has finished processing — you'll get an email. If not, check App Store Connect → TestFlight
- [ ] Add the processed build to the Internal Testing group in TestFlight
- [ ] Send dad a TestFlight invite to his real email

### When Dad Installs (you + me)

1. Dad accepts TestFlight invite, installs the app, signs up with his real Apple ID (or Apple/Google sign-in)
2. You find his user ID: Supabase Dashboard → Table Editor → `user_preferences` → find his row
3. Run this SQL to expire his server trial so the paywall shows immediately:
   ```sql
   UPDATE user_preferences
   SET trial_ends_at = NOW() - INTERVAL '1 minute'
   WHERE user_id = '<dads-user-id>';
   ```
4. Dad force-quits the app and reopens — paywall should appear
5. Dad taps "Start 14-day free trial" — when the payment sheet appears, he signs in with the **Sandbox Apple ID** you created (not his real one) — no real charge
6. Purchase completes, app unlocks Pro features
7. Dad adds his real holdings and starts testing

### What Dad Should Test

- [ ] Sign-up flow (Apple Sign-In or Google or email)
- [ ] Push notification permission prompt (appears after sign-in, not before)
- [ ] Adding holdings manually
- [ ] Portfolio grade and individual ticker grades
- [ ] Ticker detail — risk dimensions, news, reasoning
- [ ] Grade alerts (wait for daily recompute ~8am ET, check if push arrives)
- [ ] Daily digest notification (sent ~11am UTC)
- [ ] Paywall → purchase flow → Pro unlocks
- [ ] Restore purchases (sign out + sign back in)
- [ ] Settings — notifications, preferences
- [ ] ETF tickers (SPY, QQQ, VOO — verify they score sensibly)
- [ ] Search / Radar screen

---

## 7-Day Testing Window

### Day 1-2 (June 19-20) — Fix Dad's Bugs + Website Copy

**You and me:**
- Monitor dad's feedback and fix any bugs he reports immediately
- Check Supabase logs and backend logs for errors tied to his account
- Verify his push token registered: `SELECT apns_token FROM user_preferences WHERE user_id = '<dad-id>'`
- Verify he received the daily digest and grade alert pushes

**Website (you + me, section by section):**
- Hero section copy
- How it works / feature explanation
- Pricing section (update to reflect $19.99/month + 14-day trial)
- Footer / legal links

**App Store Connect:**
- Set up Agreements, Tax, and Banking (App Store Connect → Agreements): required before real money can flow post-launch. Takes 24-48h for Apple to process. Start now.

### Day 3-4 (June 21-22) — App Store Listing Assets

**Screenshots (you take, I help with copy overlays if needed):**
- Required sizes: 6.9" (iPhone 16 Pro Max) and 6.5" (iPhone 11 Pro Max) — at minimum 3 per size, ideally 5-6
- Suggested screens to capture: Portfolio overview, Ticker detail with grade, Radar/Search, Digest notification, Paywall
- Use the simulator or dad's device with realistic data

**Metadata (me to draft, you to approve):**
- App name: `Clavix — Portfolio Risk Grades`
- Subtitle (30 chars): `Know your portfolio's real risk`
- Description (4000 chars)
- Keywords (100 chars)
- Support URL: `https://getclavix.com`
- Marketing URL: `https://getclavix.com`

**Privacy Nutrition Labels:**
Data collected: Email Address, Name, Crash Data (Sentry), App Interactions (analytics events), Device ID

### Day 5-6 (June 23-24) — Social Media + Content

**Accounts to create (you):**
- Twitter/X: `@getclavix` or `@clavixapp`
- Instagram: same
- TikTok: same
- LinkedIn page (optional, good for credibility)

**Content farm / slideshow content (me to draft scripts, you to produce):**
- "What's your portfolio's real risk grade?" — reveal format showing a portfolio grading in real time
- "SPY vs individual stocks — how they compare on Clavix" — side-by-side ETF vs stock
- "The 5 dimensions we check on every ticker" — educational breakdown of the 5 risk dims
- "How AAPL actually scored on Clavix this week" — real data, real grade, real reasoning
- "Most people don't know their portfolio is BBB" — hook for the awareness angle

**Landing page updates (me):**
- Wire up any copy changes agreed in Day 1-2
- Add App Store badge link once submission is live

### Day 7 (June 25) — Final Pre-Submission Checklist

**Code (me):**
- [ ] Verify grade flicker still stable after a week of data (check AAPL/AMD/NVDA)
- [ ] Verify SPY/VOO spread closed after daily recomputes with peer news fix
- [ ] Run `verify_data_truth.py` on VPS to confirm data health
- [ ] Supabase: toggle Leaked Password Protection (Dashboard → Auth → Providers → Email)
- [ ] Privacy manifest: add Sentry crash data + analytics data types to `PrivacyInfo.xcprivacy`

**App Store Connect (you):**
- [ ] All screenshots uploaded
- [ ] All metadata filled in
- [ ] Age rating questionnaire completed (answer "None" to everything)
- [ ] Privacy nutrition labels complete
- [ ] Banking/tax agreements approved by Apple
- [ ] Introductory offer approved by Apple
- [ ] App Store review notes added (mention sandbox tester credentials for reviewer)
- [ ] Submit for App Store review

---

## Reference: Key Credentials and IDs

| Item | Value |
|---|---|
| Bundle ID | `com.clavisdev.portfolioassistant` |
| Team ID | `GYMG4MQS8F` |
| IAP Product ID | `clavix_pro_monthly` |
| Backend | `https://clavis.andoverdigital.com` |
| Supabase project | `uwvwulhkxtzabykelvam` (us-west-1) |
| VPS | `sansar@134.122.114.241` via `~/.ssh/id_ed25519` |
| Test user (Sansar) | `7ff5a6c5-8e49-4c2f-be1c-bdc869926699` |

---

## Standing Daily Check (each morning during test window)

```bash
# Backend health
curl -s https://clavis.andoverdigital.com/health

# Data freshness
ssh clavix-vps 'sudo -n docker exec clavis-backend-1 python -m app.scripts.verify_data_truth'

# Backend logs for errors
ssh clavix-vps 'sudo -n docker logs clavis-backend-1 --tail 50 2>&1 | grep -i error'
```
