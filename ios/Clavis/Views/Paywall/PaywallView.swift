import SwiftUI
import StoreKit

struct OnboardingPaywallContext: Codable {
    let grade: String
    let score: Int
    let positionCount: Int
    let blindSpotName: String
    let blindSpotAverage: Int
    let weakestTicker: String?

    private static let storageKey = "clavix.onboardingPaywallContext"

    static func store(from reveal: AhaReveal) {
        let payload = OnboardingPaywallContext(
            grade: reveal.grade,
            score: Int(reveal.score.rounded()),
            positionCount: reveal.positionCount,
            blindSpotName: reveal.blindSpot.name,
            blindSpotAverage: Int(reveal.blindSpot.average.rounded()),
            weakestTicker: reveal.weakestTicker
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func load() -> OnboardingPaywallContext? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(OnboardingPaywallContext.self, from: data)
    }
}

// MARK: - PaywallView
// Presented whenever a user hits a Pro-gated feature.
// Requires SubscriptionManager to be in the environment.
struct PaywallView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let triggerContext: PaywallTrigger
    var showsCloseButton: Bool = true
    var onEntitlementActivated: (() -> Void)? = nil

    private var onboardingContext: OnboardingPaywallContext? {
        guard triggerContext == .onboardingReveal else { return nil }
        return OnboardingPaywallContext.load()
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    heroSection
                    benefitsSection
                    offerSection
                    purchaseSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Close")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Clavix Pro")
        }
        .preferredColorScheme(.dark)
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

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headline)
                .font(ClavisTypography.inter(30, weight: .semibold))
                .tracking(-0.55)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let supportingCopy {
                Text(supportingCopy)
                    .font(ClavisTypography.inter(15, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.76))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onboardingContext {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(onboardingContext.weakestTicker ?? "YOUR PORTFOLIO")
                            .font(ClavisTypography.mono(10))
                            .tracking(0.6)
                            .foregroundColor(.textSecondary)
                        Text(onboardingContext.blindSpotName)
                            .font(ClavisTypography.inter(14, weight: .medium))
                            .foregroundColor(.textPrimary)
                    }
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(onboardingContext.blindSpotAverage)")
                            .font(ClavisTypography.mono(22))
                            .foregroundColor(.warn)
                        Text("/100")
                            .font(ClavisTypography.mono(9))
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(14)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
            }
        }
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(Array(benefits.enumerated()), id: \.offset) { _, benefit in
                HStack(spacing: 11) {
                    Image(systemName: benefit.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.backgroundPrimary)
                        .frame(width: 25, height: 25)
                        .background(Color.textPrimary)
                        .clipShape(Circle())
                    Text(benefit.title)
                        .font(ClavisTypography.inter(14, weight: .medium))
                        .foregroundColor(.textPrimary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Computed helpers

    private var hasIntroductoryOffer: Bool {
        subscriptionManager.isEligibleForIntroOffer
            && subscriptionManager.proProduct?.subscription?.introductoryOffer != nil
    }

    private var ctaTitle: String {
        if subscriptionManager.isLoading { return "Loading…" }
        if case .trial = subscriptionManager.status {
            return "Subscribe for \(subscriptionManager.proDisplayPrice)/month"
        }
        return hasIntroductoryOffer
            ? "Start my 14 days free"
            : "Subscribe for \(subscriptionManager.proDisplayPrice)/month"
    }

    @ViewBuilder
    private var offerSection: some View {
        if hasIntroductoryOffer {
            VStack(alignment: .leading, spacing: 14) {
                Text("How your free trial works")
                    .font(ClavisTypography.inter(17, weight: .semibold))
                    .foregroundColor(.textPrimary)

                PaywallTimelineRow(
                    marker: "1",
                    title: "Today",
                    detail: "Full access, no charge"
                )
                PaywallTimelineRow(
                    marker: "2",
                    title: "Day 14",
                    detail: "\(subscriptionManager.proDisplayPrice)/month"
                )
                PaywallTimelineRow(
                    marker: "3",
                    title: "Anytime",
                    detail: "Cancel in Apple ID settings"
                )
            }
            .padding(16)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text("Monthly")
                    .font(ClavisTypography.inter(15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(subscriptionManager.proDisplayPrice)
                    .font(ClavisTypography.mono(22))
                    .foregroundColor(.textPrimary)
                Text("/ month")
                    .font(ClavisTypography.inter(12, weight: .regular))
                    .foregroundColor(.textSecondary)
            }
            .padding(16)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: 11) {
            PaywallPrimaryButton(title: ctaTitle, isLoading: subscriptionManager.isLoading, isEnabled: subscriptionManager.proProduct != nil) {
                Task {
                    if await subscriptionManager.purchase() {
                        onEntitlementActivated?()
                    }
                }
            }

            Text(hasIntroductoryOffer ? "No charge today" : "Renews monthly. Cancel anytime.")
                .font(ClavisTypography.inter(12, weight: .medium))
                .foregroundColor(.textSecondary)

            HStack(spacing: 18) {
                Button("Restore") {
                    Task {
                        if await subscriptionManager.restorePurchases() {
                            onEntitlementActivated?()
                        }
                    }
                }
                .disabled(subscriptionManager.isLoading)

                Link("Terms", destination: URL(string: "https://getclavix.com/terms")!)
                Link("Privacy", destination: URL(string: "https://getclavix.com/privacy")!)
            }
            .font(ClavisTypography.inter(11, weight: .medium))
            .foregroundColor(.textSecondary)
            .buttonStyle(.plain)

            if subscriptionManager.proProduct == nil && !subscriptionManager.isLoading {
                Text("Subscription product is loading. Please try again in a moment.")
                    .font(ClavisTypography.inter(12, weight: .regular))
                    .foregroundColor(.warn)
                    .multilineTextAlignment(.center)
            }

            Text(legalCopy)
                .font(ClavisTypography.inter(11, weight: .regular))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headline: String {
        switch triggerContext {
        case .onboardingReveal:
            return "Unlock your full risk map."
        case .expiredTrial:
            return "Keep your risk monitoring live."
        default:
            return "See the risk behind every position."
        }
    }

    private var supportingCopy: String? {
        if onboardingContext != nil { return nil }
        switch triggerContext {
        case .holdingLimit:
            return "Track every position in one risk view."
        case .verboseDigest:
            return "Get the full reasoning behind every score."
        case .watchlistLimit, .advancedAlerts:
            return "Monitor every ticker and know when its risk changes."
        case .expiredTrial:
            return "Keep your scores, history, and alerts active."
        default:
            return "Track your portfolio across five daily risk signals."
        }
    }

    private var benefits: [(icon: String, title: String)] {
        [
            ("chart.bar.fill", "Every holding across five risk signals"),
            ("newspaper.fill", "Daily scores, news, and reasoning"),
            ("bell.fill", "Alerts when your risk picture changes")
        ]
    }

    private var legalCopy: String {
        if hasIntroductoryOffer {
            return "After 14 days, renews at \(subscriptionManager.proDisplayPrice)/month unless canceled at least 24 hours before renewal."
        }
        return "Payment is charged at purchase and renews at \(subscriptionManager.proDisplayPrice)/month unless canceled at least 24 hours before renewal."
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

private struct PaywallTimelineRow: View {
    let marker: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Text(marker)
                .font(ClavisTypography.mono(10))
                .foregroundColor(.backgroundPrimary)
                .frame(width: 24, height: 24)
                .background(Color.textPrimary)
                .clipShape(Circle())
            Text(title)
                .font(ClavisTypography.inter(13, weight: .semibold))
                .foregroundColor(.textPrimary)
            Spacer()
            Text(detail)
                .font(ClavisTypography.inter(13, weight: .regular))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct PaywallPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous)
                    .fill(isEnabled ? Color.textPrimary : Color.white.opacity(0.04))
                    .frame(height: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous)
                            .stroke(isEnabled ? Color.clear : Color.white.opacity(0.12), lineWidth: 1)
                    )

                if isLoading {
                    ProgressView()
                        .tint(.backgroundPrimary)
                } else {
                    Text(title)
                        .font(ClavisTypography.inter(15, weight: .semibold))
                        .foregroundColor(isEnabled ? .backgroundPrimary : Color.white.opacity(0.32))
                }
            }
            .opacity(isEnabled ? 1 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}
