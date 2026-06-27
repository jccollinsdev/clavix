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

    private var ctx: OnboardingPaywallContext? {
        guard triggerContext == .onboardingReveal else { return nil }
        return OnboardingPaywallContext.load()
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let compact = proxy.size.height < 740

                VStack(alignment: .leading, spacing: compact ? 14 : 18) {
                    heroSection(compact: compact)
                    benefitsSection(compact: compact)
                    Spacer(minLength: compact ? 8 : 16)
                    purchaseSection(compact: compact)
                    legalFooter(compact: compact)
                }
                .padding(.horizontal, 24)
                .padding(.top, compact ? 6 : 10)
                .padding(.bottom, compact ? 20 : 34)
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

    // MARK: - Hero (personalized to the user's weakest signal)

    private func heroSection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 13) {
            Text(headline)
                .font(ClavisTypography.inter(compact ? 27 : 30, weight: .semibold))
                .tracking(-0.55)
                .foregroundColor(.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            Text(subhead)
                .font(ClavisTypography.inter(compact ? 14 : 15, weight: .regular))
                .foregroundColor(.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            PaywallBlindSpotCard(context: ctx, compact: compact)
                .padding(.top, compact ? 4 : 6)
        }
    }

    // MARK: - Benefits (outcome-framed)

    private func benefitsSection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 11) {
            Text("With Pro")
                .font(ClavisTypography.inter(compact ? 15 : 16, weight: .semibold))
                .foregroundColor(.textPrimary)

            ForEach(Array(benefits.enumerated()), id: \.offset) { _, benefit in
                HStack(spacing: 11) {
                    Image(systemName: benefit.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.backgroundPrimary)
                        .frame(width: 25, height: 25)
                        .background(Color.textPrimary)
                        .clipShape(Circle())
                    Text(benefit.title)
                        .font(ClavisTypography.inter(14, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Purchase (CTA + price)

    private func purchaseSection(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 10) {
            PaywallPrimaryButton(title: ctaTitle, isLoading: subscriptionManager.isLoading, isEnabled: subscriptionManager.proProduct != nil) {
                Task {
                    if await subscriptionManager.purchase() {
                        onEntitlementActivated?()
                    }
                }
            }

            Text(purchaseCaption)
                .font(ClavisTypography.inter(13, weight: .medium))
                .foregroundColor(.textSecondary)
        }
    }

    private func legalFooter(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 8) {
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
        }
        .frame(maxWidth: .infinity)
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
            ? "Start my 14-day trial"
            : "Subscribe for \(subscriptionManager.proDisplayPrice)/month"
    }

    // The user's weakest signal, lowercased for mid-sentence use ("macro resilience").
    private var blindSpotLower: String {
        (ctx?.blindSpotName ?? "macro resilience").lowercased()
    }

    private var headline: String {
        if ctx != nil {
            let name = blindSpotLower
            return "\(name.prefix(1).uppercased())\(name.dropFirst()) is your blind spot."
        }
        switch triggerContext {
        case .expiredTrial:
            return "Keep your risk monitoring live."
        case .onboardingReveal:
            return "Unlock your full risk map."
        default:
            return "See the risk behind every position."
        }
    }

    private var subhead: String {
        if ctx != nil {
            return "Pro reveals the \(blindSpotLower) behind every holding, plus four more risk signals built from thousands of data points."
        }
        return "See every holding across five risk signals, built from thousands of data points."
    }

    private var benefits: [(icon: String, title: String)] {
        let name = ctx != nil ? blindSpotLower : "your weakest signal"
        return [
            ("scope", "Understand where your portfolio risk comes from"),
            ("doc.text.magnifyingglass", "See what's dragging \(name) down, holding by holding"),
            ("magnifyingglass", "Look up any company's risk rating before you invest"),
            ("newspaper.fill", "Get a daily digest of what improved or worsened"),
            ("bell.badge.fill", "Get notified when stock or portfolio grades change")
        ]
    }

    private var purchaseCaption: String {
        guard subscriptionManager.proProduct != nil else { return "This usually takes a moment." }
        let price = subscriptionManager.proDisplayPrice
        return hasIntroductoryOffer
            ? "$0 today, then \(price)/mo · cancel anytime"
            : "\(price)/mo · cancel anytime"
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

// MARK: - Personalized blind-spot card

private struct PaywallBlindSpotCard: View {
    let context: OnboardingPaywallContext?
    let compact: Bool

    private var scores: [Double] {
        let stored = context?.dimensionScores ?? []
        guard stored.count >= 3 else { return [72, 44, 66, 78, 61] }
        return stored.map(Double.init)
    }

    private var blindSpotValue: Int { context?.blindSpotAverage ?? 44 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 11) {
            HStack(spacing: compact ? 13 : 16) {
                PaywallRadarGraphic(values: scores)
                    .frame(width: compact ? 82 : 96, height: compact ? 74 : 86)

                VStack(alignment: .leading, spacing: 5) {
                    Text(blindSpotLabel)
                        .font(ClavisTypography.inter(compact ? 13 : 14, weight: .semibold))
                        .foregroundColor(.textPrimary)

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(blindSpotValue)")
                            .font(ClavisTypography.mono(compact ? 24 : 28))
                            .foregroundColor(.warn)
                        Text("/100")
                            .font(ClavisTypography.inter(13, weight: .regular))
                            .foregroundColor(.textSecondary)
                    }

                    ProgressBar(value: Double(blindSpotValue) / 100)
                        .frame(height: 4)
                }
                Spacer(minLength: 0)
            }

            // Locked breakdown: the sub-factors that feed this score.
            // Bars are visible; labels and values are blurred behind the lock.
            VStack(alignment: .leading, spacing: compact ? 6 : 7) {
                ForEach(Array(factorRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        Text(row.label)
                            .font(ClavisTypography.inter(11, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .lineLimit(1)
                            .frame(width: compact ? 96 : 112, alignment: .leading)

                        ProgressBar(value: row.frac)
                            .frame(height: 5)

                        Text("\(row.score)")
                            .font(ClavisTypography.mono(11))
                            .foregroundColor(.textPrimary)
                            .frame(width: 20, alignment: .trailing)
                    }
                }
            }
            .padding(.top, compact ? 2 : 3)
            .blur(radius: compact ? 2.7 : 3.1)
            .overlay(
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Get Pro to unlock data")
                        .font(ClavisTypography.inter(13, weight: .semibold))
                }
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.backgroundPrimary.opacity(0.9))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.border.opacity(0.85), lineWidth: 1))
            )
        }
        .padding(.horizontal, compact ? 14 : 16)
        .padding(.vertical, compact ? 12 : 14)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
    }

    private var blindSpotLabel: String {
        let raw = (context?.blindSpotName ?? "Macro resilience")
        let lower = raw.lowercased()
        return "\(lower.prefix(1).uppercased())\(lower.dropFirst())"
    }

    // Synthesized sub-factor teaser. Values are derived from the blind-spot
    // score so the bars look related to the real number; they're blurred, so
    // they read as "there's real detail here, locked" rather than exact data.
    private var factorRows: [(label: String, frac: Double, score: Int)] {
        let base = Double(blindSpotValue)
        let specs: [(String, Double)] = [
            ("Rate sensitivity", 0.74),
            ("Cyclical exposure", 1.22),
            ("Balance-sheet strength", 0.56),
            ("Demand durability", 1.08)
        ]
        return specs.prefix(compact ? 3 : 4).map { spec in
            let v = min(94, max(8, base * spec.1))
            return (spec.0, v / 100, Int(v.rounded()))
        }
    }
}

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.border.opacity(0.6))
                Capsule()
                    .fill(Color.warn)
                    .frame(width: max(4, proxy.size.width * min(1, max(0, value))))
            }
        }
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
                    .fill(Color.warn.opacity(0.26))
                polygon(values: normalizedValues(count: count), center: center, radius: radius)
                    .stroke(Color.warn, lineWidth: 2)
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
