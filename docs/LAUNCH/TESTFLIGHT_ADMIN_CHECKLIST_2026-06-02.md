# TestFlight Admin Checklist — 2026-06-02
# Account holder: PRASHAMSHA KATUWAL (Individual Apple Developer)

Each row shows: what to do, where, required for which stage, who does it, and what it blocks.

## Legend
- **Int TF** = Required for Internal TestFlight (your devices only)
- **Ext TF** = Required for External TestFlight (beta testers)
- **ASR** = Required for App Store Release

---

## PART 1 — Apple Developer Account

| # | Task | Where | Int TF | Ext TF | ASR | Who | Blocks |
|---|---|---|---|---|---|---|---|
| A1 | Confirm Apple Developer membership is Active and paid ($99/yr) | developer.apple.com → Account | ✅ YES | ✅ YES | ✅ YES | Human | Everything |
| A2 | Register App ID: `com.clavisdev.portfolioassistant` with Push Notifications capability | developer.apple.com → Certificates, IDs & Profiles → Identifiers → "+" | ✅ YES | ✅ YES | ✅ YES | Human | Build + push |
| A3 | Create an APNs Auth Key (NOT a certificate): download `.p8`, note Key ID | developer.apple.com → Keys → "+" → select Apple Push Notifications service | ✅ YES | ✅ YES | ✅ YES | Human | Push notifications, APNs env vars |
| A4 | Note your Team ID (10-character alphanumeric) | developer.apple.com → Account → Membership | ✅ YES | ✅ YES | ✅ YES | Human | APNs env vars |
| A5 | Create an iOS Distribution Certificate (if not existing) | Xcode → Settings → Accounts → Manage Certificates → "+" → Apple Distribution | ✅ YES | ✅ YES | ✅ YES | Human | Build archive |
| A6 | Create a Provisioning Profile: App Store distribution, bundle ID `com.clavisdev.portfolioassistant` | developer.apple.com → Profiles → "+" → App Store | ✅ YES | ✅ YES | ✅ YES | Human | Build archive |

---

## PART 2 — App Store Connect App Record

| # | Task | Where | Int TF | Ext TF | ASR | Who | Blocks |
|---|---|---|---|---|---|---|---|
| B1 | Create new app: name "Clavix", bundle ID `com.clavisdev.portfolioassistant`, SKU `clavix-ios-v1`, English | appstoreconnect.apple.com → My Apps → "+" → New App | ✅ YES | ✅ YES | ✅ YES | Human | TestFlight, uploads |
| B2 | Set Primary Language: English (U.S.) | App record → App Information | No | ✅ YES | ✅ YES | Human | External TF |
| B3 | Set App Category: Finance (primary), Reference (secondary) | App record → App Information | No | ✅ YES | ✅ YES | Human | App Review |
| B4 | Set Age Rating: Complete questionnaire (expected result: 4+) | App record → App Information → Age Rating | No | ✅ YES | ✅ YES | Human | External TF |
| B5 | Set Support URL: https://getclavix.com | App record → App Store → App Information | No | ✅ YES | ✅ YES | Human | External TF |
| B6 | Set Marketing URL: https://getclavix.com | App record → App Store → App Information | No | ✅ YES | ✅ YES | Human | App Review |
| B7 | Set Privacy Policy URL: https://getclavix.com/privacy | App record → App Store → App Information | No | ✅ YES | ✅ YES | Human | External TF, legal |
| B8 | Configure App Privacy (nutrition labels) — see PRIVACY_LABELS_DRAFT.md | App record → App Privacy | No | ✅ YES | ✅ YES | Human | External TF, legal |
| B9 | Answer Export Compliance: "No" (no encryption beyond standard iOS) | App record or during upload | No | ✅ YES | ✅ YES | Human | Build upload |
| B10 | Sign-in Required: YES. Add test account credentials for Apple Review (use test user `7ff5a6c5`: sansarbikramkarki@gmail.com) | App record → App Review Information | No | No | ✅ YES | Human | App Review |

---

## PART 3 — TestFlight Setup

| # | Task | Where | Int TF | Ext TF | ASR | Who | Blocks |
|---|---|---|---|---|---|---|---|
| C1 | Upload first build via Xcode Archive | Xcode → Product → Archive → Distribute → App Store Connect | ✅ YES | ✅ YES | ✅ YES | Human + Agent | All TF testing |
| C2 | Process build (Apple automated review ~10-30 min) | App Store Connect → TestFlight | ✅ YES | ✅ YES | ✅ YES | Wait | TF availability |
| C3 | Add yourself (PRASHAMSHA KATUWAL) as Internal Tester | App Store Connect → TestFlight → Internal Testing | ✅ YES | No | No | Human | Internal TF |
| C4 | Invite developer (you, Sansar) as Internal Tester via email | App Store Connect → TestFlight → Internal Testing | ✅ YES | No | No | Human | Internal TF |
| C5 | Set Beta App Description for TestFlight (1-2 sentences about the app) | App Store Connect → TestFlight → Test Information | No | ✅ YES | No | Human | External TF |
| C6 | Set Beta App Review contact name, email, phone | App Store Connect → TestFlight → Test Information | No | ✅ YES | No | Human | External TF approval |
| C7 | Set test notes (what testers should try, what's being tested) | App Store Connect → TestFlight → Test Information | No | ✅ YES | No | Human | External TF |
| C8 | Add external testers (email list) | App Store Connect → TestFlight → External Groups → "+" | No | ✅ YES | No | Human | External TF |
| C9 | External TestFlight requires Beta App Review approval from Apple (1-3 days) | Automatic after submitting external build | No | ✅ YES | No | Apple | External TF public link |

---

## PART 4 — In-App Purchases / Subscriptions

| # | Task | Where | Int TF | Ext TF | ASR | Who | Blocks |
|---|---|---|---|---|---|---|---|
| D1 | Accept Paid Apps Agreement (if not already done) | App Store Connect → Agreements, Tax, and Banking | No | No | ✅ YES | Human (PRASHAMSHA KATUWAL) | Subscription products |
| D2 | Set up banking/direct deposit for App Store proceeds | App Store Connect → Agreements, Tax, and Banking | No | No | ✅ YES | Human (PRASHAMSHA KATUWAL) | Receiving revenue |
| D3 | Complete tax forms (W-9 for US individual) | App Store Connect → Agreements, Tax, and Banking | No | No | ✅ YES | Human (PRASHAMSHA KATUWAL) | Paid subscriptions |
| D4 | Create Auto-Renewable Subscription Group: "Clavix Pro" | App Store Connect → In-App Purchases → Manage → Subscription Groups | No | ⚠️ Sandbox | ✅ YES | Human | StoreKit testing |
| D5 | Create subscription product: `clavix_pro_monthly`, $19.99/month, English display name "Clavix Pro", description "Unlimited holdings and watchlist, verbose morning brief, 90-day history, advanced alerts." | App Store Connect → In-App Purchases → "+" → Auto-Renewable Subscription | No | ⚠️ Sandbox | ✅ YES | Human | StoreKit integration |
| D6 | Set 14-day introductory offer (free trial) on `clavix_pro_monthly` | Product → Introductory Offers → "+" → Free Trial → 14 days | No | ⚠️ Sandbox | ✅ YES | Human | Trial UX |
| D7 | Submit subscription product for review (needed even for sandbox testing after code is wired) | App Store Connect → In-App Purchase → Submit for Review | No | ⚠️ Sandbox | ✅ YES | Human | StoreKit sandbox testing |
| D8 | Create sandbox test accounts for subscription testing | App Store Connect → Users and Access → Sandbox Testers | No | ⚠️ Sandbox | ✅ YES | Human | Subscription QA |

---

## PART 5 — APNs Key on VPS

| # | Task | Where | Int TF | Ext TF | ASR | Who | Blocks |
|---|---|---|---|---|---|---|---|
| E1 | Take the downloaded `.p8` file content from Step A3 | Local filesystem after download | ✅ YES | ✅ YES | ✅ YES | Human | APNs delivery |
| E2 | Base64-encode the .p8 file: `base64 -i AuthKey_XXXXXXXX.p8` | Terminal | ✅ YES | ✅ YES | ✅ YES | Human/Agent | APNs env var |
| E3 | SSH to VPS and update `/opt/clavis/backend/.env`: set APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC, APNS_P8_CONTENTS | `ssh clavix-vps` then edit .env | ✅ YES | ✅ YES | ✅ YES | Human | APNs |
| E4 | Restart Docker container: `sudo -n docker compose restart clavis-backend` | SSH session | ✅ YES | ✅ YES | ✅ YES | Human | APNs live |
| E5 | Verify `/health` shows `apns:ok` | `curl https://clavis.andoverdigital.com/health` | ✅ YES | ✅ YES | ✅ YES | Human/Agent | Push notifications |

---

## PART 6 — Signing & Build

| # | Task | Where | Int TF | Ext TF | ASR | Who | Blocks |
|---|---|---|---|---|---|---|---|
| F1 | In Xcode, set Signing Team to PRASHAMSHA KATUWAL's team in project settings | Xcode → Signing & Capabilities | ✅ YES | ✅ YES | ✅ YES | Human | Archive |
| F2 | Ensure bundle ID is `com.clavisdev.portfolioassistant` | Xcode → Signing & Capabilities | ✅ YES | ✅ YES | ✅ YES | Human | Archive |
| F3 | Ensure Push Notifications capability is enabled in Xcode | Xcode → Signing & Capabilities → "+" | ✅ YES | ✅ YES | ✅ YES | Human/Agent | APNs |
| F4 | Bump Marketing Version (e.g., 1.0.0) and Build Number (e.g., 1) | Xcode → Project → General | ✅ YES | ✅ YES | ✅ YES | Human/Agent | Build upload |
| F5 | Product → Archive (on real Mac, not CI, first time) | Xcode | ✅ YES | ✅ YES | ✅ YES | Human | Upload |
| F6 | Distribute App → App Store Connect → Upload | Xcode Organizer | ✅ YES | ✅ YES | ✅ YES | Human | TF availability |

---

## PART 7 — Notes for Individual Account vs LLC

Because the Apple Developer account is under PRASHAMSHA KATUWAL (individual) rather than Andover Digital LLC:

1. **The App Store seller name will be PRASHAMSHA KATUWAL** — visible to all users who tap the developer name on the App Store
2. **App Store proceeds are paid to PRASHAMSHA KATUWAL** — not to Andover Digital LLC. Tax obligations (1099-K) fall on her personally.
3. **The Privacy Policy has already been updated** to disclose the individual distributor role — no change needed there
4. **For internal TestFlight only** (family/personal), this mismatch is not a practical problem
5. **For paid App Store launch**, this requires a tax/legal review — the individual will owe taxes on Pro subscription income
6. **To resolve cleanly**: upgrade to an Organization Apple Developer account under Andover Digital LLC (requires Apple review + D-U-N-S number). This takes ~2 weeks but should be planned for post-beta.

---

## Summary: What must happen before first internal TestFlight build

1. ✅ A1: Membership active
2. ✅ A2: App ID registered 
3. ✅ A5: Distribution certificate
4. ✅ A6: Provisioning profile
5. ✅ B1: App Store Connect record created
6. ✅ B9: Export compliance answered
7. ✅ F1-F4: Xcode signing configured
8. ✅ F5-F6: Archive and upload

That's it for a build to appear in TestFlight internal testing. Everything else can follow.
