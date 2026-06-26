import SwiftUI
import UniformTypeIdentifiers

struct OnboardingContainerView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @StateObject private var viewModel = OnboardingViewModel()
    @StateObject private var brokerageViewModel = BrokerageViewModel()
    @State private var showUpgradeSheet = false
    @State private var showCSVSheet = false
    @State private var showOnboardingPaywall = false

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            Group {
                switch viewModel.currentPage {
                case .welcome:
                    OnboardingWelcomeSetupView(
                        viewModel: viewModel,
                        isFreeTier: !subscriptionManager.isPro,
                        onPrimary: {
                            if viewModel.continueToAnalysis() {
                                viewModel.nextPage()
                            }
                        }
                    )
                case .addPortfolio:
                    OnboardingPortfolioAhaView(
                        viewModel: viewModel,
                        isFreeTier: !subscriptionManager.isPro,
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
                .environmentObject(subscriptionManager)
        }
        .sheet(isPresented: $showOnboardingPaywall) {
            PaywallView(
                triggerContext: .onboardingReveal,
                onEntitlementActivated: finishOnboardingAfterEntitlement
            )
                .environmentObject(subscriptionManager)
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
        if !subscriptionManager.isPro {
            if let reveal = viewModel.reveal {
                OnboardingPaywallContext.store(from: reveal)
            }
            showOnboardingPaywall = true
            return
        }

        finishOnboardingAfterEntitlement()
    }

    private func finishOnboardingAfterEntitlement() {
        showOnboardingPaywall = false
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
                    OnboardingLogoGrid()
                        .padding(.horizontal, -24)
                        .padding(.bottom, 36)

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
                        .foregroundColor(.ink2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, viewModel.errorMessage != nil ? 10 : 18)

                    if let errorMessage = viewModel.errorMessage?.sanitizedDisplayText,
                       !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(ClavisTypography.inter(13, weight: .medium))
                            .foregroundColor(.warn)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 12)
                    }

                    OnboardingHoldingsEntry(
                        viewModel: viewModel,
                        isFreeTier: isFreeTier
                    )

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
            Button(action: onPrimary) {
                Group {
                    if viewModel.isPreparingAnalysis {
                        ProgressView().tint(.backgroundPrimary).scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundColor(.backgroundPrimary)
                .frame(width: 44, height: 44)
                .background(Color.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isPreparingAnalysis)
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .trailing)
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

private struct OnboardingLogoGrid: View {
    private struct LogoEntry: Identifiable {
        let id: String
        let domain: String
    }
    private struct Row {
        let entries: [LogoEntry]
        let brick: Bool
    }

    private let gap: CGFloat = 8
    private let brickExtraShift: CGFloat = 10

    // Tiles are sized to fit 5.5 per row so 6 tiles always overflow the
    // container on both sides — clips create partial tiles at each edge.
    private var tileW: CGFloat { (UIScreen.main.bounds.width - 5 * gap) / 5.5 }
    // Centers overflow for even rows; brick rows shift right by brickExtraShift.
    private var baseShift: CGFloat {
        let rowW = 6 * tileW + 5 * gap
        return -(rowW - UIScreen.main.bounds.width) / 2
    }
    private var gridHeight: CGFloat { (4 * tileW + 3 * gap) * 0.8 }

    // All rows: 6 tiles. Even rows centered (equal partial tiles at both edges).
    // Brick rows shifted +10pt right → left tile shows more, right tile shows less.
    private let rows: [Row] = [
        Row(entries: [
            .init(id: "AAPL", domain: "apple.com"),
            .init(id: "MSFT", domain: "microsoft.com"),
            .init(id: "NVDA", domain: "nvidia.com"),
            .init(id: "GOOGL", domain: "google.com"),
            .init(id: "AMZN", domain: "amazon.com"),
            .init(id: "DIS",  domain: "disney.com"),
        ], brick: false),
        Row(entries: [
            .init(id: "V",    domain: "visa.com"),
            .init(id: "META", domain: "meta.com"),
            .init(id: "TSLA", domain: "tesla.com"),
            .init(id: "JPM",  domain: "jpmorgan.com"),
            .init(id: "NFLX", domain: "netflix.com"),
            .init(id: "COIN", domain: "coinbase.com"),
        ], brick: true),
        Row(entries: [
            .init(id: "INTC", domain: "intel.com"),
            .init(id: "JNJ",  domain: "jnj.com"),
            .init(id: "WMT",  domain: "walmart.com"),
            .init(id: "BAC",  domain: "bankofamerica.com"),
            .init(id: "PYPL", domain: "paypal.com"),
            .init(id: "UNH",  domain: "unitedhealthgroup.com"),
        ], brick: false),
        Row(entries: [
            .init(id: "COST", domain: "costco.com"),
            .init(id: "AMD",  domain: "amd.com"),
            .init(id: "SBUX", domain: "starbucks.com"),
            .init(id: "SPOT", domain: "spotify.com"),
            .init(id: "UBER", domain: "uber.com"),
            .init(id: "SHOP", domain: "shopify.com"),
        ], brick: true),
    ]

    var body: some View {
        GeometryReader { geo in
            let tW = (geo.size.width - 5 * gap) / 5.5
            let rowW = 6 * tW + 5 * gap
            let base = -(rowW - geo.size.width) / 2

            VStack(spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: gap) {
                        ForEach(row.entries) { entry in
                            OnboardingLogoTile(ticker: entry.id, domain: entry.domain)
                                .frame(width: tW, height: tW)
                        }
                    }
                    .offset(x: row.brick ? base + brickExtraShift : base)
                }
            }
            .clipShape(Rectangle())
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: 0.0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.50),
                        .init(color: .clear, location: 0.76),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(height: gridHeight)
    }
}

private struct OnboardingLogoTile: View {
    let ticker: String
    let domain: String

    var body: some View {
        ZStack {
            Color.white
            AsyncImage(
                url: URL(string: "https://t3.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=http://\(domain)&size=128"),
                content: { image in
                    image.resizable().scaledToFit().padding(9)
                },
                placeholder: {
                    Text(ticker)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.black.opacity(0.45))
                }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
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
            ), prompt: Text("Ticker").foregroundColor(.textSecondary))
            .font(ClavisTypography.mono(15))
            .foregroundColor(.textPrimary)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)

            TextField("0", text: Binding(
                get: { entry.shares },
                set: { viewModel.updateShares(entry.id, $0) }
            ), prompt: Text("0").foregroundColor(.textSecondary))
            .font(ClavisTypography.mono(15))
            .foregroundColor(.textPrimary)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 62)

            Button {
                viewModel.removeEntry(entry.id)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.textTertiary)
            }
            .buttonStyle(.plain)
            .opacity(viewModel.entries.count > 1 ? 1 : 0)
            .disabled(viewModel.entries.count <= 1)
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
            case .questions:
                AhaQuestionsScreen(viewModel: viewModel).transition(.opacity)
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
            .foregroundColor(enabled ? .backgroundPrimary : .textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(enabled ? Color.textPrimary : Color.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(enabled ? Color.clear : Color.border, lineWidth: 1.5)
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
                    .foregroundColor(.ink2)
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
                    viewModel.enterQuestions()
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
                            .foregroundColor(.ink2)
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
                ), prompt: Text("AAPL").foregroundColor(.textSecondary))
                .font(ClavisTypography.mono(15))
                .foregroundColor(.textPrimary)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .frame(maxWidth: .infinity, alignment: .leading)

                TextField("—", text: Binding(
                    get: { entry.shares },
                    set: { viewModel.updateShares(entry.id, $0) }
                ), prompt: Text("—").foregroundColor(.textSecondary))
                .font(ClavisTypography.mono(13))
                .foregroundColor(.ink2)
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

// MARK: - Questions (quick personalization, presentation only)

private struct AhaQuestionsScreen: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("YOUR PROFILE")
                                .font(ClavisTypography.label)
                                .tracking(1.6)
                                .foregroundColor(.textSecondary)
                            Text("How you invest.")
                                .font(ClavisTypography.inter(26, weight: .semibold))
                                .tracking(-0.4)
                                .foregroundColor(.textPrimary)
                            Text("A few details so your rating speaks to how you actually invest.")
                                .font(ClavisTypography.inter(14))
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        questionBlock("What matters to you?", caption: "Pick up to \(OnboardingViewModel.maxPriorities).") {
                            FlowLayout(spacing: 8) {
                                ForEach(OnboardingPriority.allCases) { option in
                                    let isSelected = viewModel.priorities.contains(option)
                                    let atCap = viewModel.priorities.count >= OnboardingViewModel.maxPriorities
                                    OnboardingChoiceChip(label: option.label, selected: isSelected, dimmed: !isSelected && atCap) {
                                        viewModel.togglePriority(option)
                                    }
                                }
                            }
                        }

                        questionBlock("What's your investment horizon?") {
                            FlowLayout(spacing: 8) {
                                ForEach(OnboardingTimeline.allCases) { option in
                                    OnboardingChoiceChip(label: option.label, selected: viewModel.timeline == option) {
                                        viewModel.timeline = option
                                    }
                                }
                            }
                        }

                        questionBlock("What's your risk tolerance?") {
                            FlowLayout(spacing: 8) {
                                ForEach(OnboardingRiskTolerance.allCases) { option in
                                    OnboardingChoiceChip(label: option.label, selected: viewModel.riskTolerance == option) {
                                        viewModel.riskTolerance = option
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }

                AhaPrimaryButton(title: "See my rating", enabled: viewModel.questionsComplete) {
                    viewModel.finishQuestions()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, max(16, proxy.safeAreaInsets.bottom + 8))
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .background(Color.backgroundPrimary)
            }
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            OnboardingStickyBar(step: 2, total: 2)
        }
    }

    @ViewBuilder private func questionBlock<Content: View>(_ title: String, caption: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(ClavisTypography.inter(15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                if let caption {
                    Text(caption)
                        .font(ClavisTypography.inter(12, weight: .regular))
                        .foregroundColor(.textTertiary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingChoiceChip: View {
    let label: String
    let selected: Bool
    var dimmed: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(ClavisTypography.inter(13, weight: .medium))
                .foregroundColor(selected ? .backgroundPrimary : (dimmed ? .textTertiary : .textPrimary))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(selected ? Color.textPrimary : Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(selected ? Color.clear : Color.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .opacity(dimmed ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

/// Minimal wrapping layout for chips (iOS 16+ Layout).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                totalHeight += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + bounds.width, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Reveal (the first personalized insight)

private struct AhaRevealScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: OnboardingViewModel
    let onFinish: () -> Void
    @State private var analysisDone = false

    var body: some View {
        if let reveal = viewModel.reveal {
            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header(reveal)

                        AhaRiskProfileCard(reveal: reveal, reduceMotion: reduceMotion) {
                            withAnimation(.easeInOut(duration: 0.4)) { analysisDone = true }
                        }

                        if analysisDone {
                            weakestCard(reveal)
                                .transition(.opacity.combined(with: .offset(y: 8)))

                            if let strongest = reveal.strongest, strongest.key != reveal.blindSpot.key {
                                strongestCard(reveal, metric: strongest)
                                    .transition(.opacity.combined(with: .offset(y: 8)))
                            }

                            AhaLockedDetail(reveal: reveal)
                                .transition(.opacity)

                            VStack(spacing: 0) {
                                AhaPrimaryButton(
                                    title: "Continue to 14-day trial",
                                    enabled: !viewModel.isCompleting,
                                    action: onFinish
                                )

                                if let error = viewModel.errorMessage {
                                    Text(error)
                                        .font(ClavisTypography.clavixCaption)
                                        .foregroundColor(.bad)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.top, 10)
                                }

                                Text("FREE FOR 14 DAYS · CANCEL ANYTIME")
                                    .font(ClavisTypography.mono(8))
                                    .tracking(0.6)
                                    .foregroundColor(.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 13)
                            }
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .animation(.easeInOut(duration: 0.35), value: analysisDone)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                OnboardingStickyBar(step: 2, total: 2)
            }
        } else {
            ProgressView().tint(.textPrimary)
        }
    }

    // MARK: Header (swaps from "building" to the finished profile)

    @ViewBuilder private func header(_ reveal: AhaReveal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if analysisDone {
                Text("RISK PROFILE")
                    .font(ClavisTypography.label).tracking(1.6).foregroundColor(.textSecondary)
                Text("Your portfolio's results.")
                    .font(ClavisTypography.inter(26, weight: .semibold)).tracking(-0.4)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 12) {
                    ClavixGradeBadge(reveal.grade, size: 44)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(reveal.score.rounded()))")
                            .font(ClavisTypography.mono(32)).foregroundColor(.textPrimary)
                        Text("/100").font(ClavisTypography.mono(12)).foregroundColor(.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(gradeTier(reveal.grade).uppercased())
                        .font(ClavisTypography.label).tracking(0.8)
                        .foregroundColor(gradeTierColor(reveal.grade))
                }
                .padding(.top, 4)

                Text(gradeDescriptor(reveal))
                    .font(ClavisTypography.inter(14)).foregroundColor(.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            } else {
                Text("ANALYZING")
                    .font(ClavisTypography.label).tracking(1.6).foregroundColor(.textSecondary)
                Text("Analyzing your portfolio.")
                    .font(ClavisTypography.inter(26, weight: .semibold)).tracking(-0.4)
                    .foregroundColor(.textPrimary)
                Text(buildSubtitle(reveal))
                    .font(ClavisTypography.inter(14)).foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buildSubtitle(_ reveal: AhaReveal) -> String {
        let n = reveal.positionCount
        let holdings = "\(n) holding\(n == 1 ? "" : "s")"
        return "Scoring your \(holdings) across five risk metrics."
    }

    // MARK: Grade meaning

    private func gradeTier(_ grade: String) -> String {
        switch grade {
        case "AAA", "AA": return "Very low risk"
        case "A":         return "Low risk"
        case "BBB":       return "Moderate risk"
        case "BB":        return "Elevated risk"
        case "B":         return "High risk"
        default:          return "Very high risk"
        }
    }

    private func gradeTierColor(_ grade: String) -> Color {
        switch grade {
        case "AAA", "AA", "A": return .good
        case "BBB", "BB":      return .warn
        default:               return .bad
        }
    }

    private func gradeDescriptor(_ reveal: AhaReveal) -> String {
        let n = reveal.dimensions.filter { $0.average < 55 }.count
        let risks: String
        switch n {
        case 0:  risks = "no major weak spots"
        case 1:  risks = "one key risk to watch"
        case 2:  risks = "two key risks to watch"
        case 3:  risks = "three key risks to watch"
        default: risks = "\(n) key risks to watch"
        }
        let shape: String
        switch reveal.grade {
        case "AAA", "AA": shape = "A very resilient, well-balanced portfolio"
        case "A":         shape = "A resilient, balanced portfolio"
        case "BBB":       shape = "A balanced portfolio that leans steady"
        case "BB":        shape = "A balanced but exposed portfolio"
        case "B":         shape = "A higher-risk portfolio"
        default:          shape = "A high-risk portfolio"
        }
        return "\(shape) with \(risks)."
    }

    // MARK: Weakest / strongest metric callouts (with a per-holding deep dive)

    @ViewBuilder private func weakestCard(_ reveal: AhaReveal) -> some View {
        metricCard(eyebrow: "WEAKEST METRIC", tone: .warn, metric: reveal.blindSpot,
                   breakdown: reveal.weakestBreakdown, narrative: weakNarrative(reveal))
    }

    @ViewBuilder private func strongestCard(_ reveal: AhaReveal, metric: AhaDimensionFinding) -> some View {
        metricCard(eyebrow: "STRONGEST METRIC", tone: .good, metric: metric,
                   breakdown: reveal.strongestBreakdown, narrative: strongNarrative(reveal, metric: metric))
    }

    @ViewBuilder private func metricCard(eyebrow: String, tone: Color, metric: AhaDimensionFinding,
                                         breakdown: [MetricContribution], narrative: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow)
                        .font(ClavisTypography.label).tracking(1.2).foregroundColor(tone)
                    Text(metric.name)
                        .font(ClavisTypography.inter(20, weight: .semibold)).tracking(-0.3)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(metric.average.rounded()))")
                        .font(ClavisTypography.mono(28)).foregroundColor(tone)
                    Text("/100").font(ClavisTypography.mono(10)).foregroundColor(.textSecondary)
                }
            }

            Text(metricMeaning(metric))
                .font(ClavisTypography.inter(13)).foregroundColor(.ink2)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)

            if breakdown.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BY HOLDING")
                        .font(ClavisTypography.label).tracking(1.0).foregroundColor(.textTertiary)
                    ForEach(breakdown) { c in
                        HStack(spacing: 10) {
                            Text(c.ticker)
                                .font(ClavisTypography.mono(12)).foregroundColor(.textPrimary)
                                .frame(width: 56, alignment: .leading)
                            GeometryReader { p in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.surfaceElevated)
                                    Capsule().fill(tone.opacity(0.7))
                                        .frame(width: max(4, p.size.width * CGFloat(max(0, min(100, c.value)) / 100)))
                                }
                            }
                            .frame(height: 6)
                            Text("\(Int(c.value.rounded()))")
                                .font(ClavisTypography.mono(12)).foregroundColor(.textSecondary)
                                .frame(width: 28, alignment: .trailing)
                        }
                        .frame(height: 16)
                    }
                }
            }

            Text(narrative)
                .font(ClavisTypography.inter(13)).foregroundColor(.textSecondary)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
    }

    private func metricMeaning(_ metric: AhaDimensionFinding) -> String {
        "Measures \(metric.explanation). Each holding is scored 0 to 100, where higher is stronger, then averaged."
    }

    private func weakNarrative(_ reveal: AhaReveal) -> String {
        let m = reveal.blindSpot
        if reveal.positionCount > 1, let t = reveal.weakestCulpritTicker, let v = reveal.weakestCulpritValue {
            return "\(t) is the main drag at \(score(v)), pulling the average into the \(band(m.average)) band at \(score(m.average))."
        }
        return "At \(score(m.average)), that sits in the \(band(m.average)) band, your lowest metric."
    }

    private func strongNarrative(_ reveal: AhaReveal, metric: AhaDimensionFinding) -> String {
        if reveal.positionCount > 1, let t = reveal.strongestLeaderTicker, let v = reveal.strongestLeaderValue {
            return "\(t) leads at \(score(v)), lifting the average into the \(band(metric.average)) band at \(score(metric.average))."
        }
        return "At \(score(metric.average)), that sits in the \(band(metric.average)) band, your highest metric."
    }

    private func band(_ v: Double) -> String {
        switch v {
        case ..<40:  return "weak"
        case ..<55:  return "below-average"
        case ..<70:  return "moderate"
        case ..<85:  return "solid"
        default:     return "strong"
        }
    }

    private func score(_ v: Double) -> String { "\(Int(v.rounded()))" }
}

// MARK: - Risk profile card (radar assembles signal by signal)

private struct AhaRiskProfileCard: View {
    let reveal: AhaReveal
    let reduceMotion: Bool
    let onComplete: () -> Void

    @State private var displayed: [Double]
    @State private var activeIndex: Int? = nil
    @State private var finished = false
    @State private var started = false

    private var dims: [AhaDimensionFinding] { reveal.dimensions }

    /// When finished, emphasize both extremes: weakest in amber, strongest in green.
    /// During the build, emphasize the metric currently being analyzed.
    private var highlightMap: [String: Color] {
        if finished {
            var map: [String: Color] = [reveal.blindSpot.key: .warn]
            if let s = reveal.strongest, s.key != reveal.blindSpot.key { map[s.key] = .good }
            return map
        }
        if let i = activeIndex, dims.indices.contains(i) {
            return [dims[i].key: .textPrimary]
        }
        return [:]
    }

    init(reveal: AhaReveal, reduceMotion: Bool, onComplete: @escaping () -> Void) {
        self.reveal = reveal
        self.reduceMotion = reduceMotion
        self.onComplete = onComplete
        _displayed = State(initialValue: Array(repeating: 0, count: reveal.dimensions.count))
    }

    var body: some View {
        VStack(spacing: 14) {
            if dims.count >= 3 {
                AhaRiskRadar(
                    dimensions: dims,
                    values: displayed,
                    highlights: highlightMap
                )
                .frame(height: 250)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 11) {
                    ForEach(Array(dims.enumerated()), id: \.element.key) { _, d in
                        AhaSignalRow(dimension: d, isFocus: d.key == reveal.blindSpot.key,
                                     highlightColor: .warn, valuesVisible: true,
                                     animationDelay: 0, reduceMotion: reduceMotion)
                    }
                }
            }

            Divider().overlay(Color.border)

            statusArea
        }
        .padding(16)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
        .task {
            guard !started else { return }
            started = true
            await run()
        }
    }

    @ViewBuilder private var statusArea: some View {
        if let i = activeIndex, dims.indices.contains(i) {
            HStack(spacing: 10) {
                Circle().fill(Color.good).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Analyzing \(dims[i].name.lowercased())")
                        .font(ClavisTypography.inter(13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(dims[i].explanation)
                        .font(ClavisTypography.inter(11))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(Int(displayed[i].rounded()))")
                    .font(ClavisTypography.mono(15))
                    .monospacedDigit()
                    .foregroundColor(.textPrimary)
            }
            .frame(height: 30)
        } else {
            HStack {
                Text("Each holding scored across five risk metrics, then weighed into one score.")
                    .font(ClavisTypography.inter(11))
                    .foregroundColor(.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Sequencing — analyze one signal at a time

    @MainActor private func run() async {
        guard dims.count >= 3, !reduceMotion else {
            displayed = dims.map { $0.average }
            finished = true
            onComplete()
            return
        }

        await sleep(0.35)
        for i in dims.indices {
            withAnimation(.easeInOut(duration: 0.2)) { activeIndex = i }
            await scanAxis(i)
            await sleep(0.08)
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            activeIndex = nil
            finished = true
        }
        await sleep(0.15)
        onComplete()
    }

    /// Scan a single axis: jump around with wide, narrowing swings (so it reads as
    /// real computation), lightly damped so it isn't pure static, then settle.
    @MainActor private func scanAxis(_ i: Int) async {
        let target = dims[i].average
        var current = displayed[i]
        let scanFrames = 16
        for f in 0..<scanFrames {
            let t = Double(f) / Double(scanFrames - 1)          // 0 → 1
            let center = target * min(1, 0.3 + t * 0.8)
            let spread = (1 - t * t) * 48                         // big early, narrows fast
            let jumpTarget = max(3, min(98, center + Double.random(in: -spread...spread)))
            current += (jumpTarget - current) * 0.46             // more damping = smoother
            displayed[i] = current
            await sleep(0.044)
        }
        // overshoot, then settle smoothly onto the real value
        displayed[i] = min(100, target + 7)
        await sleep(0.05)
        let from = displayed[i]
        for s in 1...4 {
            displayed[i] = from + (target - from) * Double(s) / 4
            await sleep(0.03)
        }
        displayed[i] = target
    }

    private func sleep(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }
}

/// A five-axis risk radar. Pure renderer: it draws whatever `values` it is given,
/// so the parent can grow it signal by signal. `highlights` maps a dimension key to
/// the color it should be emphasized with (e.g. weakest amber, strongest green).
private struct AhaRiskRadar: View {
    let dimensions: [AhaDimensionFinding]
    let values: [Double]
    let highlights: [String: Color]

    var body: some View {
        GeometryReader { geo in
            let n = dimensions.count
            let labelInset: CGFloat = 80
            let radius = max(24, (min(geo.size.width, geo.size.height) - labelInset) / 2)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                Canvas { ctx, _ in
                    // concentric grid rings
                    for ring in stride(from: 0.25, through: 1.0, by: 0.25) {
                        var path = Path()
                        for i in 0..<n {
                            let p = vertex(i, n, center, radius * CGFloat(ring))
                            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                        }
                        path.closeSubpath()
                        ctx.stroke(path, with: .color(Color.border), lineWidth: ring == 1.0 ? 1 : 0.75)
                    }
                    // spokes
                    for i in 0..<n {
                        var s = Path()
                        s.move(to: center)
                        s.addLine(to: vertex(i, n, center, radius))
                        ctx.stroke(s, with: .color(Color.border.opacity(0.6)), lineWidth: 0.75)
                    }
                    // data polygon
                    var data = Path()
                    for i in 0..<n {
                        let p = vertex(i, n, center, radius * unit(i))
                        if i == 0 { data.move(to: p) } else { data.addLine(to: p) }
                    }
                    data.closeSubpath()
                    ctx.fill(data, with: .color(Color.textPrimary.opacity(0.10)))
                    ctx.stroke(data, with: .color(Color.textPrimary.opacity(0.85)), lineWidth: 1.5)
                    // vertex dots (highlighted keys get their accent color + a larger dot)
                    for i in 0..<n {
                        let p = vertex(i, n, center, radius * unit(i))
                        let hi = highlights[dimensions[i].key]
                        let r: CGFloat = hi != nil ? 4.5 : 2.5
                        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                        ctx.fill(Path(ellipseIn: rect), with: .color(hi ?? Color.textPrimary))
                    }
                }

                ForEach(Array(dimensions.enumerated()), id: \.element.key) { i, dim in
                    let p = vertex(i, n, center, radius + 22)
                    let hi = highlights[dim.key]
                    VStack(spacing: 1) {
                        Text(shortName(dim))
                            .font(ClavisTypography.inter(10, weight: hi != nil ? .semibold : .medium))
                            .foregroundColor(hi ?? .textSecondary)
                        Text("\(Int(value(i).rounded()))")
                            .font(ClavisTypography.mono(11))
                            .foregroundColor(hi ?? .textPrimary)
                    }
                    .fixedSize()
                    .position(x: p.x, y: p.y)
                }
            }
        }
    }

    private func value(_ i: Int) -> Double { values.indices.contains(i) ? values[i] : 0 }
    private func unit(_ i: Int) -> CGFloat { CGFloat(max(0, min(100, value(i))) / 100) }
    private func vertex(_ i: Int, _ n: Int, _ center: CGPoint, _ r: CGFloat) -> CGPoint {
        let angle = -CGFloat.pi / 2 + CGFloat(i) * (2 * .pi / CGFloat(n))
        return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
    }
    private func shortName(_ d: AhaDimensionFinding) -> String {
        switch d.key {
        case "FIN": return "Financials"
        case "NEWS": return "News"
        case "MAC": return "Macro"
        case "SEC": return "Sector"
        case "VOL": return "Stability"
        default: return d.name
        }
    }
}

private struct AhaSignalRow: View {
    let dimension: AhaDimensionFinding
    let isFocus: Bool
    let highlightColor: Color
    let valuesVisible: Bool
    let animationDelay: Double
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(shortName)
                .font(ClavisTypography.inter(12, weight: isFocus ? .semibold : .medium))
                .foregroundColor(isFocus ? .textPrimary : .textSecondary)
                .frame(width: 72, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surfaceElevated)
                    Capsule()
                        .fill(isFocus ? highlightColor : Color.textPrimary.opacity(0.62))
                        .frame(width: valuesVisible ? proxy.size.width * normalizedScore : 4)
                }
            }
            .frame(height: 7)
            .animation(
                reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.72).delay(animationDelay),
                value: valuesVisible
            )

            Text("\(Int(dimension.average.rounded()))")
                .font(ClavisTypography.mono(11))
                .foregroundColor(isFocus ? highlightColor : .textSecondary)
                .frame(width: 24, alignment: .trailing)
        }
        .frame(height: 18)
    }

    private var normalizedScore: CGFloat {
        min(1, max(0.04, dimension.average / 100))
    }

    private var shortName: String {
        switch dimension.key {
        case "FIN": return "Financials"
        case "NEWS": return "News"
        case "MAC": return "Macro"
        case "SEC": return "Sector"
        case "VOL": return "Stability"
        default: return dimension.name
        }
    }
}

private struct AhaLockedDetail: View {
    let reveal: AhaReveal

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(Color.surfaceElevated)
                    .frame(width: 42, height: 42)
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(detailTitle)
                    .font(ClavisTypography.inter(15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("Unlock the stock-by-stock breakdown and daily monitoring.")
                    .font(ClavisTypography.inter(12, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.surface.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
    }

    private var detailTitle: String {
        let area = reveal.blindSpot.name.lowercased()
        if let ticker = reveal.weakestCulpritTicker {
            return "See what's driving \(area) in \(ticker)"
        }
        return "See the stock-by-stock \(area) breakdown"
    }
}
