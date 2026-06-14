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
            Color.clavixPage.ignoresSafeArea()

            Group {
                switch viewModel.currentPage {
                case .welcome:
                    OnboardingWelcomeView(
                        onContinue: { viewModel.nextPage() },
                        onSignIn: { Task { await authViewModel.signOut() } }
                    )
                case .addPortfolio:
                    OnboardingPortfolioAhaView(
                        viewModel: viewModel,
                        isFreeTier: authViewModel.subscriptionTier.lowercased() == "free",
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
            if authViewModel.subscriptionTier.lowercased() == "free" {
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
        .preferredColorScheme(.light)
    }

    private func handleConnectBrokerage() {
        if authViewModel.subscriptionTier.lowercased() == "free" {
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
            UserDefaults.standard.set(1, forKey: "clavix.selectedTab")
            NotificationCenter.default.post(name: .openAddHoldingFromOnboarding, object: nil)
        }
    }

    /// Called from the aha reveal CTA. Positions were already created during the
    /// analyzing phase, so route straight to the populated Holdings tab without
    /// re-opening the add sheet.
    private func completeAfterAha() {
        viewModel.completeOnboarding {
            authViewModel.markOnboardingComplete()
            UserDefaults.standard.set(1, forKey: "clavix.selectedTab")
        }
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
                    .resizable()
                    .scaledToFit()
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
            Color.clavixPage.ignoresSafeArea()
            switch viewModel.ahaPhase {
            case .input:
                AhaInputScreen(
                    viewModel: viewModel,
                    isFreeTier: isFreeTier,
                    onBack: onBack,
                    onSkip: onSkip
                )
                .transition(.opacity)
            case .analyzing:
                AhaAnalyzingScreen()
                    .transition(.opacity)
            case .reveal:
                AhaRevealScreen(viewModel: viewModel, onFinish: onFinish)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: Input

private struct AhaInputScreen: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let isFreeTier: Bool
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Header row: title + live grade
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add your positions")
                            .font(ClavisTypography.clavixSerif(30, weight: .medium))
                            .foregroundColor(.clavixInk)
                        Text("Watch your portfolio grade form as you go. Clavix scores everything you own across five risk dimensions.")
                            .font(ClavisTypography.inter(14, weight: .regular))
                            .foregroundColor(.clavixInk2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    liveGradeBadge
                }
                .padding(.bottom, 28)

                // Column labels
                HStack(spacing: 10) {
                    Text("TICKER")
                        .font(ClavisTypography.clavixMono(9, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.clavixInk3)
                        .frame(width: 96, alignment: .center)
                    Text("SHARES (OPTIONAL)")
                        .font(ClavisTypography.clavixMono(9, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.clavixInk3)
                        .padding(.leading, 12)
                    Spacer()
                }
                .padding(.bottom, 8)

                // Entry rows
                VStack(spacing: 10) {
                    ForEach(viewModel.entries) { entry in
                        AhaEntryRow(viewModel: viewModel, entry: entry)
                    }
                }
                .padding(.bottom, 12)

                // Add another
                if viewModel.entries.count < viewModel.maxEntries(isFreeTier: isFreeTier) {
                    Button {
                        viewModel.addEntry(isFreeTier: isFreeTier)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                            Text("Add another position")
                                .font(ClavisTypography.inter(13, weight: .regular))
                        }
                        .foregroundColor(.clavixInk3)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                } else if isFreeTier {
                    Text("Free covers your first 3 positions. Pro unlocks your whole book.")
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixInk3)
                        .padding(.vertical, 8)
                }

                Spacer().frame(height: 28)

                // CTA
                OnboardingActionButton(
                    title: "Analyze my portfolio",
                    fill: .clavixInk,
                    foreground: .clavixPaper,
                    isEnabled: viewModel.canAnalyze,
                    action: { viewModel.runAnalysis() }
                )
                .padding(.bottom, 12)

                Button("I'll add positions later", action: onSkip)
                    .font(ClavisTypography.inter(13, weight: .regular))
                    .foregroundColor(.clavixInk3)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button("Back", action: onBack)
                    .font(ClavisTypography.clavixMono(10, weight: .semibold))
                    .foregroundColor(.clavixAccent)
                    .buttonStyle(.plain)
                Spacer()
                Text("STEP 2 OF 2")
                    .font(ClavisTypography.clavixMono(9, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.clavixInk3)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.clavixPage.ignoresSafeArea(edges: .top))
        }
    }

    private var liveGradeBadge: some View {
        VStack(spacing: 4) {
            if let grade = viewModel.liveGrade {
                ClavixGradeBadge(grade, size: 40)
                    .transition(.scale.combined(with: .opacity))
                    .id(grade)
            } else {
                Text("—")
                    .font(ClavisTypography.clavixMono(22, weight: .semibold))
                    .foregroundColor(.clavixInk4)
                    .frame(width: 40, height: 40)
                    .background(Color.clavixPaper2)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text("BOOK")
                .font(ClavisTypography.clavixMono(8, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.clavixInk3)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.liveGrade)
    }
}

private struct AhaEntryRow: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let entry: AhaPortfolioEntry

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("AAPL", text: Binding(
                    get: { entry.query },
                    set: { viewModel.updateQuery(entry.id, $0) }
                ))
                .font(ClavisTypography.clavixMono(14, weight: .bold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .multilineTextAlignment(.center)
                .frame(width: 96, height: 50)
                .background(Color.clavixPaper2)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                TextField("Shares", text: Binding(
                    get: { entry.shares },
                    set: { viewModel.updateShares(entry.id, $0) }
                ))
                .font(ClavisTypography.inter(14, weight: .regular))
                .keyboardType(.decimalPad)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .padding(.horizontal, 12)
                .background(Color.clavixPaper2)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.clavixRule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Status: resolved grade / spinner / placeholder
                Group {
                    if entry.isResolving {
                        ProgressView()
                            .tint(.clavixInk3)
                    } else if let resolved = entry.resolved, let grade = resolved.resolvedGrade {
                        ClavixGradeBadge(grade, size: 34)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 38, height: 38)
            }

            // Resolved company name or not-found hint
            if let resolved = entry.resolved {
                HStack {
                    Text(resolved.resolvedCompanyName ?? resolved.ticker)
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixInk3)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.top, 4)
                .padding(.leading, 4)
            } else if entry.notFound {
                HStack {
                    Text("No match found")
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixWarnInk)
                    Spacer()
                }
                .padding(.top, 4)
                .padding(.leading, 4)
            }
        }
    }

    private var borderColor: Color {
        if entry.resolved != nil { return .clavixGoodInk.opacity(0.5) }
        if entry.notFound { return .clavixWarnInk.opacity(0.5) }
        return .clavixRule
    }
}

// MARK: Analyzing

private struct AhaAnalyzingScreen: View {
    @State private var index = 0
    @State private var timer: Timer?

    private let dimensions: [(code: String, name: String)] = [
        ("FIN",  "Financial Health"),
        ("NEWS", "News Sentiment"),
        ("MAC",  "Macro Exposure"),
        ("SEC",  "Sector Exposure"),
        ("VOL",  "Volatility"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                HStack(spacing: 8) {
                    Image("clavix_logo")
                        .resizable().scaledToFit()
                        .frame(width: 22, height: 22)
                    Text("CLAVIX")
                        .font(ClavisTypography.clavixMono(12, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(.clavixInk)
                }

                VStack(spacing: 6) {
                    Text("Scoring your positions")
                        .font(ClavisTypography.clavixSerif(28, weight: .medium))
                        .foregroundColor(.clavixInk)
                        .multilineTextAlignment(.center)
                    Text("across five risk dimensions")
                        .font(ClavisTypography.inter(15, weight: .regular))
                        .foregroundColor(.clavixInk2)
                }

                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        ForEach(0..<dimensions.count, id: \.self) { i in
                            Text(dimensions[i].code)
                                .font(ClavisTypography.clavixMono(9, weight: .bold))
                                .tracking(0.4)
                                .foregroundColor(i == index ? .clavixPaper : .clavixInk3)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(i == index ? Color.clavixInk : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(i == index ? Color.clear : Color.clavixRule, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(dimensions[index].name)
                        .font(ClavisTypography.inter(13, weight: .regular))
                        .foregroundColor(.clavixInk3)
                        .frame(height: 18)
                        .id(index)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.22), value: index)
                }
            }
            Spacer()
            Text("Reading the market on your behalf.")
                .font(ClavisTypography.inter(12, weight: .regular))
                .foregroundColor(.clavixInk4)
                .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity)
        .onAppear { start() }
        .onDisappear { timer?.invalidate() }
    }

    private func start() {
        var tick = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { t in
            tick += 1
            withAnimation(.easeInOut(duration: 0.22)) {
                index = tick % dimensions.count
            }
        }
    }
}

// MARK: Reveal

private struct AhaRevealScreen: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let onFinish: () -> Void

    var body: some View {
        if let reveal = viewModel.reveal {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    Text("YOUR RISK SNAPSHOT")
                        .font(ClavisTypography.clavixMono(10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(.clavixInk3)
                        .padding(.bottom, 16)

                    // Grade headline
                    HStack(spacing: 16) {
                        ClavixGradeBadge(reveal.grade, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your book grades \(reveal.grade)")
                                .font(ClavisTypography.clavixSerif(24, weight: .medium))
                                .foregroundColor(.clavixInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(reveal.positionCount) position\(reveal.positionCount == 1 ? "" : "s") - composite \(Int(reveal.score.rounded()))")
                                .font(ClavisTypography.inter(13, weight: .regular))
                                .foregroundColor(.clavixInk3)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 24)

                    // Hero finding: biggest blind spot
                    ClavixCard(fill: .clavixWarnSoft) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text("BIGGEST BLIND SPOT")
                                    .font(ClavisTypography.clavixMono(9, weight: .bold))
                                    .tracking(0.6)
                                    .foregroundColor(.clavixWarnInk)
                                Spacer()
                                Text("AVG \(Int(reveal.blindSpot.average.rounded()))")
                                    .font(ClavisTypography.clavixMono(9, weight: .bold))
                                    .foregroundColor(.clavixWarnInk)
                            }
                            Text(reveal.blindSpot.name)
                                .font(ClavisTypography.clavixSerif(22, weight: .medium))
                                .foregroundColor(.clavixInk)
                            Text(blindSpotSentence(reveal))
                                .font(ClavisTypography.inter(14, weight: .regular))
                                .foregroundColor(.clavixInk2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.bottom, 12)

                    // Supporting findings
                    if let weak = reveal.weakestTicker, let wg = reveal.weakestGrade {
                        AhaFindingRow(
                            label: "Weakest link",
                            ticker: weak,
                            grade: wg,
                            note: "Drags your composite the most."
                        )
                    }
                    if let strong = reveal.strongestTicker, let sg = reveal.strongestGrade {
                        AhaFindingRow(
                            label: "Your anchor",
                            ticker: strong,
                            grade: sg,
                            note: "Your steadiest position."
                        )
                    }

                    // Locked teaser
                    ClavixCard(fill: .clavixPaper2) {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.clavixInk3)
                            Text("See the full five-dimension breakdown for every position.")
                                .font(ClavisTypography.inter(13, weight: .regular))
                                .foregroundColor(.clavixInk2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 28)

                    OnboardingActionButton(
                        title: "See my full breakdown",
                        fill: .clavixInk,
                        foreground: .clavixPaper,
                        isEnabled: !viewModel.isCompleting,
                        action: onFinish
                    )

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(ClavisTypography.clavixCaption)
                            .foregroundColor(.clavixBadInk)
                            .padding(.top, 10)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Text("Informational only. Not investment advice.")
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixInk4)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
            }
        } else {
            ProgressView().tint(.clavixInk)
        }
    }

    private func blindSpotSentence(_ reveal: AhaReveal) -> String {
        let dim = reveal.blindSpot
        if dim.weakCount > 0 {
            let noun = dim.weakCount == 1 ? "position scores" : "positions score"
            return "\(dim.weakCount) of your \(dim.total) \(noun) low on \(dim.name.lowercased()), which measures \(dim.explanation). This is where your book is most exposed."
        } else {
            return "\(dim.name) is the lowest-scoring dimension across your book, measuring \(dim.explanation). It is your relative soft spot even though no single name is critical."
        }
    }
}

private struct AhaFindingRow: View {
    let label: String
    let ticker: String
    let grade: String
    let note: String

    var body: some View {
        ClavixCard(fill: .clavixPaper) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased())
                        .font(ClavisTypography.clavixMono(9, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.clavixInk3)
                    Text(ticker)
                        .font(ClavisTypography.clavixMono(15, weight: .bold))
                        .foregroundColor(.clavixInk)
                    Text(note)
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixInk3)
                }
                Spacer()
                ClavixGradeBadge(grade, size: 34)
            }
        }
        .padding(.bottom, 8)
    }
}
