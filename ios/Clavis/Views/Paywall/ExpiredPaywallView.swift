import SwiftUI

enum SubscriptionRequiredReason {
    case notSubscribed
    case expired
    case onboardingReveal

    private static let pendingInitialPaywallContextKey = "clavix.pendingInitialPaywallContext"

    static func markPendingOnboardingReveal() {
        UserDefaults.standard.set("onboarding_reveal", forKey: pendingInitialPaywallContextKey)
    }

    static func resolveInitialNotSubscribedReason() -> SubscriptionRequiredReason {
        let stored = UserDefaults.standard.string(forKey: pendingInitialPaywallContextKey)
        return stored == "onboarding_reveal" ? .onboardingReveal : .notSubscribed
    }

    func clearPendingContextIfNeeded() {
        guard self == .onboardingReveal else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingInitialPaywallContextKey)
    }
}

struct SubscriptionRequiredView: View {
    let reason: SubscriptionRequiredReason

    var body: some View {
        PaywallView(triggerContext: triggerContext, showsCloseButton: false)
            .onAppear { reason.clearPendingContextIfNeeded() }
            .preferredColorScheme(.dark)
    }

    private var triggerContext: PaywallTrigger {
        switch reason {
        case .expired:
            return .expiredTrial
        case .onboardingReveal:
            return .onboardingReveal
        case .notSubscribed:
            return .generic
        }
    }

}
