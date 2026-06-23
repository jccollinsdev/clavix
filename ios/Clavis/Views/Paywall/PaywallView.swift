import SwiftUI
import StoreKit

// MARK: - PaywallView
// Presented whenever a user hits a Pro-gated feature.
// Requires SubscriptionManager to be in the environment.
struct PaywallView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let triggerContext: PaywallTrigger
    var showsCloseButton: Bool = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    Divider().padding(.horizontal, ClavixLayout.pad)
                    featuresSection
                    Divider().padding(.horizontal, ClavixLayout.pad)
                    pricingSection
                    ctaSection
                    legalFooter
                }
                .padding(.bottom, ClavixLayout.bottomPad)
            }
            .background(Color.clavixPage.ignoresSafeArea())
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .font(ClavisTypography.clavixMono(11, weight: .semibold))
                            .foregroundColor(.clavixInk3)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Clavix Pro")
        }
        .preferredColorScheme(.light)
        .onAppear {
            AnalyticsService.track(
                AnalyticsEventName.paywallViewed,
                properties: ["trigger": triggerContext.analyticsName]
            )
        }
        .alert("Purchase Error", isPresented: .init(
            get: { subscriptionManager.purchaseError != nil },
            set: { if !$0 { subscriptionManager.purchaseError = nil } }
        )) {
            Button("OK") { subscriptionManager.purchaseError = nil }
        } message: {
            Text(subscriptionManager.purchaseError ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ClavixEyebrow("Clavix Pro")
            Text("Depth, history,\nand your whole book.")
                .font(ClavisTypography.clavixSerif(30, weight: .medium))
                .tracking(-0.5)
                .foregroundColor(.clavixInk)
                .fixedSize(horizontal: false, vertical: true)
            if let context = triggerContext.message {
                Text(context)
                    .font(ClavisTypography.inter(14, weight: .regular))
                    .foregroundColor(.clavixInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, ClavixLayout.pad)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ClavixEyebrow("What Pro includes")
                .padding(.horizontal, ClavixLayout.pad)
                .padding(.top, 20)
                .padding(.bottom, 12)
            ClavixCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(PaywallFeature.all.enumerated()), id: \.element.title) { index, feature in
                        PaywallFeatureRow(feature: feature)
                        if index < PaywallFeature.all.count - 1 {
                            Rectangle().fill(Color.clavixRule).frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, ClavixLayout.pad)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Computed helpers

    private var hasIntroductoryOffer: Bool {
        subscriptionManager.isEligibleForIntroOffer
            && subscriptionManager.proProduct?.subscription?.introductoryOffer != nil
    }

    private var trialSubtitle: String {
        if case .trial(let expiresAt) = subscriptionManager.status {
            let days = max(0, Int(expiresAt.timeIntervalSinceNow / 86400))
            return "\(days) day\(days == 1 ? "" : "s") remaining in your free trial"
        }
        if hasIntroductoryOffer { return "14-day free trial · cancel anytime" }
        return "cancel anytime"
    }

    private var ctaTitle: String {
        if subscriptionManager.isLoading { return "Loading…" }
        if case .trial = subscriptionManager.status {
            return "Subscribe — \(subscriptionManager.proDisplayPrice)/mo"
        }
        return hasIntroductoryOffer ? "Start 14-day free trial" : "Subscribe — \(subscriptionManager.proDisplayPrice)/mo"
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ClavixEyebrow("Pricing")
                .padding(.horizontal, ClavixLayout.pad)
                .padding(.top, 20)
            ClavixCard(fill: .clavixAccentSoft) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(subscriptionManager.proDisplayPrice)
                            .font(ClavisTypography.clavixMono(24, weight: .bold))
                            .foregroundColor(.clavixAccentInk)
                        Text("/ month")
                            .font(ClavisTypography.inter(14, weight: .regular))
                            .foregroundColor(.clavixAccentInk)
                    }
                    Text(trialSubtitle)
                        .font(ClavisTypography.inter(12, weight: .regular))
                        .foregroundColor(.clavixAccentInk)
                }
            }
            .padding(.horizontal, ClavixLayout.pad)
            .padding(.bottom, 20)
        }
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            ClavisPrimaryButton(title: ctaTitle) {
                Task { await subscriptionManager.purchase() }
            }
            .disabled(subscriptionManager.isLoading || subscriptionManager.proProduct == nil)

            Button("Restore purchases") {
                Task { await subscriptionManager.restorePurchases() }
            }
            .font(ClavisTypography.inter(13, weight: .regular))
            .foregroundColor(.clavixInk3)
            .buttonStyle(.plain)
            .disabled(subscriptionManager.isLoading)

            if subscriptionManager.proProduct == nil && !subscriptionManager.isLoading {
                Text("Subscription product is loading. Please try again in a moment.")
                    .font(ClavisTypography.inter(12, weight: .regular))
                    .foregroundColor(.clavixWarn)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, ClavixLayout.pad)
        .padding(.vertical, 20)
    }

    // MARK: - Legal footer

    private var legalFooter: some View {
        VStack(spacing: 10) {
            Text(hasIntroductoryOffer
                 ? "No charge for 14 days. Then \(subscriptionManager.proDisplayPrice)/month, automatically renewing unless cancelled at least 24 hours before the trial or current billing period ends. Manage or cancel in Settings > Apple ID > Subscriptions. Clavix is informational only — not investment advice."
                 : "Payment is charged to your Apple ID at purchase and renews at \(subscriptionManager.proDisplayPrice)/month unless cancelled at least 24 hours before the current billing period ends. Manage or cancel in Settings > Apple ID > Subscriptions. Clavix is informational only — not investment advice.")
                .font(ClavisTypography.inter(11, weight: .regular))
                .foregroundColor(.clavixInk4)
                .multilineTextAlignment(.center)
            HStack(spacing: 20) {
                Link("Terms of Use", destination: URL(string: "https://getclavix.com/terms")!)
                    .font(ClavisTypography.inter(11, weight: .medium))
                    .foregroundColor(.clavixInk3)
                Link("Privacy Policy", destination: URL(string: "https://getclavix.com/privacy")!)
                    .font(ClavisTypography.inter(11, weight: .medium))
                    .foregroundColor(.clavixInk3)
            }
        }
        .padding(.horizontal, ClavixLayout.pad)
        .padding(.bottom, 12)
    }
}

// MARK: - PaywallTrigger
enum PaywallTrigger {
    case holdingLimit
    case verboseDigest
    case watchlistLimit
    case advancedAlerts
    case expiredTrial
    case onboardingReveal
    case generic

    var message: String? {
        switch self {
        case .holdingLimit:
            return "Your subscription is required to add and monitor positions across your whole portfolio."
        case .verboseDigest:
            return "The verbose morning briefing explains what overnight news means for each position in depth. It's a Pro feature."
        case .watchlistLimit:
            return "Your subscription is required to monitor watchlist tickers and receive ongoing risk updates."
        case .advancedAlerts:
            return "Advanced alerts (watchlist grade changes, macro-shock signals, and portfolio-level risk triggers) are Pro features."
        case .expiredTrial:
            return "Your free trial has ended. Subscribe to keep tracking your full portfolio risk picture."
        case .onboardingReveal:
            return "Your first Clavix snapshot is ready. Start your 14-day trial to unlock the full five-dimension breakdown for every position and keep this portfolio live inside the app."
        case .generic:
            return nil
        }
    }

    var analyticsName: String {
        switch self {
        case .holdingLimit:
            return "holding_limit"
        case .verboseDigest:
            return "verbose_digest"
        case .watchlistLimit:
            return "watchlist_limit"
        case .advancedAlerts:
            return "advanced_alerts"
        case .expiredTrial:
            return "expired_trial"
        case .onboardingReveal:
            return "onboarding_reveal"
        case .generic:
            return "generic"
        }
    }
}

// MARK: - Feature list

private struct PaywallFeature {
    let icon: String
    let title: String
    let description: String

    static let all: [PaywallFeature] = [
        .init(icon: "chart.line.uptrend.xyaxis", title: "Unlimited holdings & watchlist", description: "Track your whole book and every name you follow."),
        .init(icon: "newspaper.fill", title: "Verbose morning briefing", description: "Each position gets a paragraph-level explanation of what overnight news means for its risk profile."),
        .init(icon: "clock.arrow.2.circlepath", title: "90-day score history", description: "All five risk dimensions over 90 days with sparklines."),
        .init(icon: "bell.badge.fill", title: "Advanced alerts", description: "Watchlist grade changes, macro-shock signals, and portfolio-grade triggers."),
        .init(icon: "doc.text.magnifyingglass", title: "Deep audit view", description: "Every regression coefficient, every article's sentiment reasoning, full methodology drill-down."),
    ]
}

private struct PaywallFeatureRow: View {
    let feature: PaywallFeature

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.clavixAccent)
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(ClavisTypography.inter(13, weight: .semibold))
                    .foregroundColor(.clavixInk)
                Text(feature.description)
                    .font(ClavisTypography.inter(12, weight: .regular))
                    .foregroundColor(.clavixInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
