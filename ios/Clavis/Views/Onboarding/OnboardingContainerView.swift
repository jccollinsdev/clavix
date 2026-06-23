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
                    OnboardingWelcomeSetupView(
                        viewModel: viewModel,
                        isFreeTier: !SubscriptionManager.shared.isPro,
                        onPrimary: {
                            Task {
                                if await viewModel.continueToAnalysis() {
                                    viewModel.nextPage()
                                }
                            }
                        }
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
        .task {
            await viewModel.loadWelcomeName()
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

private struct OnboardingWelcomeSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let isFreeTier: Bool
    let onPrimary: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 18)

                    Text(title)
                        .font(ClavisTypography.inter(34, weight: .semibold))
                        .tracking(-0.6)
                        .foregroundColor(.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 10)

                    Text("Enter at least one holding and the shares you own. You can add more positions below.")
                        .font(ClavisTypography.inter(15, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.76))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 18)

                    OnboardingHoldingsEntry(
                        viewModel: viewModel,
                        isFreeTier: isFreeTier
                    )

                    if let errorMessage = viewModel.errorMessage?.sanitizedDisplayText,
                       !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(ClavisTypography.inter(13, weight: .medium))
                            .foregroundColor(.warn)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                    }

                    Spacer(minLength: 18)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            OnboardingStickyBar(step: 1, total: 2)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Rectangle().fill(Color.border).frame(height: 1)
                Button(action: onPrimary) {
                    HStack(spacing: 12) {
                        Text("Next")
                            .font(ClavisTypography.inter(15, weight: .semibold))
                        Spacer()
                        if viewModel.isPreparingAnalysis {
                            ProgressView()
                                .tint(.backgroundPrimary)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundColor(.backgroundPrimary)
                    .padding(.horizontal, 18)
                    .frame(width: 132, height: 52)
                    .background(Color.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isPreparingAnalysis)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea(edges: .bottom))
        }
    }

    private var title: String {
        guard let name = viewModel.welcomeName, !name.isEmpty else {
            return "Let’s set up your portfolio."
        }
        return "Hey \(name),\nlet’s set up your portfolio."
    }
}

private struct OnboardingHoldingsEntry: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let isFreeTier: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("YOUR HOLDINGS")
                    .font(ClavisTypography.mono(9))
                    .tracking(0.7)
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("SHARES")
                    .font(ClavisTypography.mono(9))
                    .tracking(0.7)
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            AhaHairline()

            ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                WelcomeHoldingRow(
                    viewModel: viewModel,
                    entry: entry,
                    index: index + 1
                )
                if index < viewModel.entries.count - 1 {
                    AhaHairline()
                }
            }

            if viewModel.entries.count < viewModel.maxEntries(isFreeTier: isFreeTier) {
                AhaHairline()
                Button {
                    viewModel.addEntry(isFreeTier: isFreeTier)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Add position")
                            .font(ClavisTypography.inter(14, weight: .medium))
                    }
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
    }
}

private struct WelcomeHoldingRow: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let entry: AhaPortfolioEntry
    let index: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d", index))
                .font(ClavisTypography.mono(10))
                .foregroundColor(.textTertiary)
                .frame(width: 20, alignment: .leading)

            TextField("Ticker", text: Binding(
                get: { entry.query },
                set: { viewModel.updateQuery(entry.id, $0) }
            ))
            .font(ClavisTypography.mono(15))
            .foregroundColor(.textPrimary)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)

            Group {
                if entry.isResolving {
                    ProgressView()
                        .tint(.textSecondary)
                        .scaleEffect(0.72)
                } else if entry.resolved != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                } else if entry.notFound {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.warn)
                }
            }
            .frame(width: 18)

            TextField("0", text: Binding(
                get: { entry.shares },
                set: { viewModel.updateShares(entry.id, $0) }
            ))
            .font(ClavisTypography.mono(15))
            .foregroundColor(.textPrimary)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 78)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
    }
}

private struct OnboardingStickyBar: View {
    let step: Int
    let total: Int

    var body: some View {
        ClavixAuthStickyBar()
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(Color.textPrimary)
                    .frame(width: proxy.size.width * CGFloat(step) / CGFloat(max(total, 1)))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 1)
        }
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
                Text("What do you own?")
                    .font(ClavisTypography.inter(29, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundColor(.textPrimary)
                    .padding(.bottom, 8)

                Text("Start with one ticker and share count. Add more if you want a fuller portfolio read.")
                    .font(ClavisTypography.inter(15, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)

                liveGradeBand
                    .padding(.bottom, 16)

                ledger
                    .padding(.bottom, 16)

                Button("I'll add positions later", action: onSkip)
                    .font(ClavisTypography.inter(13, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            OnboardingStickyBar(step: 2, total: 2)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                AhaHairline()
                AhaPrimaryButton(title: "Grade my portfolio", enabled: viewModel.canAnalyze) {
                    viewModel.runAnalysis()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea(edges: .bottom))
        }
    }

    // Live, forming book grade
    private var liveGradeBand: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LIVE PORTFOLIO GRADE")
                    .font(ClavisTypography.mono(10))
                    .tracking(0.7)
                    .foregroundColor(.textSecondary)

                if let grade = viewModel.liveGrade, let score = viewModel.liveScore {
                    HStack(spacing: 12) {
                        ClavixGradeBadge(grade, size: 36)
                            .id(grade)
                            .transition(.scale.combined(with: .opacity))
                        Text("Composite \(Int(score.rounded()))")
                            .font(ClavisTypography.mono(13))
                            .foregroundColor(Color.white.opacity(0.72))
                    }
                } else {
                    Text("Add a ticker to begin")
                        .font(ClavisTypography.inter(14, weight: .medium))
                        .foregroundColor(.textPrimary)
                }
            }
            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(scoredCount)")
                    .font(ClavisTypography.inter(22, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("SCORED")
                    .font(ClavisTypography.mono(9))
                    .tracking(0.6)
                    .foregroundColor(.textSecondary)
            }
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

    private let checks: [(code: String, title: String, detail: String, icon: String)] = [
        ("NEWS", "Reading market news", "Scanning recent coverage for sentiment shifts.", "newspaper"),
        ("FIN", "Checking fundamentals", "Looking at balance sheet and profitability signals.", "chart.bar.xaxis"),
        ("MAC", "Mapping macro exposure", "Testing sensitivity to rates and broad market stress.", "globe.americas"),
        ("SEC", "Finding sector concentration", "Measuring where your book is most crowded.", "square.grid.2x2"),
        ("VOL", "Building risk radar", "Combining volatility and dimension scores.", "scope"),
    ]

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 18)

                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Text("Building your risk snapshot")
                            .font(ClavisTypography.inter(28, weight: .semibold))
                            .tracking(-0.55)
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                        Text("CHECKING LIVE SIGNALS")
                            .font(ClavisTypography.mono(10))
                            .tracking(0.8)
                            .foregroundColor(.textSecondary)
                    }

                    analysisCore

                    VStack(spacing: 8) {
                        Text(checks[index].title)
                            .font(ClavisTypography.inter(16, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .id("title-\(index)")
                            .transition(.opacity)
                        Text(checks[index].detail)
                            .font(ClavisTypography.inter(13, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: 280)
                            .id("detail-\(index)")
                            .transition(.opacity)
                    }
                    .animation(.easeInOut(duration: 0.22), value: index)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 18)

                VStack(spacing: 10) {
                    segmentedProgress
                    Text("NO RECOMMENDATIONS · INFORMATIONAL RISK RATING")
                        .font(ClavisTypography.mono(8))
                        .tracking(0.6)
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 44)
                .padding(.bottom, max(36, proxy.safeAreaInsets.bottom + 24))
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            OnboardingStickyBar(step: 2, total: 2)
        }
        .onAppear { start() }
        .onDisappear { timer?.invalidate() }
    }

    private var analysisCore: some View {
        ZStack {
            ForEach(0..<checks.count, id: \.self) { i in
                checkNode(i)
            }

            progressDial
        }
        .frame(width: 230, height: 230)
    }

    private func checkNode(_ i: Int) -> some View {
        let check = checks[i]
        let active = i == index
        let point = orbitPoint(i)
        return VStack(spacing: 5) {
            Image(systemName: check.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textPrimary)
                .frame(width: 34, height: 34)
                .background(active ? Color.textPrimary.opacity(0.16) : Color.surface)
                .overlay(Rectangle().stroke(active ? Color.textPrimary : Color.border, lineWidth: 1))
            Text(check.code)
                .font(ClavisTypography.mono(10))
                .tracking(0.5)
                .foregroundColor(active ? .textPrimary : .textTertiary)
        }
        .offset(x: point.x, y: point.y)
        .opacity(active ? 1 : 0.48)
        .animation(.easeInOut(duration: 0.24), value: index)
    }

    private var progressDial: some View {
        ZStack {
            Circle()
                .stroke(Color.border, lineWidth: 1)
                .frame(width: 88, height: 88)
            Circle()
                .trim(from: 0, to: CGFloat(index + 1) / CGFloat(checks.count))
                .stroke(Color.textPrimary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 88, height: 88)
            VStack(spacing: 2) {
                Text("\(index + 1)")
                    .font(ClavisTypography.mono(24))
                    .foregroundColor(.textPrimary)
                Text("OF \(checks.count)")
                    .font(ClavisTypography.mono(8))
                    .tracking(0.6)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    private func orbitPoint(_ i: Int) -> CGPoint {
        let angle = (Double(i) / Double(checks.count) * 2 * .pi) - .pi / 2
        let radius: CGFloat = 78
        return CGPoint(
            x: CGFloat(cos(angle)) * radius,
            y: CGFloat(sin(angle)) * radius
        )
    }

    private var segmentedProgress: some View {
        HStack(spacing: 6) {
            ForEach(0..<checks.count, id: \.self) { i in
                Rectangle()
                    .fill(i <= index ? Color.textPrimary : Color.border)
                    .frame(height: 2)
                    .animation(.easeInOut(duration: 0.2), value: index)
            }
        }
    }

    private func start() {
        var tick = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
            tick += 1
            withAnimation(.easeInOut(duration: 0.24)) {
                index = tick % checks.count
            }
        }
    }
}

// MARK: - Reveal ("the risk dossier")

private struct AhaRevealScreen: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let onFinish: () -> Void

    var body: some View {
        if let reveal = viewModel.reveal {
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 14) {
                    Text("YOUR RISK SNAPSHOT")
                        .font(ClavisTypography.mono(10))
                        .tracking(0.9)
                        .foregroundColor(.textSecondary)

                    HStack(alignment: .center, spacing: 14) {
                        ClavixGradeBadge(reveal.grade, size: 68)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Portfolio grade \(reveal.grade)")
                                .font(ClavisTypography.inter(25, weight: .semibold))
                                .tracking(-0.45)
                                .foregroundColor(.textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.86)
                            Text("\(reveal.positionCount) POSITION\(reveal.positionCount == 1 ? "" : "S") · SCORE \(Int(reveal.score.rounded()))")
                                .font(ClavisTypography.mono(10))
                                .tracking(0.6)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("BIGGEST BLIND SPOT")
                                .font(ClavisTypography.mono(9))
                                .tracking(0.8)
                                .foregroundColor(.warn)
                            Spacer()
                            Text("AVG \(Int(reveal.blindSpot.average.rounded()))")
                                .font(ClavisTypography.mono(10))
                                .foregroundColor(.warn)
                        }
                        Text(reveal.blindSpot.name)
                            .font(ClavisTypography.inter(23, weight: .semibold))
                            .tracking(-0.35)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)
                        Text(blindSpotSentence(reveal))
                            .font(ClavisTypography.inter(13, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.76))
                            .lineLimit(2)
                            .lineSpacing(1)
                    }
                    .padding(14)
                    .background(Color.warnSoft)
                    .overlay(Rectangle().stroke(Color.warn.opacity(0.35), lineWidth: 1))

                    LockedPortfolioRadar(reveal: reveal)
                        .frame(height: min(210, max(176, proxy.size.height * 0.26)))

                    AhaPrimaryButton(title: "Start trial to unlock", enabled: !viewModel.isCompleting, action: onFinish)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(ClavisTypography.clavixCaption)
                            .foregroundColor(.bad)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Text("14 DAYS FREE · INFORMATIONAL ONLY")
                        .font(ClavisTypography.mono(8))
                        .tracking(0.6)
                        .foregroundColor(.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 18)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                OnboardingStickyBar(step: 2, total: 2)
            }
        } else {
            ProgressView().tint(.textPrimary)
        }
    }

    private func blindSpotSentence(_ reveal: AhaReveal) -> String {
        let dim = reveal.blindSpot
        if dim.weakCount > 0 {
            return "\(dim.weakCount) of \(dim.total) holdings need a closer read here."
        } else {
            return "Your lowest dimension. The trial opens the stock-by-stock breakdown."
        }
    }
}

private struct LockedPortfolioRadar: View {
    let reveal: AhaReveal

    private var dimensions: [AhaDimensionFinding] {
        let fallback = [reveal.blindSpot]
        return reveal.dimensions.isEmpty ? fallback : reveal.dimensions
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RadarShape(values: dimensions.map(\.average))
                    .blur(radius: 3.2)
                    .opacity(0.86)
                Circle()
                    .fill(Color.backgroundPrimary.opacity(0.82))
                    .frame(width: 54, height: 54)
                    .overlay(
                        Image(systemName: "lock.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.textPrimary)
                    )
            }
            .frame(width: 132, height: 132)

            VStack(alignment: .leading, spacing: 8) {
                Text("PORTFOLIO RADAR LOCKED")
                    .font(ClavisTypography.mono(9))
                    .tracking(0.8)
                    .foregroundColor(.textSecondary)
                Text("See every stock across all five risk dimensions.")
                    .font(ClavisTypography.inter(17, weight: .semibold))
                    .tracking(-0.15)
                    .foregroundColor(.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let ticker = reveal.weakestTicker, let grade = reveal.weakestGrade {
                        Text("\(ticker) \(grade)")
                            .font(ClavisTypography.mono(10))
                            .foregroundColor(.warn)
                    }
                    Text("14-day trial")
                        .font(ClavisTypography.mono(10))
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .overlay(Rectangle().stroke(Color.border, lineWidth: 1))
    }
}

private struct RadarShape: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let count = max(values.count, 3)
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = side * 0.42

            ZStack {
                ForEach(1...3, id: \.self) { ring in
                    radarPolygon(count: count, center: center, radius: radius * CGFloat(ring) / 3)
                        .stroke(Color.border.opacity(0.8), lineWidth: 1)
                }
                ForEach(0..<count, id: \.self) { index in
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: point(index: index, count: count, center: center, radius: radius))
                    }
                    .stroke(Color.border.opacity(0.55), lineWidth: 1)
                }
                radarPolygon(values: normalizedValues(count: count), center: center, radius: radius)
                    .fill(Color.good.opacity(0.22))
                radarPolygon(values: normalizedValues(count: count), center: center, radius: radius)
                    .stroke(Color.good, lineWidth: 2)
            }
        }
    }

    private func normalizedValues(count: Int) -> [Double] {
        guard !values.isEmpty else { return Array(repeating: 0.56, count: count) }
        return (0..<count).map { index in
            let raw = values[index % values.count]
            return min(1, max(0.18, raw / 100))
        }
    }

    private func radarPolygon(count: Int, center: CGPoint, radius: CGFloat) -> Path {
        radarPolygon(values: Array(repeating: 1, count: count), center: center, radius: radius)
    }

    private func radarPolygon(values: [Double], center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for index in values.indices {
            let point = point(
                index: index,
                count: values.count,
                center: center,
                radius: radius * CGFloat(values[index])
            )
            if index == values.startIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
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
