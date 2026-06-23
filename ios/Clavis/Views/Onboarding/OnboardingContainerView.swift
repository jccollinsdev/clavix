import SwiftUI
import UniformTypeIdentifiers

struct OnboardingContainerView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = OnboardingViewModel()
    @StateObject private var brokerageViewModel = BrokerageViewModel()
    @State private var showUpgradeSheet = false
    @State private var showCSVSheet = false

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            Group {
                switch viewModel.currentPage {
                case .welcome:
                    OnboardingIntroSlideView(
                        step: 1,
                        title: "Meet your morning\nrisk briefing.",
                        bodyCopy: "Clavix helps you understand what changed in your portfolio before the open, without turning your morning into research work.",
                        supportingCards: [
                            .init(eyebrow: "Every morning", title: "One book grade", detail: "See whether your portfolio looks sturdier or shakier at a glance."),
                            .init(eyebrow: "Always inspectable", title: "Evidence shown", detail: "Every grade traces back to the factors behind it, not black-box hype.")
                        ],
                        primaryTitle: "Continue",
                        secondaryTitle: "Sign in with a different account",
                        onPrimary: { viewModel.nextPage() },
                        onSecondary: { Task { await authViewModel.signOut() } }
                    )
                case .methodology:
                    OnboardingIntroSlideView(
                        step: 2,
                        title: "Clavix grades risk,\nnot momentum.",
                        bodyCopy: "The app acts more like a compact risk desk than a trading feed. It scores what you own across five dimensions and tells you where the book looks soft.",
                        supportingCards: [
                            .init(eyebrow: "Five dimensions", title: "Macro, sector, financials, news, volatility", detail: "You get one consistent framework instead of disconnected headlines."),
                            .init(eyebrow: "What you will not get", title: "No buy alerts, no fake certainty", detail: "Clavix is informational only. It helps you inspect risk with more discipline.")
                        ],
                        primaryTitle: "How my snapshot works",
                        secondaryTitle: "Back",
                        onPrimary: { viewModel.nextPage() },
                        onSecondary: { viewModel.previousPage() }
                    )
                case .preview:
                    OnboardingIntroSlideView(
                        step: 3,
                        title: "We’ll build your first\nportfolio snapshot.",
                        bodyCopy: "Enter 1 to 3 positions you actually care about. Clavix will grade the book, surface the weakest link, and show the biggest blind spot worth paying attention to.",
                        supportingCards: [
                            .init(eyebrow: "What you enter", title: "Ticker + shares", detail: "That is enough to build a first-pass risk picture."),
                            .init(eyebrow: "What you unlock next", title: "A personalized reveal", detail: "Your trial starts after you see why your own portfolio is interesting.")
                        ],
                        primaryTitle: "Build my snapshot",
                        secondaryTitle: "Back",
                        onPrimary: { viewModel.nextPage() },
                        onSecondary: { viewModel.previousPage() }
                    )
                case .addPortfolio:
                    OnboardingPortfolioAhaView(
                        viewModel: viewModel,
                        isFreeTier: !SubscriptionManager.shared.isPro,
                        onBack: { viewModel.previousPage() },
                        onFinish: completeAfterAha,
                        onSkip: completeAndOpenHoldings
                    )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.currentPage)
        }
        .sheet(
            isPresented: Binding(
                get: { brokerageViewModel.presentedURL != nil },
                set: { if !$0 { brokerageViewModel.presentedURL = nil } }
            )
        ) {
            if let url = brokerageViewModel.presentedURL {
                SafariView(url: url)
            }
        }
        .sheet(isPresented: $showCSVSheet) {
            if !SubscriptionManager.shared.isPro {
                PaywallView(triggerContext: .generic)
                    .environmentObject(SubscriptionManager.shared)
            } else {
                CSVImportSheet()
            }
        }
        .sheet(isPresented: $showUpgradeSheet) {
            PaywallView(triggerContext: .holdingLimit)
                .environmentObject(SubscriptionManager.shared)
        }
        .onReceive(NotificationCenter.default.publisher(for: .snapTradeCallbackReceived)) { notification in
            guard let url = notification.object as? URL else { return }
            Task { await brokerageViewModel.handleCallback(url: url) }
        }
        .preferredColorScheme(.dark)
    }

    private func handleConnectBrokerage() {
        if !SubscriptionManager.shared.isPro {
            showUpgradeSheet = true
            return
        }

        Task {
            await brokerageViewModel.startConnect()
        }
    }

    private func completeAndOpenHoldings() {
        viewModel.completeOnboarding {
            authViewModel.markOnboardingComplete()
            UserDefaults.standard.set(0, forKey: "clavix.selectedTab")
            NotificationCenter.default.post(name: .openAddHoldingFromOnboarding, object: nil)
        }
    }

    /// Called from the aha reveal CTA. Positions were already created during the
    /// analyzing phase, so route straight to the populated Holdings tab without
    /// re-opening the add sheet.
    private func completeAfterAha() {
        if !SubscriptionManager.shared.isPro {
            if let reveal = viewModel.reveal {
                OnboardingPaywallContext.store(from: reveal)
            }
            SubscriptionRequiredReason.markPendingOnboardingReveal()
        }
        viewModel.completeOnboarding {
            authViewModel.markOnboardingComplete()
            UserDefaults.standard.set(1, forKey: "clavix.selectedTab")
        }
    }
}

private struct OnboardingIntroCardContent {
    let eyebrow: String
    let title: String
    let detail: String
}

private struct OnboardingIntroSlideView: View {
    let step: Int
    let title: String
    let bodyCopy: String
    let supportingCards: [OnboardingIntroCardContent]
    let primaryTitle: String
    let secondaryTitle: String
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 28)

                Text("STEP 0\(step) / 04")
                    .font(ClavisTypography.mono(11))
                    .tracking(0.8)
                    .foregroundColor(.textSecondary)
                    .padding(.bottom, 14)

                Text(title)
                    .font(ClavisTypography.inter(34, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)

                Text(bodyCopy)
                    .font(ClavisTypography.inter(15, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 24)

                VStack(spacing: 12) {
                    ForEach(Array(supportingCards.enumerated()), id: \.offset) { _, card in
                        OnboardingIntroCard(card: card)
                    }
                }
                .padding(.bottom, 24)

                OnboardingMiniPreview(step: step)
                    .padding(.bottom, 28)

                VStack(spacing: 10) {
                    AuthStyleActionButton(
                        title: primaryTitle,
                        fill: .textPrimary,
                        foreground: .backgroundPrimary,
                        action: onPrimary
                    )

                    AuthStyleActionButton(
                        title: secondaryTitle,
                        fill: .surface,
                        foreground: .textPrimary,
                        bordered: true,
                        action: onSecondary
                    )
                }
                .padding(.bottom, 18)

                OnboardingProgressBar(step: step, total: 4)
                    .padding(.bottom, 18)

                Text("You’ll see your first personalized risk snapshot before anything asks you to commit.")
                    .font(ClavisTypography.mono(10))
                    .foregroundColor(Color.white.opacity(0.52))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            OnboardingStickyBar()
        }
    }
}

private struct OnboardingIntroCard: View {
    let card: OnboardingIntroCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.eyebrow.uppercased())
                .font(ClavisTypography.mono(10))
                .tracking(0.8)
                .foregroundColor(Color.white.opacity(0.5))
            Text(card.title)
                .font(ClavisTypography.inter(17, weight: .semibold))
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(card.detail)
                .font(ClavisTypography.inter(14, weight: .regular))
                .foregroundColor(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
    }
}

private struct OnboardingMiniPreview: View {
    let step: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT HAPPENS NEXT")
                .font(ClavisTypography.mono(10))
                .tracking(0.8)
                .foregroundColor(Color.white.opacity(0.5))

            HStack(spacing: 10) {
                previewCell(label: "Enter", value: "1-3")
                previewCell(label: "Score", value: "Book")
                previewCell(label: "Reveal", value: "Blind spot")
            }
        }
        .padding(16)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
    }

    private func previewCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(ClavisTypography.mono(9))
                .tracking(0.7)
                .foregroundColor(.textSecondary)
            Text(value)
                .font(ClavisTypography.inter(15, weight: .semibold))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous))
    }
}

private struct OnboardingProgressBar: View {
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(index < step ? Color.textPrimary : Color.white.opacity(0.12))
                    .frame(height: 4)
            }
        }
    }
}

private struct OnboardingStickyBar: View {
    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                ZStack {
                    Image("clavix_logo")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundColor(.textPrimary)
                    Image("clavix_logo")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .scaleEffect(1.18)
                        .foregroundColor(.textPrimary.opacity(0.3))
                }
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
                Spacer(minLength: 8)
            }

            Text("CLAVIX")
                .font(ClavisTypography.inter(17, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.backgroundPrimary.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
        }
    }
}

private struct AuthStyleActionButton: View {
    let title: String
    let fill: Color
    let foreground: Color
    var bordered: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ClavisTypography.inter(15, weight: .semibold))
                .foregroundColor(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous)
                        .stroke(bordered ? Color.border : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingWelcomeView: View {
    let onContinue: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            HStack(spacing: 10) {
                Image("clavix_logo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.clavixInk)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text("CLAVIX")
                    .font(ClavisTypography.clavixMono(20, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(.clavixInk)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 32)

            Text("Portfolio risk,\nmeasured.")
                .font(ClavisTypography.clavixSerif(36, weight: .medium))
                .tracking(-0.5)
                .foregroundColor(.clavixInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 16)

            Text("Clavix scores your positions across five risk dimensions every morning, with the reasoning shown. Not investment advice. Risk intelligence.")
                .font(ClavisTypography.inter(15, weight: .regular))
                .foregroundColor(.clavixInk2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 40)

            Text("1 of 2")
                .font(ClavisTypography.clavixMono(10, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.clavixInk3)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 20)

            OnboardingActionButton(title: "Get started", fill: .clavixInk, foreground: .clavixPaper, action: onContinue)
                .padding(.bottom, 12)

            Button("Sign in with a different account") { onSignIn() }
                .font(ClavisTypography.inter(13, weight: .regular))
                .foregroundColor(.clavixInk3)
                .buttonStyle(.plain)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clavixPage)
    }
}

private struct OnboardingAddPortfolioView: View {
    let isFreeTier: Bool
    let isCompleting: Bool
    let errorMessage: String?
    let onBack: () -> Void
    let onConnectBrokerage: () -> Void
    let onImportCSV: () -> Void
    let onAddManually: () -> Void
    let onSkip: () -> Void
    var brokerageAvailable: Bool = false

    var body: some View {
        ClavixScreen(
            eyebrow: "Step 2 of 2",
            title: "Add portfolio",
            trailing: AnyView(
                Button("Back", action: onBack)
                    .font(ClavisTypography.clavixMono(10, weight: .semibold))
                    .foregroundColor(.clavixAccent)
                    .buttonStyle(.plain)
            )
        ) {
            Text("Choose how to add your positions. You can change this at any time from Holdings.")
                .font(ClavisTypography.inter(15, weight: .regular))
                .foregroundColor(.clavixInk2)
                .fixedSize(horizontal: false, vertical: true)

            OnboardingMethodCard(
                title: "Enter manually",
                description: "Add tickers, share count, and cost basis. Takes about 30 seconds.",
                icon: "plus.circle",
                isRecommended: true,
                action: onAddManually
            )

            OnboardingMethodCard(
                title: "Connect your brokerage",
                description: brokerageAvailable ? "Read-only position sync. Clavix never has trading access." : "Automatic sync from your brokerage. Available in a future update.",
                icon: "link",
                badge: brokerageAvailable ? "PRO" : "COMING SOON",
                badgeFill: brokerageAvailable ? Color.clavixAccentSoft : Color.clavixWarnSoft,
                badgeForeground: brokerageAvailable ? Color.clavixAccentInk : Color.clavixWarnInk,
                action: brokerageAvailable ? onConnectBrokerage : nil
            )

            OnboardingMethodCard(
                title: "Upload CSV",
                description: "Import positions from a spreadsheet export. Available in a future update.",
                icon: "doc.text",
                badge: "COMING SOON",
                badgeFill: Color.clavixWarnSoft,
                badgeForeground: Color.clavixWarnInk,
                action: nil
            )

            if let errorMessage = errorMessage?.sanitizedDisplayText, !errorMessage.isEmpty {
                ClavixCard(fill: .clavixBadSoft) {
                    Text(errorMessage)
                        .font(ClavisTypography.inter(14, weight: .regular))
                        .foregroundColor(.clavixBadInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isCompleting {
                ProgressView()
                    .tint(.clavixInk)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            OnboardingActionButton(
                title: "Continue manually",
                fill: .clavixInk,
                foreground: .clavixPaper,
                isEnabled: !isCompleting,
                action: onAddManually
            )

            Button("Skip for now", action: onSkip)
                .font(ClavisTypography.clavixCaption)
                .foregroundColor(.clavixInk3)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct OnboardingMethodCard: View {
    let title: String
    let description: String
    let icon: String
    var badge: String? = nil
    var badgeFill: Color = .clavixAccentSoft
    var badgeForeground: Color = .clavixAccentInk
    var isRecommended: Bool = false
    var action: (() -> Void)? = nil

    var isEnabled: Bool { action != nil }

    var body: some View {
        let cardContent = ClavixCard(fill: isEnabled ? .clavixPaper : .clavixPaper2) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 28)
                    .foregroundColor(isEnabled ? .clavixAccent : .clavixInk4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(ClavisTypography.inter(15, weight: .semibold))
                            .foregroundColor(isEnabled ? .clavixInk : .clavixInk3)
                        if isRecommended {
                            Text("RECOMMENDED")
                                .font(ClavisTypography.clavixMono(8, weight: .bold))
                                .foregroundColor(.clavixGoodInk)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.clavixGoodSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                        if let badge {
                            Text(badge)
                                .font(ClavisTypography.clavixMono(8, weight: .bold))
                                .foregroundColor(badgeForeground)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(badgeFill)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                    }

                    Text(description)
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(isEnabled ? .clavixInk2 : .clavixInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isEnabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.clavixInk4)
                }
            }
        }

        if let action {
            Button(action: action) { cardContent }
                .buttonStyle(.plain)
        } else {
            cardContent
        }
    }
}

private struct OnboardingActionButton: View {
    let title: String
    let fill: Color
    let foreground: Color
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ClavisTypography.inter(15, weight: .semibold))
                .foregroundColor(isEnabled ? foreground : .clavixInk4)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous))
                .opacity(isEnabled ? 1 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct CSVImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ClavixInlineNoticeCard(
                        eyebrow: "Coming soon",
                        title: "CSV import is not yet available",
                        message: "You will be able to import positions from a spreadsheet export once this feature launches. For now, add positions manually from the Holdings tab.",
                        footnote: "CSV import will be available for all accounts in a future update.",
                        glyph: "doc.text",
                        fill: .clavixWarnSoft,
                        foreground: .clavixWarnInk,
                        secondary: .clavixWarnInk
                    )
                }
                .padding(.horizontal, ClavixLayout.pad)
                .padding(.top, 24)
            }
            .background(Color.clavixPage.ignoresSafeArea())
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(ClavisTypography.clavixMono(11, weight: .semibold))
                        .foregroundColor(.clavixAccent)
                }
            }
        }
    }
}

private struct OnboardingUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ClavixCard(fill: .clavixAccentSoft) {
                        VStack(alignment: .leading, spacing: 10) {
                            ClavixEyebrow("Clavix Pro")
                            Text("Coming soon")
                                .font(ClavisTypography.clavixSerif(26, weight: .medium))
                                .foregroundColor(.clavixInk)
                            Text("Pro will unlock unlimited positions & watchlist, verbose morning briefing, 90-day score history, and advanced alerts.")
                                .font(ClavisTypography.inter(14, weight: .regular))
                                .foregroundColor(.clavixInk2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    OnboardingActionButton(title: "Got it", fill: .clavixInk, foreground: .clavixPaper, action: { dismiss() })
                }
                .padding(.horizontal, ClavixLayout.pad)
                .padding(.top, 24)
                .padding(.bottom, ClavixLayout.bottomPad)
            }
            .background(Color.clavixPage.ignoresSafeArea())
            .navigationTitle("Clavix Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(ClavisTypography.clavixMono(11, weight: .semibold))
                        .foregroundColor(.clavixAccent)
                }
            }
        }
    }
}


// MARK: - Aha onboarding flow (input -> analyzing -> reveal)

private struct OnboardingPortfolioAhaView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let isFreeTier: Bool
    let onBack: () -> Void
    let onFinish: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()
            switch viewModel.ahaPhase {
            case .input:
                AhaInputScreen(viewModel: viewModel, isFreeTier: isFreeTier, onBack: onBack, onSkip: onSkip)
                    .transition(.opacity)
            case .analyzing:
                AhaAnalyzingScreen().transition(.opacity)
            case .reveal:
                AhaRevealScreen(viewModel: viewModel, onFinish: onFinish).transition(.opacity)
            }
        }
    }
}

// MARK: - Shared atoms

private struct AhaHairline: View {
    var color: Color = .border
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

private struct AhaPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(ClavisTypography.inter(15, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(enabled ? .backgroundPrimary : .textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(enabled ? Color.textPrimary : Color.surfaceElevated)
            .overlay(
                Rectangle().stroke(enabled ? Color.clear : Color.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Input ("the ledger")

private struct AhaInputScreen: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let isFreeTier: Bool
    let onBack: () -> Void
    let onSkip: () -> Void

    private var scoredCount: Int { viewModel.resolvedResults.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                Text("BUILD YOUR FIRST SNAPSHOT")
                    .font(ClavisTypography.mono(11))
                    .tracking(0.8)
                    .foregroundColor(.textSecondary)
                    .padding(.bottom, 10)

                Text("Enter 1 to 3 positions.")
                    .font(ClavisTypography.inter(30, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundColor(.textPrimary)
                    .padding(.bottom, 8)

                Text("Clavix will grade the book as you type, then show the weakest link and the biggest blind spot worth watching.")
                    .font(ClavisTypography.inter(15, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 22)

                liveGradeBand
                    .padding(.bottom, 20)

                ledger
                    .padding(.bottom, 24)

                AhaPrimaryButton(title: "Analyze my portfolio", enabled: viewModel.canAnalyze) {
                    viewModel.runAnalysis()
                }
                .padding(.bottom, 14)

                Button("I'll add positions later", action: onSkip)
                    .font(ClavisTypography.inter(13, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 36)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        Text("BACK")
                            .font(ClavisTypography.mono(11))
                            .tracking(0.8)
                            .foregroundColor(.textPrimary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("STEP 04 / 04")
                        .font(ClavisTypography.mono(11))
                        .tracking(0.8)
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                AhaHairline()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea(edges: .top))
        }
    }

    // Live, forming book grade
    private var liveGradeBand: some View {
        HStack(alignment: .top, spacing: 14) {
            // left accent tick
            Rectangle().fill(Color.clavixAccent).frame(width: 3, height: 52)

            VStack(alignment: .leading, spacing: 10) {
                Text("PROVISIONAL BOOK GRADE")
                    .font(ClavisTypography.mono(10))
                    .tracking(0.7)
                    .foregroundColor(.textSecondary)

                if let grade = viewModel.liveGrade, let score = viewModel.liveScore {
                    HStack(spacing: 12) {
                        ClavixGradeBadge(grade, size: 40)
                            .id(grade)
                            .transition(.scale.combined(with: .opacity))
                        Text("composite \(Int(score.rounded()))")
                            .font(ClavisTypography.mono(13))
                            .foregroundColor(Color.white.opacity(0.72))
                    }
                } else {
                    HStack(spacing: 12) {
                        Text("—")
                            .font(ClavisTypography.mono(22))
                            .foregroundColor(.textTertiary)
                            .frame(width: 40, height: 40)
                            .overlay(Rectangle().stroke(Color.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        Text("Add a ticker to start your first read")
                            .font(ClavisTypography.inter(13, weight: .regular))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            Spacer(minLength: 8)

            Text("\(scoredCount) / \(viewModel.entries.count)")
                .font(ClavisTypography.mono(11))
                .foregroundColor(.textSecondary)
        }
        .padding(14)
        .background(Color.surface)
        .overlay(Rectangle().stroke(Color.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .animation(.easeInOut(duration: 0.3), value: viewModel.liveGrade)
    }

    // Numbered trade-ticket ledger
    private var ledger: some View {
        VStack(spacing: 0) {
            // column header
            HStack(spacing: 8) {
                Text("#").font(ClavisTypography.mono(10)).foregroundColor(.textTertiary).frame(width: 18, alignment: .leading)
                Text("TICKER").font(ClavisTypography.mono(10)).tracking(0.6).foregroundColor(.textSecondary)
                Spacer()
                Text("SHARES").font(ClavisTypography.mono(10)).tracking(0.6).foregroundColor(.textSecondary).frame(width: 76, alignment: .leading)
                Text("GRADE").font(ClavisTypography.mono(10)).tracking(0.6).foregroundColor(.textSecondary).frame(width: 40, alignment: .center)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.surfaceElevated)
            AhaHairline()

            ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { idx, entry in
                AhaLedgerRow(viewModel: viewModel, entry: entry, index: idx + 1)
                if idx < viewModel.entries.count - 1 {
                    AhaHairline()
                }
            }

            AhaHairline()
            if viewModel.entries.count < viewModel.maxEntries(isFreeTier: isFreeTier) {
                Button {
                    viewModel.addEntry(isFreeTier: isFreeTier)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        Text("ADD POSITION").font(ClavisTypography.mono(10)).tracking(0.6)
                    }
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
            } else if isFreeTier {
                Text("FREE COVERS 3 POSITIONS · PRO UNLOCKS YOUR BOOK")
                    .font(ClavisTypography.mono(10))
                    .tracking(0.5)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
        }
        .background(Color.surface)
        .overlay(Rectangle().stroke(Color.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct AhaLedgerRow: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let entry: AhaPortfolioEntry
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(String(format: "%02d", index))
                    .font(ClavisTypography.mono(11))
                    .foregroundColor(.textTertiary)
                    .frame(width: 18, alignment: .leading)

                TextField("AAPL", text: Binding(
                    get: { entry.query },
                    set: { viewModel.updateQuery(entry.id, $0) }
                ))
                .font(ClavisTypography.mono(15))
                .foregroundColor(.textPrimary)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .frame(maxWidth: .infinity, alignment: .leading)

                TextField("—", text: Binding(
                    get: { entry.shares },
                    set: { viewModel.updateShares(entry.id, $0) }
                ))
                .font(ClavisTypography.mono(13))
                .foregroundColor(Color.white.opacity(0.72))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .frame(width: 76, alignment: .leading)

                Group {
                    if entry.isResolving {
                        ProgressView().tint(.textSecondary).scaleEffect(0.8)
                    } else if let resolved = entry.resolved, let grade = resolved.resolvedGrade {
                        ClavixGradeBadge(grade, size: 32)
                    } else {
                        Text("—").font(ClavisTypography.mono(13)).foregroundColor(.textTertiary)
                    }
                }
                .frame(width: 40, height: 32)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            if let resolved = entry.resolved {
                Text((resolved.resolvedCompanyName ?? resolved.ticker).uppercased())
                    .font(ClavisTypography.mono(9))
                    .tracking(0.4)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, 40)
                    .padding(.bottom, 11)
                    .padding(.trailing, 14)
            } else if entry.notFound {
                Text("NO MATCH FOUND")
                    .font(ClavisTypography.mono(9))
                    .tracking(0.4)
                    .foregroundColor(.warn)
                    .padding(.leading, 40)
                    .padding(.bottom, 11)
            }
        }
    }
}

// MARK: - Analyzing

private struct AhaAnalyzingScreen: View {
    @State private var index = 0
    @State private var timer: Timer?

    private let dimensions: [(code: String, name: String)] = [
        ("FIN", "Financial Health"),
        ("NEWS", "News Sentiment"),
        ("MAC", "Macro Exposure"),
        ("SEC", "Sector Exposure"),
        ("VOL", "Volatility"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 30) {
                HStack(spacing: 8) {
                    Image("clavix_logo").renderingMode(.template).resizable().scaledToFit().foregroundColor(.textPrimary).frame(width: 20, height: 20)
                    Text("CLAVIX").font(ClavisTypography.mono(11)).tracking(1.6).foregroundColor(.textPrimary)
                }

                VStack(spacing: 8) {
                    Text("Scoring your positions")
                        .font(ClavisTypography.inter(30, weight: .semibold))
                        .tracking(-0.6)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("ACROSS FIVE RISK DIMENSIONS")
                        .font(ClavisTypography.mono(10))
                        .tracking(0.8)
                        .foregroundColor(.textSecondary)
                }

                VStack(spacing: 14) {
                    HStack(spacing: 6) {
                        ForEach(0..<dimensions.count, id: \.self) { i in
                            Text(dimensions[i].code)
                                .font(ClavisTypography.mono(9))
                                .tracking(0.4)
                                .foregroundColor(i == index ? .backgroundPrimary : .textSecondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(i == index ? Color.textPrimary : Color.clear)
                                .overlay(Rectangle().stroke(i == index ? Color.clear : Color.border, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(dimensions[index].name)
                        .font(ClavisTypography.inter(13, weight: .regular))
                        .foregroundColor(.textSecondary)
                        .frame(height: 18)
                        .id(index)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.22), value: index)
                }
            }
            Spacer()
            Text("READING THE MARKET ON YOUR BEHALF")
                .font(ClavisTypography.mono(9))
                .tracking(0.7)
                .foregroundColor(.textTertiary)
                .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity)
        .onAppear { start() }
        .onDisappear { timer?.invalidate() }
    }

    private func start() {
        var tick = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            tick += 1
            withAnimation(.easeInOut(duration: 0.22)) { index = tick % dimensions.count }
        }
    }
}

// MARK: - Reveal ("the risk dossier")

private struct AhaRevealScreen: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let onFinish: () -> Void

    var body: some View {
        if let reveal = viewModel.reveal {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Masthead
                    HStack {
                        Text("CLAVIX").font(ClavisTypography.mono(11)).tracking(1.6).foregroundColor(.textPrimary)
                        Spacer()
                        Text("RISK SNAPSHOT").font(ClavisTypography.mono(10)).tracking(0.9).foregroundColor(.textSecondary)
                    }
                    .padding(.bottom, 10)
                    Rectangle().fill(Color.textPrimary).frame(height: 2)
                        .padding(.bottom, 22)

                    // Hero grade
                    HStack(alignment: .center, spacing: 16) {
                        ClavixGradeBadge(reveal.grade, size: 68)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Your portfolio grades \(reveal.grade).")
                                .font(ClavisTypography.inter(28, weight: .semibold))
                                .tracking(-0.6)
                                .foregroundColor(.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(reveal.positionCount) POSITION\(reveal.positionCount == 1 ? "" : "S") · COMPOSITE \(Int(reveal.score.rounded()))")
                                .font(ClavisTypography.mono(10))
                                .tracking(0.6)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 24)

                    // Lead finding: the blind spot
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 12) {
                            Rectangle().fill(Color.clavixWarn).frame(width: 3)
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("BIGGEST BLIND SPOT")
                                        .font(ClavisTypography.mono(9)).tracking(0.8).foregroundColor(.warn)
                                    Spacer()
                                    Text("AVG \(Int(reveal.blindSpot.average.rounded()))")
                                        .font(ClavisTypography.mono(10)).foregroundColor(.warn)
                                }
                                Text(reveal.blindSpot.name)
                                    .font(ClavisTypography.inter(26, weight: .semibold))
                                    .tracking(-0.5)
                                    .foregroundColor(.textPrimary)
                                Text(blindSpotSentence(reveal))
                                    .font(ClavisTypography.inter(14, weight: .regular))
                                    .foregroundColor(Color.white.opacity(0.72))
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 16)
                            .padding(.trailing, 16)
                        }
                    }
                    .background(Color.warnSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(.bottom, 22)

                    // Position ledger
                    Text("POSITION LEDGER")
                        .font(ClavisTypography.mono(9)).tracking(0.8).foregroundColor(.textSecondary)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        if let t = reveal.weakestTicker, let g = reveal.weakestGrade {
                            AhaLedgerStatRow(label: "WEAKEST LINK", ticker: t, grade: g, note: "Drags your composite the most")
                        }
                        if let t = reveal.strongestTicker, let g = reveal.strongestGrade {
                            AhaHairline()
                            AhaLedgerStatRow(label: "YOUR ANCHOR", ticker: t, grade: g, note: "Steadiest name in the book")
                        }
                    }
                    .background(Color.surface)
                    .overlay(Rectangle().stroke(Color.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(.bottom, 14)

                    // Locked teaser
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold)).foregroundColor(.textPrimary)
                        Text("The full five-dimension breakdown is ready for your book. Start your 14-day trial to unlock each position, trend history, and morning monitoring.")
                            .font(ClavisTypography.inter(13, weight: .regular)).foregroundColor(Color.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(.bottom, 26)

                    AhaPrimaryButton(title: "Unlock my full breakdown", enabled: !viewModel.isCompleting, action: onFinish)

                    Text("Next, start your 14-day trial and walk into the app with this snapshot fully unlocked.")
                        .font(ClavisTypography.inter(12, weight: .regular))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 10)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(ClavisTypography.clavixCaption).foregroundColor(.bad)
                            .frame(maxWidth: .infinity, alignment: .center).padding(.top, 10)
                    }

                    Text("INFORMATIONAL ONLY · NOT INVESTMENT ADVICE")
                        .font(ClavisTypography.mono(8)).tracking(0.6).foregroundColor(.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 18).padding(.bottom, 36)
                }
                .padding(.horizontal, 22)
                .padding(.top, 28)
            }
        } else {
            ProgressView().tint(.textPrimary)
        }
    }

    private func blindSpotSentence(_ reveal: AhaReveal) -> String {
        let dim = reveal.blindSpot
        let nameLower = dim.name.lowercased()
        if dim.weakCount > 0 {
            let coverage = dim.weakCount == dim.total
                ? "Every scored holding"
                : "\(dim.weakCount) of \(dim.total) scored holdings"
            return "\(dim.name) is your softest signal. It tracks \(dim.explanation), and \(coverage.prefix(1).lowercased() + coverage.dropFirst()) lands in caution territory here."
        } else {
            return "\(dim.name) is the lowest-scoring dimension across your book. It tracks \(dim.explanation), so it is your relative soft spot even though no single name is critical."
        }
    }
}

private struct AhaLedgerStatRow: View {
    let label: String
    let ticker: String
    let grade: String
    let note: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(ClavisTypography.mono(9)).tracking(0.6).foregroundColor(.textSecondary)
                HStack(spacing: 8) {
                    Text(ticker)
                        .font(ClavisTypography.mono(16)).foregroundColor(.textPrimary)
                    Text(note)
                        .font(ClavisTypography.inter(12, weight: .regular)).foregroundColor(.textSecondary)
                }
            }
            Spacer(minLength: 0)
            ClavixGradeBadge(grade, size: 34)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}
