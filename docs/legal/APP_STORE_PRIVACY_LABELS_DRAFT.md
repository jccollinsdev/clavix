# App Store Privacy Labels

**Verified:** June 21, 2026
**Status:** Ready to enter in App Store Connect
**Tracking:** No
**Privacy Policy URL:** https://getclavix.com/privacy

These answers match the iOS privacy manifest, first-party analytics, Sentry
configuration, APNs registration, StoreKit entitlement storage, and backend
data model as of build 10.

## App Store Connect Answers

Select **Yes, we collect data from this app**. Do not declare tracking and do
not add any tracking domains.

| App Store data type | Linked to identity | Used for tracking | Purpose |
|---|---:|---:|---|
| Contact Info - Email Address | Yes | No | App Functionality |
| Contact Info - Name | Yes | No | App Functionality |
| Financial Info - Other Financial Info | Yes | No | App Functionality |
| Identifiers - User ID | Yes | No | App Functionality, Analytics |
| Identifiers - Device ID | Yes | No | App Functionality |
| Purchases - Purchase History | Yes | No | App Functionality |
| Usage Data - Product Interaction | Yes | No | Analytics |
| Diagnostics - Crash Data | No | No | App Functionality |
| Diagnostics - Performance Data | No | No | App Functionality |
| Diagnostics - Other Diagnostic Data | No | No | App Functionality |
| Other Data - Other Data Types | Yes | No | App Functionality |

## What Each Answer Covers

- **Email Address:** Supabase authentication and account communication.
- **Name:** optional profile personalization.
- **Other Financial Info:** portfolio tickers, share quantities, cost basis,
  watchlists, and related risk-analysis inputs.
- **User ID:** Supabase account UUID, including linkage to first-party product
  analytics events.
- **Device ID:** APNs device token used only to deliver notifications.
- **Purchase History:** verified App Store transaction identifiers, product ID,
  environment, offer type, and entitlement dates. Clavix does not receive card
  or payment credentials.
- **Product Interaction:** paywall, trial, purchase, and restore events stored
  as first-party analytics.
- **Diagnostics:** Sentry collects crash, performance, and diagnostic data with
  `sendDefaultPii = false`, so these are not linked to the user's identity.
- **Other Data Types:** optional birth year, timezone, notification schedule,
  alert preferences, onboarding state, and similar app settings.

## Explicitly Do Not Select

- Payment Info
- Credit or Debit Card
- Bank Account Info
- Precise or Coarse Location
- Contacts
- Photos or Videos
- Audio Data
- Health or Fitness
- Browsing History
- Search History
- Advertising Data
- Advertising Identifier
- Sensitive Info

## Consistency Check

- `NSPrivacyTracking` is `false`.
- The app privacy manifest declares all linked first-party data above.
- Sentry's embedded privacy manifest declares unlinked diagnostics.
- The public policy discloses Apple App Store purchase processing, Sentry,
  first-party analytics, APNs, portfolio data, and account deletion.
- App Store Connect remains the source of truth; these selections must be
  entered there before App Review.
