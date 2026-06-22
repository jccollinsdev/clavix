import SwiftUI

enum SubscriptionRequiredReason {
    case notSubscribed
    case expired
}

struct SubscriptionRequiredView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    let reason: SubscriptionRequiredReason

    var body: some View {
        PaywallView(triggerContext: triggerContext, showsCloseButton: false)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Text(statusMessage)
                        .font(ClavisTypography.inter(13, weight: .semibold))
                        .foregroundColor(.clavixInk2)

                    Button("Sign out") {
                        Task { await authViewModel.signOut() }
                    }
                    .font(ClavisTypography.inter(13, weight: .regular))
                    .foregroundColor(.clavixInk3)
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ClavixLayout.pad)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(Color.clavixPage)
            }
    }

    private var triggerContext: PaywallTrigger {
        reason == .expired ? .expiredTrial : .generic
    }

    private var statusMessage: String {
        reason == .expired
            ? "Your free trial or subscription has ended"
            : "Start your 14-day free trial to continue"
    }
}
