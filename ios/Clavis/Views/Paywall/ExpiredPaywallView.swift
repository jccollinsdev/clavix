import SwiftUI

struct ExpiredPaywallView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        PaywallView(triggerContext: .expiredTrial, showsCloseButton: false)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Text("Your free trial has ended")
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
}
