# Clavix TestFlight Handoff - June 21, 2026

## Current State

Build 10 is code-complete and exported as an App Store Connect IPA. Billing is
server-authoritative, the only trial is Apple's configured 14-day introductory
offer, and the privacy manifest/policy source match current collection.

The build is not yet ready for an end-to-end TestFlight purchase because the
database migration and backend deployment are not live.

## Verified

- App Store JWS signatures and Apple certificate chains are verified by the
  official App Store Server Library.
- Product ID is restricted to `clavix_pro_monthly`.
- Purchases are bound to the authenticated Supabase UUID with
  `appAccountToken`.
- Cross-account transaction replay is rejected.
- Expired, revoked, refunded, upgraded, and stale transactions do not grant
  backend access.
- Holdings, watchlists, and manual refresh use the shared server entitlement.
- Legacy database trial timestamps no longer grant access.
- Introductory StoreKit transactions display as trial until Apple's signed
  expiration date.
- Apple server notification replay is idempotent and older events cannot
  overwrite newer entitlement state.
- App privacy manifest is valid and embedded with Sentry and Swift Crypto
  manifests.
- Exported IPA is Apple Distribution signed with production APNs,
  `beta-reports-active`, and `get-task-allow=false`.
- Python 3.11 audit suite: 31 tests passed.
- Release archive and App Store Connect export succeeded.

## Build Artifact

- Version: `1.0`
- Build: `10`
- Bundle ID: `com.clavisdev.portfolioassistant`
- IPA: `/tmp/Clavis-10-audited-export/Clavis.ipa`
- SHA-256:
  `db7915fb2fe993d366b5343411db281673cdfe47ff9b38534d02b64e5b210266`

## Live Blockers

1. Apply `supabase/migrations/20260621180000_production_storekit_entitlements.sql`.
2. Deploy the changed backend and install
   `app-store-server-library==3.1.2`.
3. Set App Store Server Notifications V2 production and sandbox URL to:
   `https://clavis.andoverdigital.com/subscriptions/app-store-notifications`
4. Deploy `web/privacy.html`; the live policy still shows June 17.
5. Enter the verified selections from
   `docs/legal/APP_STORE_PRIVACY_LABELS_DRAFT.md` in App Store Connect.
6. Upload build 10 and wait for TestFlight processing.
7. Add Dad as an internal tester or submit the build for external beta review.

The Supabase CLI currently stalls at `Initialising login role`, so the
migration has not been applied. The current production notification endpoint
returns `401`, confirming the new backend is not deployed.

## Mock Account

- Email: `sansarbikramkarki@gmail.com`
- Current user ID: `9a9fc8ae-a241-41e2-beb0-2135b0df3a16`
- Onboarding: complete
- Holdings: SMCI, VOO, CME, GEV
- Latest digest: June 21, 2026, grade BBB
- Subscription tier before purchase: free

Confirm the known password works before sending the TestFlight invite. Do not
put the password in source control.

## Dad's End-to-End Test

1. Install build 10 from TestFlight.
2. Sign in with the mock account.
3. Confirm the existing portfolio and June 21 digest load.
4. Open the paywall and start the 14-day free introductory offer.
5. Confirm Apple reports a sandbox/TestFlight purchase with no real charge.
6. Confirm the paywall closes and Pro limits unlock.
7. Add a fourth holding, add more than five watchlist items, and manually
   refresh a ticker.
8. Force-quit and reopen the app; Pro access must remain.
9. Restore purchases and confirm access remains.

TestFlight in-app purchases run in Apple's sandbox environment and do not
charge testers.

## Non-Blocking Cleanup

- Sentry's `profilesSampleRate` setter is deprecated.
- One onboarding local variable is unused.
- The wordmark asset catalog contains an unassigned child.
- Pydantic and Supabase auth dependencies emit deprecation warnings.
