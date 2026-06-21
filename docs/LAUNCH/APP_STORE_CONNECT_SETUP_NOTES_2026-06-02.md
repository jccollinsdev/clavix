# App Store Connect Setup Notes — 2026-06-02
# Account: PRASHAMSHA KATUWAL (Individual Apple Developer)

This document is a step-by-step walkthrough of exactly what to do in Apple Developer and App Store Connect to get Clavix from zero to first internal TestFlight build.

---

## Step 1 — Verify Apple Developer Membership

URL: https://developer.apple.com/account/  
**What to do:** Sign in as PRASHAMSHA KATUWAL. Confirm:
- Membership status: Active
- Program type: Apple Developer Program ($99/yr)
- Expiration date: More than 30 days away

If expired: Renew at https://developer.apple.com/programs/enroll/ → $99

---

## Step 2 — Register the App ID

URL: https://developer.apple.com/account/resources/identifiers/list  
**What to do:**
1. Click the blue "+" button
2. Select "App IDs" → Continue
3. Select "App" → Continue
4. Description: `Clavix`
5. Bundle ID: Explicit → `com.clavisdev.portfolioassistant`
6. Capabilities: Scroll to "Push Notifications" → check the box ✓
7. Continue → Register

**Confirm:** The App ID `com.clavisdev.portfolioassistant` appears in your identifiers list with Push Notifications capability enabled.

---

## Step 3 — Create APNs Auth Key

URL: https://developer.apple.com/account/resources/authkeys/list  
**What to do:**
1. Click the blue "+" button
2. Name: `Clavix APNs Key`
3. Check "Apple Push Notifications service (APNs)" → Continue → Register
4. **CRITICAL:** Click "Download" → save the file as `AuthKey_XXXXXXXX.p8` (where XXXXXXXX is the Key ID)
5. Write down:
   - Key ID: shown as `XXXXXXXX` in the filename
   - Team ID: visible at https://developer.apple.com/account → Membership → Team ID

⚠️ The .p8 file can ONLY be downloaded once. If lost, you must revoke and create a new key.

---

## Step 4 — Add APNs Credentials to VPS

```bash
# On your local machine, base64-encode the .p8 file:
base64 -i ~/Downloads/AuthKey_XXXXXXXX.p8 | tr -d '\n'
# Copy the output

# SSH to VPS:
ssh clavix-vps

# Edit the .env file:
sudo -n nano /opt/clavis/backend/.env
```

Add these lines (replace with your actual values):
```
APNS_KEY_ID=XXXXXXXX
APNS_TEAM_ID=XXXXXXXXXX
APNS_TOPIC=com.clavisdev.portfolioassistant
APNS_P8_CONTENTS=<paste the base64-encoded .p8 content here>
```

Then restart:
```bash
cd /opt/clavis && sudo -n docker compose restart clavis-backend
# Verify:
curl https://clavis.andoverdigital.com/health
# Expected: {"status":"ok","apns":"ok",...}
```

---

## Step 5 — Create App Store Connect Record

URL: https://appstoreconnect.apple.com/apps  
**What to do:**
1. Click the blue "+" → New App
2. Platforms: iOS
3. Name: `Clavix`
4. Primary Language: English (U.S.)
5. Bundle ID: Select `com.clavisdev.portfolioassistant` from dropdown (will appear after Step 2)
6. SKU: `clavix-ios-v1` (internal, not shown to users)
7. User Access: Full access (for now)
8. Create

---

## Step 6 — Fill App Information

In the app record → App Information:
- Subtitle (optional): `Portfolio risk, graded.`
- Category: Finance (primary), Reference (secondary)
- Content Rights: Check "No, it does not contain, show, or access third-party content"
- Age Rating: Complete the questionnaire
  - Unrestricted web access: No
  - Gambling: No
  - Medical/Treatment: No
  - All others: None/No
  - Expected result: 4+

---

## Step 7 — Configure App Privacy Labels

In the app record → App Privacy → Get Started:

Use the verified selections in
`docs/legal/APP_STORE_PRIVACY_LABELS_DRAFT.md`. The current app collects
linked account, portfolio, APNs token, purchase-history, preference, and
first-party product-interaction data. Sentry diagnostics are collected without
being linked to identity. Nothing is used for tracking.

---

## Step 8 — Set App Store Metadata (for App Review, can wait for external TF)

- Support URL: https://getclavix.com
- Marketing URL: https://getclavix.com
- Privacy Policy URL: https://getclavix.com/privacy

App Review Information (needed for public App Store, not internal TF):
- Sign-in required: YES
- Demo account email: sansarbikramkarki@gmail.com
- Demo account password: [the actual test account password]
- Notes to reviewer: "Clavix is a portfolio risk analysis app. Sign in with the demo credentials to see a pre-populated portfolio with real risk scores."

---

## Step 9 — Set Up Subscription Products

In the app record → In-App Purchases → Manage → Subscriptions:

1. Create subscription group:
   - Reference Name: `Clavix Pro`
   - Click "Create"

2. Add subscription:
   - Product ID: `clavix_pro_monthly` ← exact string, must match iOS code
   - Reference Name: `Clavix Pro Monthly`
   - Subscription Duration: 1 month
   - Click "Create"

3. Configure the subscription:
   - Price: $19.99 USD (select from price tiers — Tier 17 is $19.99)
   - Localizations → English (U.S.):
     - Display Name: `Clavix Pro`
     - Description: `Unlimited holdings & watchlist, verbose morning briefing, 90-day score history, advanced alerts, and the deepest audit view.`
   - Introductory Offer: Free Trial
     - Duration: 2 weeks (14 days)
     - Customer pays: $0 during the introductory period
   - Click "Save"

4. Submit for review (required even for sandbox testing with StoreKit 2):
   - Screenshot required: A screenshot of the subscription UI in your app
   - Once you have a build in TestFlight, take a screenshot of the upgrade sheet and upload here

---

## Step 10 — Agreements, Tax, and Banking

⚠️ This is required before any paid App Store transactions (not needed for free TestFlight).

URL: App Store Connect → Agreements, Tax, and Banking

1. Accept the "Paid Apps" agreement (electronic)
2. Set up banking: PRASHAMSHA KATUWAL's US bank account for direct deposit
3. Complete tax forms:
   - If US person: W-9 form (takes ~5 minutes online)
   - Apple issues 1099-K for App Store proceeds paid to this account

---

## Step 11 — Configure Xcode Signing

In Xcode:
1. Open `ios/Clavis.xcodeproj`
2. Target → Signing & Capabilities
3. Team: Select `PRASHAMSHA KATUWAL (Personal Team)` from dropdown
4. Bundle Identifier: Confirm `com.clavisdev.portfolioassistant`
5. Automatically manage signing: ON (easiest for first build)
6. Add capability: `Push Notifications` (click "+" → Push Notifications)
7. Confirm the provisioning profile auto-updates

---

## Step 12 — Upload First Build

1. In Xcode: Select "Any iOS Device (arm64)" as the destination
2. Product → Archive
3. When Organizer opens: click "Distribute App"
4. Select "App Store Connect" → Next
5. Options: Upload, include bitcode if prompted → Upload
6. Wait for upload to complete (~2-5 minutes)
7. In App Store Connect → TestFlight → iOS Builds: wait for build to process (10-30 min)
8. Build should appear as "Ready to Submit" in TestFlight

---

## Step 13 — Internal TestFlight

1. In App Store Connect → TestFlight → Internal Testing:
2. Click "+" next to the build
3. Add testers: your own Apple ID, PRASHAMSHA KATUWAL's Apple ID
4. All internal testers receive an invite email
5. Accept invite on iPhone (or use the TestFlight app)
6. Install and test

---

## What TestFlight Internal Testing Does NOT Require

- Subscription products set up (StoreKit will show "no products" until D4-D7 above)
- APNs .p8 key (app will work without push; just no push notifications)
- External Beta App Review from Apple
- Screenshots or app description
- Age rating (needed for external TF)

---

## Timeline Estimate

| Task | Time | Depends on |
|---|---|---|
| Steps 1-4 (account, App ID, APNs) | 30 min | You |
| Steps 5-8 (App Store Connect record) | 20 min | Step 1 complete |
| P0-1 through P0-4 fixes (agent) | 1-2 hours | Nothing |
| P0-8 StoreKit scaffold (agent) | 2-3 hours | Nothing (full test needs D4-D7) |
| Steps 9-10 (subscriptions, banking) | 1-2 hours | Step 5 complete |
| Xcode signing + Archive + Upload | 30 min | Steps 1-11 complete |
| Apple processes build | 10-30 min | Upload complete |
| Internal TestFlight available | 0 min after processing | Steps above |
| Subscription sandbox testing | After D4-D7 + P0-8 | 2-3 more hours |
| External TestFlight (after Beta Review) | 1-3 days after external submission | All above |
