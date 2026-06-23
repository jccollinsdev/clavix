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
    @EnvironmentObject private var authViewModel: AuthViewModel
    let reason: SubscriptionRequiredReason

    var body: some View {
        PaywallView(triggerContext: triggerContext, showsCloseButton: false)
            .onAppear { reason.clearPendingContextIfNeeded() }
            .preferredColorScheme(.dark)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Text(statusMessage)
                        .font(ClavisTypography.inter(13, weight: .semibold))
                        .foregroundColor(.textPrimary)

                    Button("Sign out") {
                        Task { await authViewModel.signOut() }
                    }
                    .font(ClavisTypography.inter(13, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ClavixLayout.pad)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(Color.backgroundPrimary)
            }
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

    private var statusMessage: String {
        switch reason {
        case .expired:
            return "Your free trial or subscription has ended"
        case .onboardingReveal:
            return "Your first Clavix snapshot is ready"
        case .notSubscribed:
            return "Start your 14-day free trial to continue"
        }
    }
}
