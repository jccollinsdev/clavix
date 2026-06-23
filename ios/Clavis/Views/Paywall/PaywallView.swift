import SwiftUI
import StoreKit

struct OnboardingPaywallContext: Codable {
    let grade: String
    let score: Int
    let positionCount: Int
    let blindSpotName: String
    let blindSpotAverage: Int
    let weakestTicker: String?
    let dimensionScores: [Int]?

    private static let storageKey = "clavix.onboardingPaywallContext"

    static func store(from reveal: AhaReveal) {
        let payload = OnboardingPaywallContext(
            grade: reveal.grade,
            score: Int(reveal.score.rounded()),
            positionCount: reveal.positionCount,
            blindSpotName: reveal.blindSpot.name,
            blindSpotAverage: Int(reveal.blindSpot.average.rounded()),
            weakestTicker: reveal.weakestTicker,
            dimensionScores: reveal.dimensions.map { Int($0.average.rounded()) }
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
            GeometryReader { proxy in
                let compact = proxy.size.height < 700

                VStack(alignment: .leading, spacing: compact ? 12 : 18) {
                    heroSection(compact: compact)
                    benefitsSection(compact: compact)
                    offerSection(compact: compact)
                    purchaseSection(compact: compact)
                }
                .padding(.horizontal, 24)
                .padding(.top, compact ? 6 : 12)
                .padding(.bottom, compact ? 6 : 12)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .frame(height: proxy.size.height, alignment: .top)
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

    private func heroSection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Text(headline)
                .font(ClavisTypography.inter(compact ? 27 : 30, weight: .semibold))
                .tracking(-0.55)
                .foregroundColor(.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.88)
                .fixedSize(horizontal: false, vertical: true)

            PaywallLockedRiskMap(context: onboardingContext, compact: compact)
        }
    }

    private func benefitsSection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 11) {
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
        if subscriptionManager.isLoading || subscriptionManager.proProduct == nil {
            return "Loading App Store offer…"
        }
        if case .trial = subscriptionManager.status {
            return "Subscribe for \(subscriptionManager.proDisplayPrice)/month"
        }
        return hasIntroductoryOffer
            ? "Start my 14 days free"
            : "Subscribe for \(subscriptionManager.proDisplayPrice)/month"
    }

    @ViewBuilder
    private func offerSection(compact: Bool) -> some View {
        if subscriptionManager.proProduct == nil {
            HStack(spacing: 10) {
                ProgressView().tint(.textSecondary)
                Text("Checking your App Store offer")
                    .font(ClavisTypography.inter(14, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: compact ? 70 : 84)
            .padding(.horizontal, compact ? 12 : 16)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
        } else if hasIntroductoryOffer {
            VStack(alignment: .leading, spacing: compact ? 9 : 12) {
                Text("How your free trial works")
                    .font(ClavisTypography.inter(compact ? 16 : 17, weight: .semibold))
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
            .padding(compact ? 12 : 16)
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

    private func purchaseSection(compact: Bool) -> some View {
        VStack(spacing: compact ? 7 : 10) {
            PaywallPrimaryButton(title: ctaTitle, isLoading: subscriptionManager.isLoading, isEnabled: subscriptionManager.proProduct != nil) {
                Task {
                    if await subscriptionManager.purchase() {
                        onEntitlementActivated?()
                    }
                }
            }

            Text(purchaseCaption)
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

            Text(legalCopy)
                .font(ClavisTypography.inter(compact ? 10 : 11, weight: .regular))
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

    private var purchaseCaption: String {
        guard subscriptionManager.proProduct != nil else { return "This usually takes a moment." }
        return hasIntroductoryOffer ? "No charge today" : "Renews monthly. Cancel anytime."
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
            return "Start your 14-day trial to unlock every position and keep your portfolio monitoring live."
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

private struct PaywallLockedRiskMap: View {
    let context: OnboardingPaywallContext?
    let compact: Bool

    private var scores: [Double] {
        let stored = context?.dimensionScores ?? []
        guard stored.count >= 3 else { return [72, 44, 66, 78, 61] }
        return stored.map(Double.init)
    }

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            ZStack {
                PaywallRadarGraphic(values: scores)
                    .blur(radius: 2.2)
                    .opacity(0.76)

                Circle()
                    .fill(Color.backgroundPrimary.opacity(0.9))
                    .frame(width: compact ? 36 : 42, height: compact ? 36 : 42)
                    .overlay(
                        Image(systemName: "lock.fill")
                            .font(.system(size: compact ? 12 : 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                    )
            }
            .frame(width: compact ? 84 : 100, height: compact ? 72 : 88)

            VStack(alignment: .leading, spacing: 4) {
                Text(context?.weakestTicker ?? "YOUR PORTFOLIO")
                    .font(ClavisTypography.mono(9))
                    .tracking(0.6)
                    .foregroundColor(.textSecondary)
                Text("Full five-signal map")
                    .font(ClavisTypography.inter(compact ? 15 : 16, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(detail)
                    .font(ClavisTypography.inter(compact ? 11 : 12, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 8 : 10)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
    }

    private var detail: String {
        guard let context else { return "Every holding, refreshed daily" }
        return "\(context.blindSpotName) is currently \(context.blindSpotAverage)/100"
    }
}

private struct PaywallRadarGraphic: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let count = max(values.count, 3)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) * 0.43

            ZStack {
                ForEach(1...3, id: \.self) { ring in
                    polygon(
                        values: Array(repeating: 1, count: count),
                        center: center,
                        radius: radius * CGFloat(ring) / 3
                    )
                    .stroke(Color.border.opacity(0.9), lineWidth: 1)
                }

                ForEach(0..<count, id: \.self) { index in
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: point(index: index, count: count, center: center, radius: radius))
                    }
                    .stroke(Color.border.opacity(0.6), lineWidth: 1)
                }

                polygon(values: normalizedValues(count: count), center: center, radius: radius)
                    .fill(Color.good.opacity(0.24))
                polygon(values: normalizedValues(count: count), center: center, radius: radius)
                    .stroke(Color.good, lineWidth: 2)
            }
        }
    }

    private func normalizedValues(count: Int) -> [Double] {
        (0..<count).map { index in
            let raw = values[index % values.count]
            return min(1, max(0.16, raw / 100))
        }
    }

    private func polygon(values: [Double], center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for index in values.indices {
            let point = point(
                index: index,
                count: values.count,
                center: center,
                radius: radius * CGFloat(values[index])
            )
            index == values.startIndex ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func point(index: Int, count: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = (Double(index) / Double(count) * 2 * .pi) - (.pi / 2)
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
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
