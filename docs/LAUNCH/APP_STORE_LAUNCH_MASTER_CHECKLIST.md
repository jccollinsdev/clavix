# Clavix App Store Launch Master Checklist

**Owner:** Sansar / Andover Digital LLC  
**Created:** June 21, 2026  
**Target:** Clavix 1.0 public App Store launch  
**Bundle ID:** `com.clavisdev.portfolioassistant`  
**App Apple ID:** `6775920073`  
**Subscription product:** `clavix_pro_monthly` at $19.99/month  
**Introductory offer:** 14-day free trial, then monthly auto-renewal  
**Current release candidate:** version 1.0, build 10  

This file is the canonical launch checklist. Older launch audits are useful as
history, but this file controls current launch work. Update a checkbox only
after verifying the result, and add evidence beside it when possible.

## Status Legend

- `[x]` Verified complete.
- `[ ] BLOCKER` Must be complete before the next stated gate.
- `[ ] VERIFY` Work may exist, but it has not been verified in the relevant
  production, device, or App Store environment.
- `[ ] TASK` Required work not yet completed.
- `[ ] OPTIONAL` Useful, but not required for version 1.0 launch.

## Current Snapshot

### Verified complete

- [x] Backend deployment is live and `https://clavis.andoverdigital.com/health`
  returns HTTP 200.
- [x] The public App Store notification endpoint is deployed and rejects
  malformed payloads.
- [x] The June 21 privacy policy is live at
  `https://getclavix.com/privacy`.
- [x] StoreKit purchases use `appAccountToken` and send Apple's signed JWS to
  the backend.
- [x] Backend uses Apple's official App Store Server Library and root
  certificates to verify transactions and notifications.
- [x] Cross-account replay, expired purchases, revoked purchases, refunds, and
  stale events are covered by automated tests.
- [x] Legacy database trial dates no longer grant application access in code.
- [x] The 14-day trial is represented as Apple's introductory offer, not a
  second server-created trial.
- [x] Privacy manifest is valid and embedded in the release export.
- [x] Build 10 archives and exports successfully.
- [x] Exported build 10 is Apple Distribution signed with production APNs,
  TestFlight beta entitlement, and `get-task-allow=false`.
- [x] Full backend test suite passes locally: 513 passed, 10 expected failures.
- [x] GitHub backend CI and production deployment completed successfully for
  commit `71ab8db4a`.
- [x] Demo account exists: `sansarbikramkarki@gmail.com`, user
  `9a9fc8ae-a241-41e2-beb0-2135b0df3a16`, with four holdings and a fresh
  digest.
- [x] App contains functional Terms, Privacy, and Restore Purchases controls on
  the paywall.
- [x] `ITSAppUsesNonExemptEncryption` is `false` in the iOS Info.plist.
- [x] App icon set includes the required 1024x1024 marketing icon and iPhone
  icon sizes.

### Hard blockers right now

- [x] Re-authenticate Supabase CLI using the account that owns project
  `uwvwulhkxtzabykelvam`.
- [x] Apply
  `supabase/migrations/20260621180000_production_storekit_entitlements.sql`
  to project `uwvwulhkxtzabykelvam`.
- [x] Verify the live Clavix database contains
  `app_store_subscriptions`, `app_store_notifications`, and the four new
  subscription columns on `user_preferences`.
- [x] Configure App Store Server Notifications V2 for production and
  sandbox to:
  `https://clavis.andoverdigital.com/subscriptions/app-store-notifications`.
- [x] Update and redeploy `web/refund.html` for Apple-managed subscriptions.
- [x] Launch entitlement model is final: no freemium; every user must start the
  Apple 14-day introductory trial or subscribe at $19.99/month, and loses
  product access when the verified StoreKit entitlement expires.
- [ ] BLOCKER Upload build 10 only after the database migration and server
  notification configuration are complete.
- [ ] BLOCKER Complete a real TestFlight purchase, restore, cancellation, and
  expiration test before public App Review.

## Tomorrow: Recommended Order

Do these in order. Stop if a gate fails.

1. [x] Re-authenticate Supabase CLI to the Clavix project owner account.
2. [x] Apply the StoreKit entitlement migration to
   `uwvwulhkxtzabykelvam`.
3. [x] Verify new tables, columns, RLS, mock user data, and a free effective
   tier.
4. [x] Configure Apple Server Notifications V2 in App Store Connect.
5. [ ] Send Apple's test notification and verify HTTP 200 plus a notification
   row in Supabase.
6. [x] Fix and deploy the refund page.
7. [x] Choose trial-only hard paywall and update the shipping entitlement code.
8. [ ] Upload build 10 to App Store Connect.
9. [ ] Resolve export-compliance/build-processing questions and wait for build
   status `Ready to Submit`.
10. [ ] Add the build to a TestFlight group and invite Dad.
11. [ ] Run the complete Dad end-to-end test checklist in this file.
12. [ ] Only after TestFlight passes, finish public App Store metadata and
    submit the app plus subscription for review.

## 1. Product and Scope Decisions

- [x] Launch model: Every new user must start the Apple 14-day trial or
  subscribe at $19.99/month, then loses access when the verified entitlement
  expires. There is no freemium product tier.
- [x] All product features require an active trial, paid subscription, or
  explicit admin entitlement; only onboarding, purchase/restore, account,
  analytics, and subscription-recovery routes remain available while locked.
- [ ] TASK Confirm every Pro feature advertised on the paywall works today.
- [ ] TASK Remove or label anything not shipping in 1.0 as `Coming later`.
- [ ] TASK Confirm brokerage connection remains unavailable in version 1.0.
- [ ] TASK Remove every user-facing claim that brokerage sync is available.
- [ ] VERIFY Confirm CSV import, email alert digests, audit export, and advanced
  alerts are either working or absent from launch copy.
- [ ] TASK Confirm supported market universe: US stocks and ETFs only, and
  state exclusions honestly.
- [ ] TASK Confirm whether version 1.0 launches in the United States only or in
  multiple storefronts.
- [ ] TASK Define launch success metrics: installs, onboarding completion,
  trial starts, first portfolio created, daily active use, trial conversion,
  crash-free sessions, and refunds.

## 2. Supabase and Billing Data

- [x] Log in to Supabase CLI with access to
  `uwvwulhkxtzabykelvam`.
- [x] Link an isolated migration workspace to the correct project and verify the project
  name before running any DDL.
- [x] Dry-run only the StoreKit entitlement migration.
- [x] Apply only
  `20260621180000_production_storekit_entitlements.sql`; do not replay the old
  date-only migration files.
- [x] Verify these `user_preferences` columns:
  - `subscription_expires_at`
  - `subscription_offer_type`
  - `subscription_original_transaction_id`
  - `subscription_environment`
- [x] Verify `app_store_subscriptions` exists with unique original and
  latest transaction IDs.
- [x] Verify `app_store_notifications` exists with unique notification
  UUIDs.
- [x] Verify RLS is enabled and only the service role can manage billing
  rows.
- [x] Verify old `trial_started_at` and `trial_ends_at` values are
  cleared.
- [ ] VERIFY Confirm the mock user still has the expected portfolio and digest
  after migration.
- [ ] VERIFY Confirm a free user cannot change `subscription_tier` through any
  public API.
- [ ] VERIFY Confirm an admin override remains admin after Apple notification
  processing.
- [ ] TASK Back up the production schema before future billing migrations.
- [ ] TASK Repair the repository's legacy Supabase migration history so future
  `supabase db push` commands are safe and do not require an isolated workspace.

## 3. Apple StoreKit and Subscription Configuration

- [x] Confirm subscription group name `Clavix Pro` exists.
- [x] Confirm product ID is exactly `clavix_pro_monthly`.
- [x] Confirm subscription duration is one month.
- [x] Confirm US base price is $19.99.
- [x] Confirm the product is available in the intended launch storefronts:
  United States and Canada.
- [x] Confirm English localization has a display name and accurate
  description.
- [x] Confirm the introductory offer is type `Free`, duration `2 weeks`,
  starts now, and covers every intended storefront.
- [ ] VERIFY Confirm no old or overlapping introductory offer conflicts with
  the 14-day offer.
- [ ] TASK Capture one current paywall screenshot for the subscription's App
  Review Information section.
- [ ] TASK Add subscription review notes explaining the 14-day free trial,
  monthly renewal, restore flow, and demo account.
- [ ] TASK Decide whether to enable Family Sharing. Default recommendation for
  1.0: leave disabled unless explicitly supported and tested.
- [ ] TASK Decide whether to enable Billing Grace Period. If enabled, test and
  document the selected 6-day or 16-day behavior.
- [ ] VERIFY Confirm StoreKit product metadata appears in TestFlight sandbox;
  Apple notes changes can take up to one hour.
- [ ] VERIFY Test an introductory-offer-eligible Apple account.
- [ ] VERIFY Test an Apple account that is not eligible for the intro offer and
  confirm the UI does not promise a free trial.
- [ ] VERIFY Confirm purchase sheet shows $0 for the initial 14 days and the
  correct post-trial renewal price.
- [ ] VERIFY Confirm a purchase unlocks backend-held Pro access.
- [ ] VERIFY Confirm access survives force-quit, reinstall, and sign-in again.
- [ ] VERIFY Confirm Restore Purchases works.
- [ ] VERIFY Confirm cancellation leaves access until Apple's expiration date.
- [ ] VERIFY Confirm expiration returns the account to the chosen free/locked
  state.
- [ ] VERIFY Confirm refund/revocation removes access before normal expiration.
- [ ] VERIFY Confirm one Apple purchase cannot unlock two Clavix accounts.
- [ ] VERIFY Confirm sandbox transactions remain separate from production
  transactions.

## 4. Apple Server Notifications V2

The notification URL is Apple's authenticated webhook into Clavix. Apple calls
it when a subscription renews, expires, enters grace period, fails billing, is
cancelled, refunded, or revoked. It keeps backend access correct even if the
customer never opens the app again.

- [x] Endpoint is deployed:
  `https://clavis.andoverdigital.com/subscriptions/app-store-notifications`.
- [x] Endpoint does not require Clavix user authentication.
- [x] Endpoint verifies Apple's signed payload before changing data.
- [x] Enter the URL under App Store Connect -> App Information -> App
  Store Server Notifications.
- [x] Set both Production Server URL and Sandbox Server URL.
- [x] Use Apple's current Version 2 notification setup for both URLs.
- [ ] BLOCKER Request a test notification from App Store Connect.
- [ ] BLOCKER Confirm Apple reports success and the endpoint returns HTTP 200.
- [ ] BLOCKER Confirm the test notification UUID is stored once in Supabase.
- [ ] VERIFY Confirm duplicate notification delivery returns success without a
  second entitlement mutation.
- [ ] VERIFY Confirm a real sandbox purchase produces DID_SUBSCRIBE and renewal
  events.
- [ ] VERIFY Confirm expiration/refund test events update the mock user's tier.
- [ ] TASK Add monitoring for repeated 4xx/5xx responses on this endpoint.
- [ ] TASK Document notification replay/recovery procedure for an Apple outage.

## 5. Apple Developer and Business Administration

- [ ] VERIFY Confirm Apple Developer Program membership is active through the
  intended launch period.
- [ ] VERIFY Confirm App Store Connect app record exists for App Apple ID
  `6775920073`.
- [ ] VERIFY Confirm bundle ID is `com.clavisdev.portfolioassistant`.
- [ ] VERIFY Confirm Team ID is `GYMG4MQS8F`.
- [x] Confirm the latest Paid Apps Agreement is active. Apple requires
  it for subscriptions and In-App Purchases. (Signed/active per owner, 2026-06-23.)
- [x] Complete banking information and confirm it is approved. (Prerequisite of
  the now-active Paid Apps Agreement; confirm approved status in App Store Connect.)
- [x] Complete all required tax forms, including the US W-9 for a
  US-based account. (W-9 completed per owner, 2026-06-23.)
- [ ] TASK Enroll in the App Store Small Business Program if eligible.
- [ ] TASK Confirm who is the Account Holder and who has Admin/App Manager
  access.
- [ ] TASK Remove unnecessary App Store Connect users and use least privilege.
- [ ] TASK Decide whether to keep the individual Apple developer account or
  convert/transfer to an organization account. The current seller may display
  an individual's name while the app says it is operated by Andover Digital
  LLC.
- [ ] TASK Confirm Andover Digital LLC name, address, EIN, bank account, tax
  identity, website, and legal documents are internally consistent.
- [ ] BLOCKER Complete EU Digital Services Act trader-status declaration even
  if the app will not launch in the EU.
- [ ] BLOCKER If distributing in the EU as a trader, verify the public address
  or P.O. Box, phone, email, payment account, and supporting documents.
- [ ] TASK Decide whether EU storefronts are included at launch. Legal review is
  recommended before a paid EU launch.
- [ ] VERIFY Confirm no pending Apple agreements or compliance banners remain.

## 6. Build, Signing, and Upload

- [x] Version is 1.0 and build is 10.
- [x] Release archive succeeds.
- [x] App Store Connect export succeeds.
- [x] Final app has production `aps-environment`.
- [x] Final app has Sign in with Apple entitlement.
- [x] Final app has `beta-reports-active=true` and `get-task-allow=false`.
- [x] Final app contains the app, Sentry, and Swift Crypto privacy manifests.
- [x] Export-compliance plist flag is present and set to exempt/no non-exempt
  encryption.
- [ ] BLOCKER Confirm build 10 is still the intended source snapshot after all
  launch-blocking code changes. If code changes, increment the build number and
  archive again.
- [ ] BLOCKER Upload the IPA or archive through Xcode/Transporter.
- [ ] BLOCKER Wait for Apple processing and inspect all upload warnings.
- [ ] BLOCKER Resolve Missing Compliance if App Store Connect still asks.
- [ ] BLOCKER Confirm build status is `Ready to Submit`.
- [ ] VERIFY Confirm App Store Connect displays version 1.0, build 10, correct
  icon, and correct bundle ID.
- [ ] VERIFY Download the processed build through TestFlight and verify it is
  the same UI/release candidate.
- [ ] TASK Preserve the final `.xcarchive`, exported IPA, export options, dSYM,
  commit SHA, and SHA-256 in a durable release-artifacts folder outside `/tmp`.
- [ ] TASK Upload dSYMs to Sentry if automatic symbol processing does not cover
  the release.
- [ ] TASK Tag the release commit, for example `v1.0.0-build.10`, only after the
  final accepted build is known.

## 7. TestFlight Setup and Dad Test

- [ ] TASK Decide internal versus external testing:
  - Internal: Dad must be added as an App Store Connect user. Faster, but grants
    account access based on his role.
  - External: Dad only needs an email/TestFlight invitation, but the build must
    pass TestFlight Beta App Review first.
- [ ] TASK Create a TestFlight group named `Family Beta` or similar.
- [ ] TASK Add build 10 to the group.
- [ ] TASK Add beta description, feedback email, privacy policy URL, and test
  notes.
- [ ] TASK Add Dad and confirm the invitation reaches the intended Apple ID.
- [ ] TASK Confirm Dad has the current TestFlight app installed.
- [ ] TASK Confirm the demo-account password works before sending it.
- [ ] TASK Do not store the demo password in Git, docs, screenshots, or review
  notes visible beyond App Review.

### Dad end-to-end acceptance test

- [ ] Fresh install from TestFlight succeeds.
- [ ] App launches without crash or blank screen.
- [ ] Sign in with the mock email/password succeeds.
- [ ] Existing SMCI, VOO, CME, and GEV holdings load.
- [ ] Latest morning digest loads.
- [ ] Search and ticker detail load for a supported stock and ETF.
- [ ] Methodology/audit detail loads and contains real timestamps/sources.
- [ ] Paywall displays the correct live StoreKit price.
- [ ] Paywall displays the 14-day trial only when Apple says eligible.
- [ ] Purchase sheet clearly shows sandbox/TestFlight and no real charge.
- [ ] Starting the trial closes the paywall and unlocks Pro.
- [ ] More than the free holding/watchlist limit can be added when Pro.
- [ ] Manual refresh follows the intended Pro rule and rate limit.
- [ ] Force-quit and reopen preserves entitlement.
- [ ] Sign out and sign in preserves entitlement for the same app account.
- [ ] Restore Purchases succeeds.
- [ ] Notification permission prompt appears at the intended time.
- [ ] Production APNs token is stored in Supabase.
- [ ] Test push arrives on Dad's device.
- [ ] Tapping a push opens the correct screen.
- [ ] Terms and Privacy links open successfully.
- [ ] Data export works and contains expected categories.
- [ ] Account deletion confirmation and behavior are tested on a disposable
  user, not the canonical demo user.
- [ ] Offline/reconnect behavior is understandable and does not erase data.
- [ ] Backend temporary failure shows a recoverable error rather than fake data.
- [ ] Test results, screenshots, device model, iOS version, and bugs are logged.

## 8. App Store Record and Metadata

- [ ] BLOCKER Confirm public app name `Clavix` is available and saved. Apple
  limits app names to 30 characters.
- [ ] TASK Set primary category to Finance.
- [ ] TASK Decide and set a secondary category only if it accurately improves
  discovery.
- [ ] TASK Draft subtitle, maximum 30 characters.
- [ ] TASK Draft promotional text, maximum 170 characters.
- [ ] TASK Draft plain-text description, maximum 4,000 characters.
- [ ] TASK Draft keywords, maximum 100 bytes; do not repeat app/company names or
  use competitor trademarks.
- [ ] TASK Set Support URL to a real support/contact page, not only a marketing
  homepage.
- [ ] TASK Set Marketing URL to `https://getclavix.com`.
- [ ] BLOCKER Set Privacy Policy URL to `https://getclavix.com/privacy`.
- [ ] TASK Set copyright, likely `2026 Andover Digital LLC`, after confirming
  ownership and Apple account identity.
- [ ] TASK Use Apple's standard EULA or enter a custom EULA intentionally; do
  not accidentally maintain conflicting terms.
- [ ] TASK Confirm app version number 1.0.
- [ ] TASK Draft review-safe What's New text if App Store Connect requests it;
  it is usually more relevant to updates than the first release.
- [ ] TASK Proofread every field for `Clavix` versus internal `Clavis` naming.
- [ ] TASK Remove claims about brokerage, guaranteed outcomes, predictions,
  price targets, or features not in the submitted build.
- [ ] TASK Ensure every mention of the trial says 14 days, $0 during trial,
  then the localized monthly price, auto-renewing unless cancelled.
- [ ] TASK Ensure App Store copy consistently states that product access
  requires the trial or subscription; there is no freemium tier.
- [ ] TASK Prepare US English metadata first; localize only after the English
  truth is stable.

## 9. Screenshots and App Preview

- [ ] BLOCKER Capture screenshots from the exact release candidate on a clean,
  realistic demo account.
- [ ] BLOCKER Upload between 1 and 10 iPhone screenshots.
- [ ] BLOCKER Provide accepted 6.9-inch portrait dimensions, such as
  1320x2868, 1290x2796, or 1260x2736, depending on the source simulator/device.
- [ ] TASK Use one coherent screenshot story:
  1. Morning risk brief.
  2. Portfolio grades at a glance.
  3. Five-dimension ticker analysis.
  4. Transparent methodology/audit trail.
  5. Alerts when risk changes.
  6. Watchlist/holdings workflow.
- [ ] TASK Ensure screenshot text is large enough to read on the product page.
- [ ] TASK Do not show fake performance, guaranteed returns, real user data,
  misleading grades, or unavailable features.
- [ ] TASK Do not claim `free` without clarifying the actual launch model.
- [ ] TASK Remove status-bar secrets, personal email, and notification content.
- [ ] TASK Verify all screenshots use the current brand mark and app UI.
- [ ] TASK Upload localized screenshots only if the app metadata is localized.
- [ ] OPTIONAL Create an app preview video. Apple allows up to three per device
  size/language, but screenshots are sufficient for version 1.0.
- [ ] OPTIONAL If using a preview, show only captured app UI, use licensed audio,
  add a poster frame, and allow time for Apple processing.
- [ ] TASK Create the separate subscription App Review screenshot showing the
  paywall and purchase terms.

Official screenshot reference:
`https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications`

## 10. App Privacy, Legal, and Compliance

- [x] Privacy policy is live and dated June 21, 2026.
- [x] Terms are live and include subscriptions, Apple billing, cancellation,
  disclaimers, and account termination.
- [ ] BLOCKER Rewrite the refund policy to remove `free during beta`, `free
  tier`, and `no purchases` statements.
- [ ] BLOCKER State that Apple is merchant of record and refund requests go
  through `reportaproblem.apple.com` or Apple Support.
- [ ] TASK Update refund-policy date and deploy it.
- [ ] TASK Have a qualified attorney review the Terms, Privacy Policy, refund
  policy, arbitration/class waiver, financial disclaimers, and company/seller
  arrangement before public paid launch.
- [ ] BLOCKER Enter and publish App Store privacy answers from
  `docs/legal/APP_STORE_PRIVACY_LABELS_DRAFT.md`.
- [ ] BLOCKER Include first-party data plus Sentry and other integrated SDK data
  in App Privacy answers.
- [ ] VERIFY Confirm App Store privacy preview matches the manifest and policy.
- [ ] TASK Set optional Privacy Choices URL if a dedicated rights-request page
  is created.
- [ ] VERIFY Confirm in-app data export works.
- [ ] VERIFY Confirm in-app account deletion deletes auth, portfolio, alerts,
  analytics association, and StoreKit linkage as intended.
- [ ] TASK Document how support handles manual privacy requests within the
  policy's stated deadline.
- [ ] TASK Confirm MiniMax/AI provider data handling and contract permit the
  disclosed use.
- [ ] TASK Confirm Sentry data retention, region, and PII settings match policy.
- [ ] TASK Confirm APNs token collection is disclosed as a device identifier.
- [ ] TASK Confirm analytics events do not contain portfolio content or secrets.
- [ ] BLOCKER Complete the current Apple age-rating questionnaire. The service
  says it is not directed to under-18 users; do not blindly reuse an old 4+
  answer.
- [ ] BLOCKER Complete Content Rights. Confirm rights to display market data,
  company metadata, news headlines/excerpts, logos, and AI-generated analysis
  in every launch storefront.
- [ ] TASK Retain evidence of Polygon, Finnhub, news-source, font, icon, photo,
  music, and video licenses.
- [ ] BLOCKER Complete export compliance. Info.plist is configured as exempt,
  but verify the App Store Connect answer on the processed build.
- [ ] BLOCKER Complete DSA trader status and any region-specific compliance.
- [ ] TASK Review financial-app obligations with counsel. Clavix must remain
  informational risk analysis, not personalized investment advice, brokerage,
  custody, trading, or guaranteed performance.
- [ ] TASK Ensure `Not financial advice` appears where a reasonable user could
  otherwise mistake grades for recommendations.

Official references:

- App privacy:
  `https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy`
- Age rating:
  `https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating`
- Export compliance:
  `https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance`
- DSA trader requirements:
  `https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements`
- App Review Guidelines:
  `https://developer.apple.com/app-store/review/guidelines/`

## 11. App Review Information

- [ ] BLOCKER Enter a reachable review contact name, phone, and email.
- [ ] BLOCKER Mark sign-in as required.
- [ ] BLOCKER Enter demo email `sansarbikramkarki@gmail.com` and verify the
  current password.
- [ ] BLOCKER Ensure the demo account does not require an inaccessible email or
  SMS code during review.
- [ ] BLOCKER Keep demo data fresh throughout review.
- [ ] TASK Write reviewer notes explaining:
  - Clavix provides informational portfolio-risk analysis.
  - Brokerage connection is not available in version 1.0.
  - How to reach the pre-populated portfolio and morning digest.
  - How to reach the paywall and start the 14-day introductory offer.
  - How to restore purchases.
  - Why background notifications are requested.
  - That market data and analysis may update on schedules.
- [ ] TASK Include any non-obvious feature flags or delayed content behavior.
- [ ] TASK Provide a support contact who will monitor Resolution Center daily.
- [ ] TASK Prepare a concise response template for subscription, financial
  advice, data source, and demo-login questions.

## 12. Availability, Pricing, and Release Controls

- [ ] BLOCKER Set the app itself to Free. Revenue comes from the subscription.
- [ ] BLOCKER Select public distribution, not private/custom distribution.
- [ ] BLOCKER Select intended countries/regions before submission.
- [ ] TASK Start with the US only if legal, support, licensing, pricing, and
  localization are not ready globally.
- [ ] TASK Set the subscription's tax category correctly.
- [ ] TASK Verify the $19.99 base price and Apple's generated storefront prices.
- [ ] TASK Decide whether to support Apple Business/School availability.
- [ ] TASK Select `Manually release this version` for the first launch so
  approval does not publish unexpectedly.
- [ ] TASK Choose a launch date and time with several hours available for
  monitoring and support.
- [ ] TASK Do not enable pre-order unless there is a deliberate campaign and
  complete launch metadata.

## 13. Brand System

### What already exists

- [x] `brand/BRAND.md` exists with name, tagline, tone, logo rules, palette, and
  voice.
- [x] Six PNG icon/wordmark variants exist under `brand/logos/`.
- [x] Social profile image exists at `brand/social/profile-photo.png`.
- [x] Instagram, TikTok, and YouTube setup notes exist.
- [x] Web logo, wordmark, 1024 icon, and LinkedIn banner exist under
  `web/logos/`.

### Brand blockers and tasks

- [ ] BLOCKER Review and commit the currently untracked `brand/` folder once
  its contents are approved.
- [ ] BLOCKER Decide the canonical website domain. Current live domain is
  `getclavix.com`, while social docs and marketing config reference
  `clavixapp.com`.
- [ ] BLOCKER Replace every stale domain with the canonical domain.
- [ ] BLOCKER Correct the public risk dimensions in brand/social copy. Current
  drafts mention volatility, liquidity, momentum, and fundamentals, which do
  not match the shipped five dimensions: news sentiment, financial health,
  macro exposure, sector exposure, and volatility.
- [ ] TASK Create vector masters (`.svg`, `.pdf`, or design-source files) for
  the icon and wordmark; PNG-only masters are fragile.
- [ ] TASK Add minimum sizes, exact clear-space units, background rules, and
  misuse examples to the guide.
- [ ] TASK Specify canonical typography with licensed font files rather than
  `system-default` for external creative.
- [ ] TASK Create App Store screenshot typography/layout templates.
- [ ] TASK Create press-kit exports: transparent PNG, SVG, monochrome, icon,
  horizontal wordmark, founder/company boilerplate, and product screenshots.
- [ ] TASK Create favicon, Open Graph image, social share card, and email-header
  variants.
- [ ] TASK Verify the logo is legible in a circular crop and at 40px.
- [ ] TASK Resolve the Xcode wordmark asset warning about an unassigned child.
- [ ] TASK Decide whether missing 2x/3x variants in non-AppIcon image sets need
  proper assets or intentional single-scale declarations.
- [ ] TASK Review the uncommitted launch-screen logo change and either commit it
  intentionally or discard it intentionally. Do not leave the release source
  ambiguous.
- [ ] TASK Search USPTO and common-law usage for `Clavix`; consult counsel on
  trademark filing and naming risk.
- [ ] TASK Confirm Andover Digital LLC owns all commissioned/generated brand
  assets and fonts.

## 14. Website and Support Surface

- [x] `https://getclavix.com` is live.
- [x] Privacy and Terms pages are live.
- [x] `support@getclavix.com` is published as the support email.
- [ ] BLOCKER Update and deploy the refund policy.
- [ ] BLOCKER Create a dedicated `/support` page with support email, expected
  response time, FAQs, subscription management, restore, refund path, privacy
  request path, and troubleshooting.
- [ ] TASK Point App Store Support URL to that page.
- [ ] TASK Add an App Store download badge only after the final App Store URL
  exists.
- [ ] TASK Replace waitlist/coming-soon CTAs with accurate beta or download
  behavior at the right launch stage.
- [ ] TASK Add the final App Store URL to website, social bios, email signatures,
  and confirmation page.
- [ ] TASK Verify `www.getclavix.com` and apex redirects/canonical URLs.
- [ ] TASK Verify HTTPS, HSTS, mobile layout, keyboard navigation, contrast,
  alt text, and legal links.
- [ ] TASK Add or verify SEO title, meta description, Open Graph/Twitter cards,
  canonical tag, sitemap, and robots.txt.
- [ ] TASK Ensure analytics/cookies on the website match the privacy policy and
  regional consent obligations.
- [ ] TASK Set up `support@getclavix.com` delivery, SPF, DKIM, DMARC, and a
  monitored inbox.
- [ ] TASK Test password-reset and confirmation email delivery on real Gmail,
  iCloud, Outlook, and spam folders.
- [ ] TASK Create a simple public status page or incident notice channel.
- [ ] TASK Add a security-contact path such as `security@getclavix.com` or
  `/.well-known/security.txt`.

## 15. Social Media Setup

The repository contains plans, not proof that accounts are created.

- [ ] VERIFY Reserve and secure `@clavixapp` on Instagram.
- [ ] VERIFY Reserve and secure `@clavixapp` on TikTok.
- [ ] VERIFY Reserve and secure `@clavixapp` on YouTube.
- [ ] TASK Create/reserve a LinkedIn Company Page.
- [ ] TASK Create/reserve an X account if it is part of the launch strategy.
- [ ] OPTIONAL Reserve Threads, Facebook Page, Reddit profile, and Product Hunt
  maker profile.
- [ ] TASK Use a company-owned email and password manager for every account.
- [ ] TASK Enable 2FA and store recovery codes securely.
- [ ] TASK Add at least one backup administrator where the platform supports it.
- [ ] TASK Upload approved profile art and platform-specific banners.
- [ ] TASK Update bios to the shipped five dimensions and final pricing model.
- [ ] TASK Link every profile to `https://getclavix.com` before launch, then to
  the App Store URL with tracked campaign parameters after launch.
- [ ] TASK Add `Not financial advice` where platform space and content context
  require it.
- [ ] TASK Define response policy for support requests, investment questions,
  spam, impersonation, and abusive comments.
- [ ] TASK Create a launch content calendar covering 2 weeks before and 4 weeks
  after release.
- [ ] TASK Prepare at least 9 Instagram feed assets so the profile is not empty.
- [ ] TASK Prepare at least 3 short app-demo videos for Reels/TikTok/Shorts.
- [ ] TASK Prepare one founder/company launch post for LinkedIn.
- [ ] TASK Prepare one pinned `What is Clavix?` post for each platform.
- [ ] TASK Prepare one `How the grades work` post using the correct dimensions.
- [ ] TASK Prepare one privacy/trust/transparency post.
- [ ] TASK Prepare one launch announcement with the real App Store link.
- [ ] TASK Build a lightweight UTM convention by platform, campaign, and asset.
- [ ] TASK Track follower growth, profile visits, link clicks, installs, and
  trial starts without collecting unnecessary personal data.
- [ ] TASK Do not publish ticker grades that cannot be reproduced from the live
  app at the publication timestamp.
- [ ] TASK Do not publish predictions, target prices, guaranteed outcomes, or
  personalized advice.

## 16. Marketing System

### What already exists

- [x] `marketing/README.md` documents a content workflow.
- [x] Carousel renderer and Instagram posting script exist.
- [x] One queued carousel spec exists.
- [x] Screen assets, a mark asset, and one raw b-roll session exist.

### Marketing blockers and tasks

- [ ] BLOCKER Review and commit the currently untracked `marketing/` folder only
  after removing secrets, raw files that should not be versioned, and inaccurate
  claims.
- [ ] BLOCKER Correct the queued `what-is-aaa` carousel. It currently describes
  the wrong scoring dimensions and says `Free on iOS` before launch.
- [ ] BLOCKER Replace all `clavixapp.com` links with the chosen canonical
  domain.
- [ ] TASK Decide whether raw video belongs in Git/LFS, object storage, or a
  private creative drive. Do not casually commit large source media.
- [ ] TASK Render and visually inspect the queued carousel before publishing.
- [ ] TASK Set up Meta Business/Creator account and linked Facebook Page only if
  Instagram Graph API automation is desired.
- [ ] TASK Create Meta developer app and obtain only required permissions.
- [ ] TASK Store Instagram IDs/tokens outside Git and define token-rotation
  ownership.
- [ ] TASK Serve rendered assets publicly only if automated Instagram posting
  is enabled; do not expose private work-in-progress content.
- [ ] TASK Add post-level analytics only after defining a minimal privacy-safe
  schema.
- [ ] TASK Record a clean b-roll library from the release build with no personal
  information.
- [ ] TASK Create reusable templates for 4:5 feed, 9:16 vertical, 16:9 YouTube,
  and LinkedIn formats.
- [ ] TASK Build a content review checklist: factual, reproducible, licensed,
  on-brand, not advice, no unavailable features, correct CTA, correct link.
- [ ] TASK Define a zero/low-budget launch plan and a maximum experimental ad
  budget.
- [ ] OPTIONAL Build posting automation only after manual posts establish what
  performs.
- [ ] OPTIONAL Build a weekly marketing report after there is enough traffic to
  make it useful.

## 17. Product Quality and Device QA

- [ ] BLOCKER Run a clean-install QA pass on the oldest supported iOS version or
  explicitly raise/lower the support decision. Current minimum is iOS 17.0.
- [ ] BLOCKER Test on at least one small-screen iPhone and one large-screen
  iPhone.
- [ ] BLOCKER Test light/dark appearance if both are supported; otherwise lock
  and document the intended appearance.
- [ ] BLOCKER Test VoiceOver on authentication, onboarding, holdings, ticker
  detail, paywall, Settings, and deletion.
- [ ] BLOCKER Test Dynamic Type, Bold Text, Increase Contrast, Reduce Motion,
  and 200% text where practical.
- [ ] BLOCKER Verify no clipped paywall legal text or inaccessible links.
- [ ] BLOCKER Verify all touch targets, loading states, empty states, errors,
  offline states, and retry controls.
- [ ] VERIFY Sign in with Apple on a physical device.
- [ ] VERIFY Google sign-in on a physical device if Google is shown.
- [ ] VERIFY Email sign-up, confirmation, sign-in, password reset, sign-out,
  session expiry, and account deletion.
- [ ] VERIFY APNs permission, token registration, foreground/background receipt,
  and deep link.
- [ ] VERIFY Morning digest scheduling across timezone and daylight-saving
  boundaries.
- [ ] VERIFY Holdings/watchlist limits for free, trial, Pro, expired, and admin.
- [ ] VERIFY Search unsupported ticker behavior.
- [ ] VERIFY Data timestamps and limited-data states never fabricate certainty.
- [ ] VERIFY No old colored-bars logo or internal `Clavis` spelling leaks into
  user-visible UI.
- [ ] TASK Resolve compiler warnings: deprecated Sentry profiling setter and
  unused onboarding variable.
- [ ] TASK Resolve asset-catalog warning for the wordmark.
- [ ] TASK Run Instruments/leak/basic energy pass on key screens.
- [ ] TASK Confirm app launch, dashboard, and paywall remain responsive on a
  slower network.
- [ ] TASK Confirm no secrets or personal data appear in console/Sentry logs.

## 18. Data Quality and Financial Trust

- [ ] BLOCKER Re-run the grade-stability audit on popular names and current demo
  holdings. Older audits found A/BBB and multi-band day-to-day flicker.
- [ ] BLOCKER Define acceptable daily score and grade movement thresholds.
- [ ] BLOCKER Verify hysteresis at the letter-grade write boundary.
- [ ] BLOCKER Verify the displayed grade, score, dimensions, methodology, and
  history all come from one canonical snapshot.
- [ ] VERIFY Confirm SPY, VOO, launch ETFs, and demo holdings are fresh.
- [ ] VERIFY Confirm scheduler jobs complete and failures alert an operator.
- [ ] VERIFY Confirm news sources, timestamps, relevance, and sentiment evidence
  are traceable.
- [ ] VERIFY Confirm limited-data labels appear when fundamentals or news are
  incomplete.
- [ ] TASK Define freshness SLOs for price, news, fundamentals, macro, sectors,
  snapshots, and digests.
- [ ] TASK Define the user-facing behavior when an SLO is missed.
- [ ] TASK Verify data-provider commercial terms permit public paid-app use and
  expected scale.
- [ ] TASK Budget for paid market-data tiers before free-tier limits threaten
  reliability.

## 19. Backend, Security, and Operations

- [x] Production backend deploys from GitHub Actions.
- [x] Backend Docker container restarts automatically.
- [x] Health endpoint is live.
- [x] Backend and iOS Sentry integrations exist.
- [ ] BLOCKER Confirm Sentry receives a symbolicated iOS build-10 test event.
- [ ] BLOCKER Confirm backend Sentry receives an intentional non-sensitive test
  event after the latest deploy.
- [ ] BLOCKER Add an external uptime monitor for `/health` with email/SMS alert.
- [ ] BLOCKER Add scheduler/job-failure alerts.
- [ ] TASK Add a notification-endpoint error-rate alert.
- [ ] TASK Add release/commit tags to backend and iOS Sentry events.
- [ ] TASK Enable and verify DigitalOcean droplet backups.
- [ ] TASK Verify Supabase backup/PITR policy and run a documented restore test.
- [ ] TASK Write a rebuild-from-repository runbook.
- [ ] TASK Write rollback steps for backend, database migration, and iOS release.
- [ ] TASK Review firewall, SSH users/keys, sudo access, Docker exposure, and
  patch cadence.
- [ ] TASK Rotate any old shared keys and remove unused provider credentials.
- [ ] TASK Run dependency/security scans for Python and Swift packages.
- [ ] TASK Verify Supabase RLS on every user-owned table.
- [ ] TASK Verify rate limits on auth-adjacent, analysis, refresh, support, and
  public webhook endpoints.
- [ ] TASK Confirm webhook logs never store full signed payloads or personal
  data unnecessarily.
- [ ] TASK Define data retention for analytics, notifications, diagnostics,
  deleted accounts, and backups.
- [ ] TASK Create an incident severity and response process.
- [ ] TASK Document who receives alerts and who can deploy/rollback.
- [ ] TASK Confirm production environment variables match `.env.example` for
  App Store bundle ID, app Apple ID, allowed product IDs, and online checks.

## 20. Analytics and Launch Measurement

- [x] First-party events exist for paywall view, purchase tap, purchase success,
  trial start, and restore tap.
- [ ] BLOCKER Verify each funnel event arrives from TestFlight without PII.
- [ ] TASK Add/verify onboarding-started, onboarding-completed, portfolio-created,
  first-digest-viewed, notification-enabled, and account-deleted events.
- [ ] TASK Define one canonical funnel dashboard.
- [ ] TASK Separate Sandbox/TestFlight and Production purchase analytics.
- [ ] TASK Track trial eligibility, start, conversion, cancellation, billing
  retry, refund, and churn using Apple reports plus verified backend state.
- [ ] TASK Define crash-free session and API reliability targets.
- [ ] TASK Define a daily launch dashboard and a weekly product review.
- [ ] TASK Avoid vanity metrics; connect social campaigns to installs and trial
  starts with privacy-safe aggregate attribution.

## 21. Customer Support and Operations

- [ ] BLOCKER Confirm `support@getclavix.com` can send and receive reliably.
- [ ] TASK Define support hours and target response time.
- [ ] TASK Prepare responses for login, missing digest, stale score, trial,
  cancellation, refund, restore, push, privacy, and deletion questions.
- [ ] TASK Train support to direct billing/refund disputes to Apple without
  promising refunds Clavix cannot issue.
- [ ] TASK Create a bug-report template requesting app version, build, device,
  iOS version, time, and steps without requesting passwords.
- [ ] TASK Create a feature-request log and severity rubric.
- [ ] TASK Monitor App Store reviews and respond professionally.
- [ ] TASK Create a process for urgent inaccurate-data reports.
- [ ] TASK Define when to post incidents to the status page/social accounts.

## 22. Submission and Review

- [ ] BLOCKER Select the final processed build on version 1.0.
- [ ] BLOCKER Complete every required metadata field and clear all yellow/red
  App Store Connect indicators.
- [ ] BLOCKER Attach and submit `clavix_pro_monthly` for App Review using its
  required screenshot and metadata.
- [ ] BLOCKER Add the app version and subscription to the intended review
  submission flow.
- [ ] BLOCKER Click Add for Review, inspect the draft submission, then Submit for
  Review.
- [ ] TASK Monitor App Review and Resolution Center at least daily.
- [ ] TASK Respond to reviewer questions with exact steps and evidence.
- [ ] TASK If rejected, record guideline, root cause, fix, and response in this
  file before resubmitting.
- [ ] TASK Do not change production billing behavior while a build is in review
  unless the reviewer-facing flow remains valid.
- [ ] TASK Keep the demo account operational until review and launch are
  complete.

Official submission flow:
`https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/`

## 23. Launch-Day Runbook

- [ ] BLOCKER App status is approved and `Pending Developer Release`.
- [ ] BLOCKER Subscription is approved/available and correctly attached.
- [ ] BLOCKER Production database migration and notification URL are verified.
- [ ] BLOCKER Production health, auth, mock user, StoreKit product, and APNs are
  green.
- [ ] BLOCKER Website legal/support pages show final content.
- [ ] BLOCKER No unresolved P0/P1 launch bugs.
- [ ] TASK Freeze backend and marketing changes several hours before release.
- [ ] TASK Take database and droplet backups.
- [ ] TASK Confirm on-call contact and dashboards are open.
- [ ] TASK Manually release version 1.0.
- [ ] TASK Confirm the App Store page is visible in intended storefronts.
- [ ] TASK Install the public App Store build on a clean device.
- [ ] TASK Run signup, portfolio, paywall, purchase, restore, and notification
  smoke tests.
- [ ] TASK Replace website/social CTAs with the final App Store link.
- [ ] TASK Publish launch posts only after the public product page works.
- [ ] TASK Monitor health, Sentry, Supabase, purchase events, support inbox, and
  App Store reviews throughout launch day.
- [ ] TASK Record launch timestamp, build, commit, storefronts, and known issues.

## 24. First 24 Hours and First 30 Days

### First 24 hours

- [ ] Review crash-free sessions and top errors.
- [ ] Review API uptime/latency and scheduler completion.
- [ ] Review sign-up, onboarding, portfolio, paywall, and trial-start funnels.
- [ ] Verify Apple notifications and entitlement transitions.
- [ ] Respond to support and App Store reviews.
- [ ] Pause marketing if purchase, auth, data truth, deletion, or crash issues
  appear.

### First 7 days

- [ ] Review activation and retention by acquisition source.
- [ ] Review failed purchases, restores, cancellations, and refunds.
- [ ] Review stale-data and grade-stability reports.
- [ ] Ship only urgent fixes; batch low-risk polish.
- [ ] Publish transparent help content for recurring questions.

### First 30 days

- [ ] Review trial-to-paid conversion and churn.
- [ ] Review provider costs and infrastructure headroom.
- [ ] Confirm Small Business Program proceeds if enrolled.
- [ ] Decide annual plan, broader storefronts, paid data tiers, and next feature
  scope using real evidence.
- [ ] Update privacy labels/policies for any changed data practice.
- [ ] Run a backup restore drill and security review.

## Go/No-Go Gates

### Gate A: Upload build to TestFlight

- [x] Correct Supabase migration is live.
- [ ] Apple notification URL is configured; test notification still needs to
  succeed and be verified in Supabase.
- [x] Refund page is truthful.
- [x] Final entitlement model is decided.
- [ ] Build number matches final source.

### Gate B: Give Dad full end-to-end access

- [ ] Build is processed and assigned to his TestFlight group.
- [ ] Demo credentials work.
- [ ] StoreKit product and trial appear.
- [ ] Purchase, backend entitlement, restore, and push work on his device.
- [ ] No P0 beta issue remains.

### Gate C: Submit to public App Review

- [ ] Dad/TestFlight acceptance test passes.
- [ ] Agreements, tax, banking, DSA, privacy, age rating, content rights, and
  export compliance are complete.
- [ ] Metadata, screenshots, subscription screenshot, review notes, and demo
  account are complete.
- [ ] Legal/refund/support pages are final.
- [ ] Data stability, Sentry, uptime, backups, and job alerts are verified.
- [ ] App and subscription are both ready for review.

### Gate D: Release publicly

- [ ] App and subscription are approved.
- [ ] Production smoke test and backups pass.
- [ ] Support and monitoring are staffed.
- [ ] Website and social launch assets are ready with the final App Store link.
- [ ] Owner explicitly approves manual release.

## Reference Files

- Billing/TestFlight handoff:
  `docs/AUDITS/CLAVIX_TESTFLIGHT_HANDOFF_2026-06-21.md`
- App Store privacy answers:
  `docs/legal/APP_STORE_PRIVACY_LABELS_DRAFT.md`
- App Store setup notes:
  `docs/LAUNCH/APP_STORE_CONNECT_SETUP_NOTES_2026-06-02.md`
- Brand guide: `brand/BRAND.md`
- Marketing system: `marketing/README.md`
- StoreKit migration:
  `supabase/migrations/20260621180000_production_storekit_entitlements.sql`
- Release export options: `ios/ExportOptions-TestFlight.plist`
- Privacy policy source: `web/privacy.html`
- Terms source: `web/terms.html`
- Refund source requiring update: `web/refund.html`

## Apple Reference Links

- App information and field limits:
  `https://developer.apple.com/help/app-store-connect/reference/app-information`
- Version metadata and field limits:
  `https://developer.apple.com/help/app-store-connect/reference/platform-version-information`
- Screenshot specifications:
  `https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications`
- Upload builds:
  `https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds`
- Introductory offers:
  `https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions`
- Subscription setup:
  `https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions`
- Internal TestFlight testers:
  `https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers`
- Agreements:
  `https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements`
- Tax information:
  `https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information`
- Availability:
  `https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store`
- Release controls:
  `https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option`
