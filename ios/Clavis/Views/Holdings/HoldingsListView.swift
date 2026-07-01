import SwiftUI

extension Notification.Name {
    static let openAddHoldingFromOnboarding = Notification.Name("openAddHoldingFromOnboarding")
    static let holdingsDidChange = Notification.Name("holdingsDidChange")
    static let watchlistDidChange = Notification.Name("watchlistDidChange")
}

private enum HoldingsSortKey {
    case risk
    case weight
    case grade
    case dayChange
    case profitLoss
}

struct HoldingsListView: View {
    @Binding var selectedTab: Int
    @Binding var deepLinkTicker: String?

    @StateObject private var viewModel = HoldingsViewModel()
    @StateObject private var brokerageViewModel = BrokerageViewModel()
    @State private var navigationPath: [String] = []
    @State private var deleteCandidate: Position?
    @State private var showUpgradeSheet = false
    @State private var showAddHoldingSheet = false
    @State private var showQuickSetupSheet = false
    @State private var sortKey: HoldingsSortKey = .risk
    @State private var donutSelection: String?

    // First-run getting-started checklist (interactive launcher)
    @AppStorage("clavix.checklist.openedBreakdown") private var clOpenedBreakdown = false
    @AppStorage("clavix.checklist.viewedToday") private var clViewedToday = false
    @AppStorage("clavix.checklist.trackedName") private var clTrackedName = false
    @AppStorage("clavix.checklist.dismissed") private var clDismissed = false

    private var totalMarketValue: Double {
        viewModel.holdings.compactMap(\.currentValue).reduce(0, +)
    }

    private var sortedHoldings: [Position] {
        viewModel.holdings.sorted { lhs, rhs in
            switch sortKey {
            case .risk:
                let lhsContribution = (lhs.currentValue ?? 0) * max(0, 100 - (lhs.resolvedTotalScore ?? 50))
                let rhsContribution = (rhs.currentValue ?? 0) * max(0, 100 - (rhs.resolvedTotalScore ?? 50))
                return lhsContribution > rhsContribution
            case .weight:
                return (lhs.currentValue ?? 0) > (rhs.currentValue ?? 0)
            case .grade:
                return (lhs.resolvedTotalScore ?? 0) < (rhs.resolvedTotalScore ?? 0)
            case .dayChange:
                return abs(lhs.sharedAnalysis?.dayChangePct ?? 0) > abs(rhs.sharedAnalysis?.dayChangePct ?? 0)
            case .profitLoss:
                return (lhs.unrealizedPL ?? 0) > (rhs.unrealizedPL ?? 0)
            }
        }
    }

    private var weightedScore: Double? {
        PortfolioMath.weightedScore(viewModel.holdings)
    }

    private var weightedGrade: String {
        PortfolioMath.weightedGrade(viewModel.holdings)
    }

    private var biggestMover: Position? {
        sortedHoldings.max { abs($0.scoreDelta ?? 0) < abs($1.scoreDelta ?? 0) }
    }

    private var isFreeTier: Bool {
        !SubscriptionManager.shared.isPro
    }

    private var isInitialHydration: Bool {
        viewModel.isLoading && viewModel.holdings.isEmpty
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                    if let errorMessage = viewModel.errorMessage {
                        DashboardErrorCard(message: errorMessage)
                    }

                    bookHero
                    if showGettingStarted { gettingStartedCard }
                    compositionSection
                    positionsSection
                    watchlistSection
                }
                .padding(.horizontal, ClavisTheme.screenPadding)
                .padding(.top, ClavisTheme.sectionSpacing)
                .padding(.bottom, ClavisTheme.extraLargeSpacing)
            }
            .background(Color.clavixPage.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                ClavixStickyBar(trailing: AnyView(
                    Button(action: openAddHolding) {
                        Image(systemName: "plus")
                            .foregroundColor(.clavixInk)
                    }
                    .buttonStyle(.plain)
                ))
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await viewModel.loadHoldings()
            }
            .onAppear {
                Task { await viewModel.refreshWatchlist() }
            }
            .refreshable {
                await viewModel.refreshHoldings()
            }
            .onChange(of: deepLinkTicker) { _, newValue in
                guard let ticker = newValue else { return }
                deepLinkTicker = nil
                navigationPath.append(ticker)
            }
            .sheet(isPresented: $showQuickSetupSheet) {
                QuickPortfolioSetupSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showAddHoldingSheet) {
                HoldingsAddMethodSheet(
                    viewModel: viewModel,
                    brokerageViewModel: brokerageViewModel,
                    selectedTab: $selectedTab
                )
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
            .fullScreenCover(isPresented: $viewModel.showProgressSheet) {
                AddPositionProgressView(viewModel: viewModel)
            }
            .sheet(isPresented: Binding(
                get: { showUpgradeSheet || viewModel.showHoldingLimitPaywall },
                set: { if !$0 { showUpgradeSheet = false; viewModel.showHoldingLimitPaywall = false } }
            )) {
                PaywallView(triggerContext: .holdingLimit)
                    .environmentObject(SubscriptionManager.shared)
            }
            .sheet(item: $deleteCandidate) { position in
                HoldingDeleteSheet(
                    ticker: position.ticker,
                    onDelete: {
                        Task { await viewModel.deleteHolding(position) }
                        deleteCandidate = nil
                    },
                    onKeep: {
                        deleteCandidate = nil
                    }
                )
            }
            .navigationDestination(for: TickerSearchResult.self) { result in
                TickerDetailView(ticker: result.ticker)
            }
            .navigationDestination(for: String.self) { ticker in
                TickerDetailView(ticker: ticker)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAddHoldingFromOnboarding)) { _ in
                openAddHolding()
            }
            .onReceive(NotificationCenter.default.publisher(for: .watchlistDidChange)) { _ in
                Task { await viewModel.refreshWatchlist() }
            }
        }
    }

    // MARK: - Book hero

    private var bookHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Holdings")
                .font(ClavisTypography.clavixSerif(34, weight: .medium))
                .tracking(-0.6)
                .foregroundColor(.clavixInk)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio value")
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixInk3)
                    Text(totalMarketValue > 0 ? currencyNoCents(totalMarketValue) : "—")
                        .font(ClavisTypography.clavixMono(29, weight: .semibold))
                        .tracking(-0.6)
                        .foregroundColor(.clavixInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    if let stamp = syncStampText {
                        Text(stamp)
                            .font(ClavisTypography.clavixMono(10, weight: .regular))
                            .tracking(0.7)
                            .foregroundColor(.clavixInk3)
                    }
                    Text(holdingsSummaryText)
                        .font(ClavisTypography.clavixMono(10, weight: .regular))
                        .tracking(0.3)
                        .foregroundColor(.clavixInk3)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    ClavixGradeBadge(weightedGrade)
                    Text(weightedScore.map { "Composite \(Int($0.rounded()))" } ?? "Composite —")
                        .font(ClavisTypography.clavixMono(11, weight: .regular))
                        .foregroundColor(.clavixInk3)
                }
            }
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.clavixRule).frame(height: 1) }
    }

    private var syncStampText: String? {
        if isInitialHydration {
            return "SYNCING LATEST BOOK"
        }
        if let ts = viewModel.brokerageLastSyncedAt {
            let stamp = ts.formatted(date: .omitted, time: .shortened)
            return "SYNCED \(stamp.uppercased()) · BROKERAGE"
        }
        if let ts = viewModel.lastRefreshedAt {
            let dateText = ts.formatted(date: .abbreviated, time: .omitted)
            return "UPDATED \(dateText.uppercased())"
        }
        return nil
    }

    private var holdingsSummaryText: String {
        if isInitialHydration {
            return "Loading positions and watchlist"
        }

        let holdingsCount = viewModel.holdings.count
        return "\(holdingsCount) position\(holdingsCount == 1 ? "" : "s") · \(viewModel.watchlistItems.count) monitored"
    }

    // MARK: - Sort toolbar

    private var holdingsToolbar: some View {
        HStack(spacing: 4) {
            toolbarPill(label: "Risk", key: .risk)
            toolbarPill(label: "Weight", key: .weight)
            toolbarPill(label: "Grade", key: .grade)
            toolbarPill(label: "Δ Today", key: .dayChange)
            Spacer()
        }
    }

    @ViewBuilder
    private var holdingsSection: some View {
        if viewModel.isLoading && viewModel.holdings.isEmpty {
            ClavisLoadingCard(title: "Loading holdings", subtitle: "Pulling your latest positions and ratings.")
        } else if viewModel.holdings.isEmpty {
            HoldingsEmptyState(onAddPosition: openAddHolding)
        } else {
            ClavixCard(padding: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        ClavixColumnHeader("Sym")
                            .frame(width: 70, alignment: .leading)
                        ClavixColumnHeader("Price")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ClavixColumnHeader("P&L", align: .trailing)
                            .frame(width: 70, alignment: .trailing)
                        ClavixColumnHeader("Grade · Δ", align: .trailing)
                            .frame(width: 60, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.clavixPaper2)
                    Rectangle().fill(Color.clavixRule).frame(height: 1)
                    ForEach(Array(sortedHoldings.enumerated()), id: \.element.id) { index, position in
                        NavigationLink(value: position.ticker) {
                            HoldingsRow(position: position)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteCandidate = position
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        if index < sortedHoldings.count - 1 {
                            Rectangle().fill(Color.clavixRule2).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private var watchlistSection: some View {
        simpleSection(
            title: "Watchlist",
            trailing: AnyView(
                Button("Add ticker →") { selectedTab = 2 }
                    .font(ClavisTypography.clavixCaption)
                    .foregroundColor(.clavixAccent)
                    .buttonStyle(.plain)
            )
        ) {
            if isInitialHydration && viewModel.watchlistItems.isEmpty {
                ClavisLoadingCard(title: "Loading watchlist", subtitle: "Checking the tickers you already track.")
            } else if viewModel.watchlistItems.isEmpty {
                ClavixCard {
                    Text("Track tickers here to monitor grade and price changes alongside your positions.")
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ClavixCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.watchlistItems.enumerated()), id: \.element.id) { index, item in
                            NavigationLink(value: item.ticker) {
                                WatchlistRow(item: item)
                            }
                            .buttonStyle(.plain)
                            if index < viewModel.watchlistItems.count - 1 {
                                Divider().overlay(Color.clavixRule)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sectorCompositionSection: some View {
        if !viewModel.holdings.isEmpty {
            simpleSection(title: "Grade Map") {
                ClavixCard(padding: 0) {
                    PositionHeatmapView(positions: sortedHoldings)
                        .frame(height: PositionHeatmapView.height(for: sortedHoldings.count))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    // MARK: - Composition (allocation + grade mix donuts)

    /// One slice per holding, sized by market value, tinted by its risk grade.
    private var allocationSlices: [DonutSlice] {
        guard totalMarketValue > 0 else { return [] }
        return viewModel.holdings
            .compactMap { position -> (Position, Double)? in
                guard let value = position.currentValue, value > 0 else { return nil }
                return (position, value)
            }
            .sorted { $0.1 > $1.1 }
            .map { position, value in
                let pct = value / totalMarketValue * 100
                return DonutSlice(
                    id: position.ticker,
                    label: position.ticker,
                    value: value,
                    color: ClavisGradeStyle.riskColor(for: position.resolvedRiskGrade),
                    caption: "\(Int(pct.rounded()))% · \(currencyNoCents(value))"
                )
            }
    }

    /// One slice per grade band present, sized by how many positions sit in it.
    private var gradeSlices: [DonutSlice] {
        let order = ["A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D", "D-", "F"]
        var counts: [String: Int] = [:]
        for position in viewModel.holdings {
            let grade = ClavisGradeStyle.displayGrade(position.resolvedRiskGrade)
            guard grade != "\u{2014}" else { continue }
            counts[grade, default: 0] += 1
        }
        let graded = counts.values.reduce(0, +)
        guard graded > 0 else { return [] }
        return order.compactMap { grade in
            guard let count = counts[grade], count > 0 else { return nil }
            let pct = Int((Double(count) / Double(graded) * 100).rounded())
            return DonutSlice(
                id: grade,
                label: grade,
                value: Double(count),
                color: ClavisGradeStyle.riskColor(for: grade),
                caption: "\(count) position\(count == 1 ? "" : "s") · \(pct)%"
            )
        }
    }

    private var gradedCount: Int {
        viewModel.holdings.filter { ClavisGradeStyle.displayGrade($0.resolvedRiskGrade) != "\u{2014}" }.count
    }

    @ViewBuilder
    private var compositionSection: some View {
        if !viewModel.holdings.isEmpty, totalMarketValue > 0 {
            VStack(alignment: .leading, spacing: 0) {
                Text("Composition")
                    .font(ClavisTypography.clavixSerif(20, weight: .medium))
                    .tracking(-0.3)
                    .foregroundColor(.clavixInk)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                ClavixCard {
                    ZStack {
                        // Tap-to-dismiss layer: any tap on empty card space clears
                        // the active wedge. Wedge taps hit the donuts in front.
                        Color.clavixPaper.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture { donutSelection = nil }
                        HStack(alignment: .top, spacing: 12) {
                            donutColumn(
                                title: "ALLOCATION",
                                subtitle: "share of book",
                                slices: allocationSlices,
                                centerPrimary: currencyNoCents(totalMarketValue),
                                centerDetail: "book value",
                                namespace: "alloc"
                            )
                            Rectangle().fill(Color.clavixRule).frame(width: 1)
                            donutColumn(
                                title: "GRADES",
                                subtitle: "positions per grade",
                                slices: gradeSlices,
                                centerPrimary: "\(gradedCount)",
                                centerDetail: gradedCount == 1 ? "ticker" : "tickers",
                                namespace: "grade"
                            )
                        }
                    }
                }
            }
        }
    }

    private func donutColumn(
        title: String,
        subtitle: String,
        slices: [DonutSlice],
        centerPrimary: String,
        centerDetail: String,
        namespace: String
    ) -> some View {
        VStack(spacing: 10) {
            // Only the donut wedges capture touches. Everything else here is
            // non-interactive so taps fall through to the card's clear layer
            // and deselect the active wedge.
            ClavixDonutChart(
                slices: slices,
                centerPrimary: centerPrimary,
                centerDetail: centerDetail,
                namespace: namespace,
                selection: $donutSelection
            )
            .frame(height: 130)

            VStack(spacing: 1) {
                Text(title)
                    .font(ClavisTypography.clavixMono(10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.clavixInk)
                Text(subtitle)
                    .font(ClavisTypography.clavixMono(8, weight: .regular))
                    .tracking(0.3)
                    .foregroundColor(.clavixInk3)
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Positions section

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your Holdings")
                .font(ClavisTypography.clavixSerif(20, weight: .medium))
                .tracking(-0.3)
                .foregroundColor(.clavixInk)
                .padding(.top, 6)
                .padding(.bottom, 10)
            holdingsToolbar
                .padding(.bottom, 10)
            holdingsSection
        }
    }

    private func simpleSection<Content: View>(
        title: String,
        trailing: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(ClavisTypography.clavixSerif(20, weight: .medium))
                    .tracking(-0.3)
                    .foregroundColor(.clavixInk)
                Spacer()
                if let trailing {
                    trailing
                }
            }
            content()
        }
        .padding(.top, 6)
    }

    private var sectorRows: [SectorHoldingsRow] {
        guard totalMarketValue > 0 else { return [] }

        struct Bucket {
            var positions: [Position] = []
            var value: Double = 0
        }

        var buckets: [String: Bucket] = [:]
        for position in viewModel.holdings {
            guard let value = position.currentValue, value > 0 else { continue }
            let sector = normalizedSectorName(position.sharedAnalysis?.sector)
            var bucket = buckets[sector, default: Bucket()]
            bucket.positions.append(position)
            bucket.value += value
            buckets[sector] = bucket
        }

        return buckets
            .map { sector, bucket in
                let tickers = bucket.positions
                    .map(\.ticker)
                    .sorted()
                    .joined(separator: " · ")
                let grade = PortfolioMath.weightedGrade(bucket.positions)
                return SectorHoldingsRow(
                    name: sector,
                    weightPct: Int(((bucket.value / totalMarketValue) * 100).rounded()),
                    grade: grade,
                    tickers: tickers
                )
            }
            .sorted { $0.weightPct > $1.weightPct }
    }

    private func normalizedSectorName(_ raw: String?) -> String {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "Unclassified"
        }
        switch value.lowercased() {
        case "tech":
            return "Technology"
        case "consumer discretionary":
            return "Consumer Disc."
        case "consumer staples":
            return "Consumer Staples"
        case "communication services":
            return "Communication Svcs"
        case "us total market":
            return "US Total Market"
        default:
            return value
        }
    }

    private func toolbarPill(label: String, key: HoldingsSortKey) -> some View {
        Button {
            sortKey = key
        } label: {
            ClavixPill(label: label, active: sortKey == key)
        }
        .buttonStyle(.plain)
    }

    private var allChecklistDone: Bool {
        clOpenedBreakdown && clViewedToday && clTrackedName
    }

    private var showGettingStarted: Bool {
        !clDismissed && !allChecklistDone && !viewModel.holdings.isEmpty
    }

    private var gettingStartedCard: some View {
        GettingStartedChecklistCard(
            openedBreakdown: clOpenedBreakdown,
            viewedToday: clViewedToday,
            trackedName: clTrackedName,
            onOpenBreakdown: {
                clOpenedBreakdown = true
                if let ticker = sortedHoldings.first?.ticker {
                    navigationPath.append(ticker)
                }
            },
            onMorningBrief: {
                clViewedToday = true
                selectedTab = 0
            },
            onTrackName: {
                clTrackedName = true
                selectedTab = 2
            },
            onDismiss: { clDismissed = true }
        )
    }

    private func openAddHolding() {
        if isFreeTier && viewModel.holdings.count >= 3 {
            showUpgradeSheet = true
        } else if viewModel.holdings.isEmpty {
            showQuickSetupSheet = true
        } else {
            showAddHoldingSheet = true
        }
    }

    private func currencyNoCents(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }

}

/// VQAHoldingsLedgerRow 1:1 — 4 columns: Sym/w%, Last/day(spark+pct), P&L,
/// Grade·Δ. Highlights when the position is in a worsening trend.
private struct HoldingsRow: View {
    let position: Position

    private var grade: String { position.resolvedRiskGrade ?? "—" }
    private var dayPct: Double? { position.sharedAnalysis?.dayChangePct }

    /// Newly added ticker whose first analysis run hasn't produced a grade yet.
    private var isResearching: Bool {
        guard position.resolvedRiskGrade == nil else { return false }
        let state = position.resolvedAnalysisState
        return state == "queued" || state == "running" || position.analysisStartedAt != nil
    }

    var body: some View {
        HStack(spacing: 8) {
            // Sym
            Text(position.ticker)
                .font(ClavisTypography.clavixMono(13, weight: .bold))
                .tracking(0.3)
                .foregroundColor(.clavixInk)
                .frame(width: 70, alignment: .leading)

            // Price · day
            VStack(alignment: .leading, spacing: 3) {
                Text(currencyDecimal(position.resolvedCurrentPrice))
                    .font(ClavisTypography.clavixMono(13, weight: .semibold))
                    .foregroundColor(.clavixInk)
                Text(dayText)
                    .font(ClavisTypography.clavixMono(10, weight: .semibold))
                    .foregroundColor(dayTone)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // P&L
            VStack(alignment: .trailing, spacing: 3) {
                Text(pnlText)
                    .font(ClavisTypography.clavixMono(13, weight: .semibold))
                    .foregroundColor(pnlColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(pnlPctText)
                    .font(ClavisTypography.clavixMono(10, weight: .regular))
                    .foregroundColor(.clavixInk3)
                    .lineLimit(1)
            }
            .frame(width: 82, alignment: .trailing)

            // Grade · Δ (or a researching indicator for freshly added tickers)
            if isResearching {
                VStack(alignment: .trailing, spacing: 3) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.clavixAccent)
                    Text("Researching")
                        .font(ClavisTypography.clavixMono(7, weight: .bold))
                        .tracking(0.2)
                        .foregroundColor(.clavixAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 60, alignment: .trailing)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    ClavixGradeBadge(grade, size: 18)
                    Text(deltaText)
                        .font(ClavisTypography.clavixMono(10, weight: .semibold))
                        .foregroundColor(deltaColor)
                }
                .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(highlighted ? Color.clavixAccentSoft : Color.clear)
        .overlay(alignment: .leading) {
            if highlighted { Rectangle().fill(Color.clavixAccent).frame(width: 3) }
        }
    }

    private var highlighted: Bool { position.riskTrend == .worsening }

    private var dayTone: Color {
        guard let pct = dayPct else { return .clavixInk3 }
        if pct > 0.05 { return .clavixGood }
        if pct < -0.05 { return .clavixBad }
        return .clavixInk3
    }

    private var dayText: String {
        guard let pct = dayPct else { return "—" }
        return String(format: "%@%.1f%%", pct >= 0 ? "+" : "", pct)
    }

    private var pnlText: String { currencyDecimal(position.unrealizedPL, abbreviate: false) }
    private var pnlColor: Color {
        guard let pnl = position.unrealizedPL else { return .clavixInk3 }
        return pnl >= 0 ? .clavixGood : .clavixBad
    }
    private var pnlPctText: String {
        guard let pct = position.unrealizedPLPercent else { return "—" }
        return String(format: "%@%.1f%%", pct >= 0 ? "+" : "", pct)
    }

    private var deltaText: String {
        guard let delta = position.scoreDelta, delta != 0 else { return "—" }
        return delta > 0 ? "▲ \(delta)" : "▼ \(abs(delta))"
    }

    private var deltaColor: Color {
        guard let delta = position.scoreDelta else { return .clavixInk3 }
        if delta > 0 { return .clavixGood }
        if delta < 0 { return .clavixBad }
        return .clavixInk3
    }

    private func currencyDecimal(_ value: Double?, abbreviate: Bool = false) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = abbreviate ? 0 : 2
        if abbreviate, abs(value) >= 10_000 { formatter.maximumFractionDigits = 0 }
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }
}

private struct SectorHoldingsRow {
    let name: String
    let weightPct: Int
    let grade: String
    let tickers: String
}

// MARK: - Donut chart

/// One wedge of a ClavixDonutChart.
private struct DonutSlice: Identifiable {
    let id: String
    let label: String      // shown big in the center when selected (e.g. "HOOD", "A+")
    let value: Double      // wedge size
    let color: Color
    let caption: String    // center readout sub-line (e.g. "35% · $12,400")
}

private struct DonutSegment: Identifiable {
    let slice: DonutSlice
    let start: Double      // 0...1 cumulative start
    let end: Double        // 0...1 cumulative end
    var id: String { slice.id }
}

/// A single stroked arc of the ring. `centerlineRadius` is the radius of the
/// stroke centerline so the ring stays inside the bounds for any line width.
private struct DonutArc: Shape {
    let startDeg: Double
    let endDeg: Double
    let centerlineRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: centerlineRadius,
            startAngle: .degrees(startDeg),
            endAngle: .degrees(endDeg),
            clockwise: false
        )
        return path
    }
}

/// Interactive donut. Touch (or drag-scrub) a wedge to read its label and
/// detail in the hole — the "hover" affordance for "this is HOOD, 35%".
private struct ClavixDonutChart: View {
    let slices: [DonutSlice]
    let centerPrimary: String
    let centerDetail: String          // static sub-line shown when nothing is selected
    let namespace: String             // distinguishes this donut in the shared selection
    @Binding var selection: String?   // shared "namespace:id" key, nil when nothing selected

    private func key(_ id: String) -> String { "\(namespace):\(id)" }

    private var total: Double { slices.reduce(0) { $0 + $1.value } }

    private var segments: [DonutSegment] {
        guard total > 0 else { return [] }
        var acc = 0.0
        return slices.map { slice in
            let start = acc / total
            acc += slice.value
            return DonutSegment(slice: slice, start: start, end: acc / total)
        }
    }

    private var selected: DonutSlice? {
        guard let selection else { return nil }
        return slices.first { key($0.id) == selection }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let outer = side / 2
            let ring = max(13, outer * 0.34)
            let centerline = outer - ring / 2
            let gap: Double = segments.count > 1 ? 1.4 : 0

            ZStack {
                ForEach(segments) { seg in
                    let isSelected = selection == key(seg.id)
                    let dimmed = selected != nil && !isSelected
                    DonutArc(
                        startDeg: -90 + seg.start * 360 + gap,
                        endDeg: -90 + seg.end * 360 - gap,
                        centerlineRadius: centerline
                    )
                    .stroke(
                        seg.slice.color.opacity(dimmed ? 0.32 : 1),
                        style: StrokeStyle(lineWidth: isSelected ? ring + 6 : ring, lineCap: .butt)
                    )
                }

                VStack(spacing: 2) {
                    Text(selected?.label ?? centerPrimary)
                        .font(ClavisTypography.clavixMono(15, weight: .bold))
                        .tracking(-0.2)
                        .foregroundColor(.clavixInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(selected?.caption ?? centerDetail)
                        .font(ClavisTypography.clavixMono(9, weight: .regular))
                        .tracking(0.3)
                        .foregroundColor(.clavixInk3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                }
                .frame(width: max(0, (outer - ring) * 1.8))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: selection)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        select(at: value.location, center: center, outer: outer, ring: ring)
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func select(at point: CGPoint, center: CGPoint, outer: CGFloat, ring: CGFloat) {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = (dx * dx + dy * dy).squareRoot()
        guard dist >= outer - ring - 10, dist <= outer + 12 else {
            // Tapped off the ring (the hole or outside it) -> reset to default.
            if selection != nil { selection = nil }
            return
        }
        var angle = atan2(dy, dx) * 180 / .pi + 90
        angle = angle.truncatingRemainder(dividingBy: 360)
        if angle < 0 { angle += 360 }
        let frac = angle / 360
        if let seg = segments.first(where: { frac >= $0.start && frac < $0.end }) {
            let newKey = key(seg.id)
            if selection != newKey { selection = newKey }
        }
    }
}

private struct SectorCompositionRow: View {
    let row: SectorHoldingsRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text(row.name)
                    .font(ClavisTypography.inter(15, weight: .semibold))
                    .foregroundColor(.clavixInk)
                    .lineLimit(1)
                Spacer()
                Text("\(row.weightPct)%")
                    .font(ClavisTypography.clavixMono(11, weight: .semibold))
                    .foregroundColor(.clavixInk3)
                ClavixGradeBadge(row.grade, size: 18)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.clavixRule2)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(barTone)
                        .frame(width: geo.size.width * CGFloat(row.weightPct) / 100.0)
                }
            }
            .frame(height: 6)

            Text(row.tickers)
                .font(ClavisTypography.clavixCaption)
                .foregroundColor(.clavixInk3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var barTone: Color {
        switch row.grade {
        case "A+", "A", "A-":
            return .clavixGood
        case "B+", "B":
            return .clavixAccent
        case "B-", "C+", "C", "C-":
            return .clavixWarn
        case "\u{2014}":
            return .clavixInk4
        default:
            return .clavixBad
        }
    }
}

private struct WatchlistRow: View {
    let item: WatchlistItem

    private var dayPct: Double? { item.sharedAnalysis?.dayChangePct }

    private var dayTone: Color {
        guard let pct = dayPct else { return .clavixInk3 }
        if pct > 0.05 { return .clavixGood }
        if pct < -0.05 { return .clavixBad }
        return .clavixInk3
    }

    private var dayText: String {
        guard let pct = dayPct else { return "—" }
        return String(format: "%@%.1f%%", pct >= 0 ? "+" : "", pct)
    }

    private var deltaText: String {
        guard let delta = item.sharedAnalysis?.scoreDelta, delta != 0 else { return "—" }
        return delta > 0 ? "▲ \(delta)" : "▼ \(abs(delta))"
    }

    private var deltaColor: Color {
        guard let delta = item.sharedAnalysis?.scoreDelta else { return .clavixInk3 }
        if delta > 0 { return .clavixGood }
        if delta < 0 { return .clavixBad }
        return .clavixInk3
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.ticker)
                    .font(ClavisTypography.clavixMono(13, weight: .bold))
                    .foregroundColor(.clavixInk)
                Text(item.resolvedCompanyName ?? "Tracked symbol")
                    .font(ClavisTypography.clavixCaption)
                    .foregroundColor(.clavixInk3)
                    .lineLimit(1)
            }
            .frame(width: 84, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.price.map { currency($0) } ?? "—")
                    .font(ClavisTypography.clavixMono(13, weight: .semibold))
                    .foregroundColor(.clavixInk)
                Text(dayText)
                    .font(ClavisTypography.clavixMono(10, weight: .semibold))
                    .foregroundColor(dayTone)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                ClavixGradeBadge(item.resolvedGrade ?? "—", size: 18)
                Text(deltaText)
                    .font(ClavisTypography.clavixMono(10, weight: .semibold))
                    .foregroundColor(deltaColor)
            }
            .frame(width: 60, alignment: .trailing)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }
}

private struct SearchResultRow: View {
    let result: TickerSearchResult
    let isWatchlisted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.ticker)
                    .font(ClavisTypography.clavixMono(13, weight: .bold))
                    .foregroundColor(.clavixInk)
                Text(result.resolvedCompanyName ?? result.companyName)
                    .font(ClavisTypography.clavixCaption)
                    .foregroundColor(.clavixInk3)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    if !result.isSupported {
                        SearchTag(text: "OUTSIDE", foreground: .clavixWarnInk, background: .clavixWarnSoft)
                    }

                    if isWatchlisted {
                        SearchTag(text: "WATCHING", foreground: .clavixAccentInk, background: .clavixAccentSoft)
                    }
                }

                HStack(spacing: 8) {
                    Text(result.price.map { currency($0) } ?? "—")
                        .font(ClavisTypography.clavixMono(11, weight: .semibold))
                        .foregroundColor(.clavixInk3)
                    ClavixGradeBadge(result.resolvedGrade ?? "—", size: 18)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }
}

private struct SearchTag: View {
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(ClavisTypography.clavixMono(9, weight: .bold))
            .foregroundColor(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

private struct HoldingDeleteSheet: View {
    let ticker: String
    let onDelete: () -> Void
    let onKeep: () -> Void

    var body: some View {
        ClavixScreen(eyebrow: ticker, title: "Remove position") {
            ClavixCard(fill: .clavixBadSoft) {
                Text("Removing this position removes portfolio context for \(ticker). Ticker-level risk data remains available through Search.")
                    .font(ClavisTypography.inter(14, weight: .regular))
                    .foregroundColor(.clavixInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HoldingsSheetButton(
                title: "Remove position",
                fill: .clavixBad,
                action: onDelete
            )

            HoldingsSheetButton(
                title: "Keep position",
                fill: .clavixPaper,
                foreground: .clavixInk,
                bordered: true,
                action: onKeep
            )
        }
    }
}

struct HoldingsEmptyState: View {
    let onAddPosition: () -> Void

    var body: some View {
        ClavixInlineNoticeCard(
            eyebrow: "Portfolio",
            title: "Add your first holding",
            message: "Start with the positions you follow most closely. Clavix builds the Morning Report around what actually sits in your book.",
            footnote: "If you are not ready to add a holding yet, you can still track names from Search and the Watchlist.",
            glyph: "briefcase",
            buttonTitle: "Add your first holding",
            action: onAddPosition
        )
    }
}

private struct HoldingsAddMethodSheet: View {
    @ObservedObject var viewModel: HoldingsViewModel
    @ObservedObject var brokerageViewModel: BrokerageViewModel
    @Binding var selectedTab: Int
    @Environment(\.dismiss) private var dismiss
    @State private var showManualSheet = false
    @State private var manualSaveCompleted = false

    var body: some View {
        ClavixScreen(eyebrow: "Choose a method", title: "Add position") {
            HoldingsMethodCard(
                title: "Search the universe",
                description: "Type a ticker or company name. Available for tracked names.",
                icon: "magnifyingglass"
            ) {
                selectedTab = 2
                dismiss()
            }

            if FeatureFlags.brokerageEnabled {
                HoldingsMethodCard(
                    title: "Refresh from your brokerage",
                    description: brokerageViewModel.isConnected
                        ? "Connected brokerage can update share counts and cost data."
                        : "Connect your brokerage to pull positions read-only.",
                    icon: "arrow.clockwise",
                    badge: brokerageViewModel.isConnected ? "LIVE" : nil
                ) {
                    Task {
                        if brokerageViewModel.isConnected {
                            await brokerageViewModel.syncNow(refreshRemote: true)
                            await viewModel.refreshHoldings()
                        } else {
                            await brokerageViewModel.startConnect()
                        }
                    }
                }
            }

            HoldingsMethodCard(
                title: "Enter manually",
                description: "Type a ticker and how many shares you hold.",
                icon: "plus"
            ) {
                showManualSheet = true
            }
        }
        .sheet(isPresented: $showManualSheet, onDismiss: {
            if manualSaveCompleted {
                manualSaveCompleted = false
                dismiss()
            }
        }) {
            HoldingsAddSheet(viewModel: viewModel, onComplete: {
                manualSaveCompleted = true
            })
        }
    }
}

private struct HoldingsMethodCard: View {
    let title: String
    let description: String
    let icon: String
    var badge: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ClavixCard {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .frame(width: 28)
                        .foregroundColor(.clavixAccent)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(title)
                                .font(ClavisTypography.inter(15, weight: .semibold))
                                .foregroundColor(.clavixInk)
                            if let badge {
                                Text(badge)
                                    .font(ClavisTypography.clavixMono(9, weight: .bold))
                                    .foregroundColor(.clavixAccentInk)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.clavixAccentSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            }
                        }

                        Text(description)
                            .font(ClavisTypography.clavixCaption)
                            .foregroundColor(.clavixInk2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.clavixInk4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HoldingsAddSheet: View {
    @ObservedObject var viewModel: HoldingsViewModel
    @Environment(\.dismiss) private var dismiss
    var onComplete: (() -> Void)? = nil

    @State private var ticker = ""
    @State private var companyName = ""
    @State private var tickerSuggestions: [TickerSearchResult] = []
    @State private var isSearchingSuggestions = false
    @State private var tickerError: String?
    @State private var selectedTickerResult: TickerSearchResult?
    @State private var shares = ""
    @State private var resolveTickerTask: Task<Void, Never>?

    private var trimmedTicker: String {
        ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// A tracked-universe ticker the user picked from suggestions (or exact match).
    private var hasSupportedSelection: Bool { selectedTickerResult != nil }

    /// The user typed a ticker that isn't in our tracked list and there are no
    /// pending suggestions. We can still add it and start researching it.
    private var isResearchCandidate: Bool {
        !hasSupportedSelection
            && !trimmedTicker.isEmpty
            && !isSearchingSuggestions
            && tickerSuggestions.isEmpty
            && tickerError == nil
    }

    private var isValid: Bool {
        (hasSupportedSelection || isResearchCandidate)
            && !isDuplicateHeld
            && (Double(shares) ?? 0) > 0
    }

    private var isDuplicateHeld: Bool {
        viewModel.holdings.contains { $0.ticker.caseInsensitiveCompare(trimmedTicker) == .orderedSame }
    }

    var body: some View {
        ClavixScreen(
            eyebrow: "Manual entry",
            title: "Add a holding",
            trailing: AnyView(
                Button("Close") { dismiss() }
                    .font(ClavisTypography.clavixMono(10, weight: .semibold))
                    .foregroundColor(.clavixAccent)
                    .buttonStyle(.plain)
            )
        ) {
            // Ticker + live autocomplete (suggestions form directly beneath the field)
            VStack(alignment: .leading, spacing: 8) {
                ClavixEyebrow("Ticker")
                entryField(title: "Search ticker or company", text: $ticker, keyboard: .default, autocapitalized: true)
                    .onChange(of: ticker) { _, newValue in
                        resolveTickerTask?.cancel()
                        selectedTickerResult = nil
                        resolveTickerTask = Task { await resolveTicker(newValue) }
                    }

                if isSearchingSuggestions {
                    HStack(spacing: 8) {
                        ProgressView().tint(.clavixInk3).controlSize(.small)
                        Text("Searching…")
                            .font(ClavisTypography.clavixCaption)
                            .foregroundColor(.clavixInk3)
                        Spacer()
                    }
                    .padding(.top, 2)
                }

                if !tickerSuggestions.isEmpty {
                    ClavixCard(padding: 0, fill: .clavixPaper) {
                        VStack(spacing: 0) {
                            ForEach(Array(tickerSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                                Button(action: { applySuggestion(suggestion) }) {
                                    SearchResultRow(result: suggestion, isWatchlisted: false)
                                }
                                .buttonStyle(.plain)

                                if index < tickerSuggestions.count - 1 {
                                    Divider().overlay(Color.clavixRule)
                                }
                            }
                        }
                    }
                }

                if hasSupportedSelection, !companyName.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.clavixGood)
                        Text("\(trimmedTicker) · \(companyName)")
                            .font(ClavisTypography.clavixCaption)
                            .foregroundColor(.clavixInk2)
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }
            }

            // Shares
            VStack(alignment: .leading, spacing: 8) {
                ClavixEyebrow("Shares")
                entryField(title: "Number of shares", text: $shares, keyboard: .decimalPad)
            }

            if let tickerError {
                ClavixCard(fill: .clavixBadSoft) {
                    Text(tickerError.sanitizedDisplayText)
                        .font(ClavisTypography.inter(14, weight: .regular))
                        .foregroundColor(.clavixInk2)
                }
            }

            if isDuplicateHeld {
                ClavixCard(fill: .clavixAccentSoft) {
                    Text("\(trimmedTicker) is already in your holdings.")
                        .font(ClavisTypography.inter(14, weight: .regular))
                        .foregroundColor(.clavixAccentInk)
                }
            }

            if isResearchCandidate, !isDuplicateHeld {
                ClavixCard(fill: .clavixWarnSoft) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(trimmedTicker) isn't tracked yet")
                            .font(ClavisTypography.inter(15, weight: .semibold))
                            .foregroundColor(.clavixInk)
                        Text("Add it and Clavix starts researching it: scoring all five risk dimensions and pulling its news. Data may be limited while research is underway, and it becomes fully tracked from here on.")
                            .font(ClavisTypography.inter(13, weight: .regular))
                            .foregroundColor(.clavixInk2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HoldingsSheetButton(
                title: isResearchCandidate ? "Add & research \(trimmedTicker)" : "Add holding",
                isEnabled: isValid,
                action: {
                    Task { await submit() }
                }
            )
        }
    }

    private func entryField(
        title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        autocapitalized: Bool = false
    ) -> some View {
        TextField(title, text: text, prompt: Text(title).foregroundColor(.clavixInk3))
            .font(ClavisTypography.inter(15, weight: .regular))
            .foregroundColor(.clavixInk)
            .textInputAutocapitalization(autocapitalized ? .characters : .never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(Color.clavixPaper2)
            .overlay(
                RoundedRectangle(cornerRadius: ClavixLayout.controlRadius)
                    .stroke(Color.clavixRule, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous))
    }

    private func resolveTicker(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            tickerSuggestions = []
            tickerError = nil
            companyName = ""
            selectedTickerResult = nil
            return
        }

        isSearchingSuggestions = true
        do {
            try await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let results = try await viewModel.searchTickers(query: trimmed, limit: 8)
            guard !Task.isCancelled else { return }

            tickerError = nil
            let exactMatch = results.first { $0.ticker.caseInsensitiveCompare(trimmed) == .orderedSame }
            if let exactMatch {
                applySuggestion(exactMatch)
                tickerSuggestions = []
            } else {
                // No exact match. Show near matches if any; otherwise the
                // research-candidate path lets the user add it as untracked.
                tickerSuggestions = results
                companyName = ""
                selectedTickerResult = nil
            }
        } catch is CancellationError {
            return
        } catch {
            tickerSuggestions = []
            companyName = ""
            selectedTickerResult = nil
            tickerError = "Unable to validate ticker right now."
        }
        isSearchingSuggestions = false
    }

    private func applySuggestion(_ suggestion: TickerSearchResult) {
        ticker = suggestion.ticker
        companyName = suggestion.resolvedCompanyName ?? suggestion.companyName
        selectedTickerResult = suggestion
        tickerError = nil
    }

    private func submit() async {
        guard let sharesValue = Double(shares), sharesValue > 0 else { return }
        let target = hasSupportedSelection ? (selectedTickerResult?.ticker ?? trimmedTicker) : trimmedTicker
        await viewModel.addHolding(
            ticker: target.uppercased(),
            shares: sharesValue,
            purchasePrice: 0,
            allowOutsideUniverse: !hasSupportedSelection
        )
        if viewModel.errorMessage == nil {
            // Signal success so the parent method-picker sheet can also dismiss.
            // onComplete sets a flag on HoldingsAddMethodSheet; its onDismiss
            // handler then calls dismiss() to close the method picker too.
            onComplete?()
            dismiss()
        }
    }
}

private struct HoldingsSheetButton: View {
    let title: String
    var isEnabled: Bool = true
    var fill: Color = .clavixInk
    var foreground: Color? = nil
    var bordered: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ClavisTypography.inter(15, weight: .semibold))
                .foregroundColor(isEnabled ? (foreground ?? .clavixPaper) : .clavixInk4)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous)
                        .stroke(bordered ? Color.clavixRule : Color.clear, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.controlRadius, style: .continuous))
                .opacity(isEnabled ? 1 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct AddPositionProgressView: View {
    @ObservedObject var viewModel: HoldingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: ClavisTheme.extraLargeSpacing) {
                Spacer()

                ClavixCard(fill: .clavixPaper) {
                    VStack(spacing: ClavisTheme.mediumSpacing) {
                        Image(systemName: viewModel.progressValue >= 1.0 ? "checkmark" : "chart.line.uptrend.xyaxis")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(iconColor)

                        VStack(spacing: ClavisTheme.smallSpacing) {
                            Text(primaryProgressMessage)
                                .font(ClavisTypography.h2)
                                .foregroundColor(.clavixInk)
                                .multilineTextAlignment(.center)

                            Text(viewModel.progressMessage)
                                .font(ClavisTypography.body)
                                .foregroundColor(.clavixInk3)
                                .multilineTextAlignment(.center)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.clavixRule)
                                    .frame(height: 4)
                                Rectangle()
                                    .fill(iconColor)
                                    .frame(width: geo.size.width * CGFloat(viewModel.progressValue), height: 4)
                            }
                        }
                        .frame(height: 4)

                        Text(progressStageText)
                            .font(ClavisTypography.label)
                            .foregroundColor(.clavixInk3)
                    }
                }

                Spacer()
            }
            .padding(ClavisTheme.screenPadding)
            .background(ClavisAtmosphereBackground())
            .navigationTitle(viewModel.pendingTicker ?? "New Holding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.clavixInk3)
                }
            }
        }
    }

    private var iconColor: Color {
        if viewModel.progressValue >= 1.0 { return .good }
        if viewModel.progressMessage.lowercased().contains("failed") { return .bad }
        if viewModel.progressMessage.lowercased().contains("limited") { return .warn }
        return .clavixAccent
    }

    private var primaryProgressMessage: String {
        if viewModel.progressValue >= 1.0 { return "Holding ready" }
        return "Adding \(viewModel.pendingTicker ?? "holding")"
    }

    private var progressStageText: String {
        if viewModel.progressValue >= 1.0 { return "POSITION READY" }
        return viewModel.activeRun?.currentStageMessage?.uppercased() ?? "ANALYSIS IN PROGRESS"
    }
}

private struct HoldingsUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ClavixScreen(eyebrow: "Subscription", title: "Access required") {
            ClavixCard(fill: .clavixAccentSoft) {
                Text("Start your trial or restore your subscription to track positions, receive the morning brief, and view full history.")
                    .font(ClavisTypography.inter(14, weight: .regular))
                    .foregroundColor(.clavixAccentInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HoldingsSheetButton(
                title: "View subscription",
                fill: .clavixAccent,
                action: { dismiss() }
            )

            HoldingsSheetButton(
                title: "Manage positions",
                fill: .clavixPaper,
                foreground: .clavixInk,
                bordered: true,
                action: { dismiss() }
            )
        }
    }
}
import SwiftUI

/// First-time portfolio setup sheet.
/// Shown instead of the method picker when the user has zero holdings.
/// Lets the user enter up to 5 tickers at once, then plays a short
/// "Scoring your positions" animation before dismissing to the Holdings tab.
struct QuickPortfolioSetupSheet: View {

    @ObservedObject var viewModel: HoldingsViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    struct Entry: Identifiable {
        let id = UUID()
        var ticker = ""
        var shares = ""
    }

    @State private var entries: [Entry] = [Entry(), Entry(), Entry()]
    @State private var phase: Phase = .input
    @State private var dimensionIndex = 0
    @State private var cycleTimer: Timer?

    enum Phase { case input, analyzing }

    // MARK: - Data

    private let dimensions: [(code: String, name: String)] = [
        ("FIN",  "Financial Health"),
        ("NEWS", "News Sentiment"),
        ("MAC",  "Macro Exposure"),
        ("SEC",  "Sector Exposure"),
        ("VOL",  "Volatility"),
    ]

    private var validEntries: [(ticker: String, shares: Double)] {
        entries.compactMap { e in
            let t = e.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !t.isEmpty else { return nil }
            return (t, Double(e.shares) ?? 1.0)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.clavixPage.ignoresSafeArea()
            switch phase {
            case .input:     inputView.transition(.opacity)
            case .analyzing: analyzingView.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: phase)
    }

    // MARK: - Input screen

    private var inputView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Header
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Set up your book")
                            .font(ClavisTypography.clavixSerif(30, weight: .medium))
                            .foregroundColor(.clavixInk)
                        Text("Add the positions you hold. Clavix scores each one across five risk dimensions every morning.")
                            .font(ClavisTypography.inter(14, weight: .regular))
                            .foregroundColor(.clavixInk2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 28)

                    // Column labels
                    HStack(spacing: 10) {
                        Text("TICKER")
                            .font(ClavisTypography.clavixMono(9, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(.clavixInk3)
                            .frame(width: 88, alignment: .center)
                        Text("SHARES")
                            .font(ClavisTypography.clavixMono(9, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(.clavixInk3)
                            .padding(.leading, 12)
                        Spacer()
                    }
                    .padding(.bottom, 8)

                    // Entry rows
                    VStack(spacing: 8) {
                        ForEach($entries) { $entry in
                            HStack(spacing: 10) {
                                TextField(
                                    "AAPL",
                                    text: $entry.ticker,
                                    prompt: Text("AAPL").foregroundColor(.clavixInk3)
                                )
                                    .font(ClavisTypography.clavixMono(14, weight: .bold))
                                    .foregroundColor(.clavixInk)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .keyboardType(.asciiCapable)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 88, height: 50)
                                    .background(Color.clavixPaper2)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.clavixRule, lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                TextField(
                                    "Shares (optional)",
                                    text: $entry.shares,
                                    prompt: Text("Shares (optional)").foregroundColor(.clavixInk3)
                                )
                                    .font(ClavisTypography.inter(14, weight: .regular))
                                    .foregroundColor(.clavixInk)
                                    .keyboardType(.decimalPad)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .padding(.horizontal, 12)
                                    .background(Color.clavixPaper2)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.clavixRule, lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(.bottom, 14)

                    // Add row button
                    if entries.count < 5 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                entries.append(Entry())
                            }
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
                    }

                    Spacer().frame(height: 28)

                    // Primary CTA
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Analyze my portfolio")
                                .font(ClavisTypography.inter(15, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(validEntries.isEmpty ? .clavixInk3 : .clavixPaper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(validEntries.isEmpty ? Color.clavixPaper2 : Color.clavixInk)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(validEntries.isEmpty)
                    .padding(.bottom, 12)

                    // Skip link
                    Button("I'll add positions later") { dismiss() }
                        .font(ClavisTypography.inter(13, weight: .regular))
                        .foregroundColor(.clavixInk3)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .background(Color.clavixPage.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                        .font(ClavisTypography.inter(13, weight: .regular))
                        .foregroundColor(.clavixInk3)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Analyzing screen

    private var analyzingView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Wordmark
                HStack(spacing: 8) {
                    Image("clavix_logo")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.clavixInk)
                        .frame(width: 22, height: 22)
                    Text("CLAVIX")
                        .font(ClavisTypography.clavixMono(12, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(.clavixInk)
                }

                // Headline
                VStack(spacing: 6) {
                    Text("Scoring your positions")
                        .font(ClavisTypography.clavixSerif(28, weight: .medium))
                        .foregroundColor(.clavixInk)
                        .multilineTextAlignment(.center)
                    Text("across five risk dimensions")
                        .font(ClavisTypography.inter(15, weight: .regular))
                        .foregroundColor(.clavixInk2)
                }

                // Cycling dimension chips
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(0..<dimensions.count, id: \.self) { i in
                            Text(dimensions[i].code)
                                .font(ClavisTypography.clavixMono(9, weight: .bold))
                                .tracking(0.4)
                                .foregroundColor(i == dimensionIndex ? .clavixPaper : .clavixInk3)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(i == dimensionIndex ? Color.clavixInk : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(i == dimensionIndex ? Color.clear : Color.clavixRule, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    Text(dimensions[dimensionIndex].name)
                        .font(ClavisTypography.inter(13, weight: .regular))
                        .foregroundColor(.clavixInk3)
                        .frame(height: 18)
                        .id(dimensionIndex)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal:   .opacity.combined(with: .move(edge: .top))
                            )
                        )
                        .animation(.easeInOut(duration: 0.22), value: dimensionIndex)
                }
            }

            Spacer()

            Text("This usually takes a moment.")
                .font(ClavisTypography.inter(12, weight: .regular))
                .foregroundColor(.clavixInk4)
                .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity)
        .onAppear { startCycle() }
        .onDisappear { cycleTimer?.invalidate() }
    }

    // MARK: - Logic

    private func submit() async {
        withAnimation { phase = .analyzing }

        let toSave = validEntries
        Task {
            for (ticker, shares) in toSave {
                await viewModel.addHolding(
                    ticker: ticker,
                    shares: shares,
                    purchasePrice: 0,
                    allowOutsideUniverse: true
                )
            }
            await viewModel.loadHoldings()
        }
    }

    private func startCycle() {
        var tick = 0
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { timer in
            tick += 1
            if tick < dimensions.count {
                withAnimation(.easeInOut(duration: 0.22)) {
                    dimensionIndex = tick
                }
            } else {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - First-run getting-started checklist

struct GettingStartedChecklistCard: View {
    let openedBreakdown: Bool
    let viewedToday: Bool
    let trackedName: Bool
    let onOpenBreakdown: () -> Void
    let onMorningBrief: () -> Void
    let onTrackName: () -> Void
    let onDismiss: () -> Void

    private var doneCount: Int {
        [openedBreakdown, viewedToday, trackedName].filter { $0 }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("GET STARTED")
                    .font(ClavisTypography.clavixMono(10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.clavixAccent)
                Spacer()
                Text("\(doneCount) / 3")
                    .font(ClavisTypography.clavixMono(10, weight: .bold))
                    .foregroundColor(.clavixInk3)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.clavixInk4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.clavixPaper2)
            Rectangle().fill(Color.clavixRule).frame(height: 1)

            ChecklistTaskRow(
                done: openedBreakdown,
                title: "See your full risk breakdown",
                subtitle: "Open a position's five-dimension view",
                action: onOpenBreakdown
            )
            Rectangle().fill(Color.clavixRule).frame(height: 1)
            ChecklistTaskRow(
                done: viewedToday,
                title: "Read your morning brief",
                subtitle: "Your daily risk report on the Today tab",
                action: onMorningBrief
            )
            Rectangle().fill(Color.clavixRule).frame(height: 1)
            ChecklistTaskRow(
                done: trackedName,
                title: "Track a name to watch",
                subtitle: "Add a ticker from Search",
                action: onTrackName
            )
        }
        .background(Color.clavixPaper)
        .overlay(Rectangle().stroke(Color.clavixRule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct ChecklistTaskRow: View {
    let done: Bool
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: { if !done { action() } }) {
            HStack(spacing: 12) {
                ZStack {
                    if done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.clavixGood)
                    } else {
                        Circle()
                            .stroke(Color.clavixInk4, lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ClavisTypography.inter(14, weight: .semibold))
                        .foregroundColor(done ? .clavixInk3 : .clavixInk)
                        .strikethrough(done, color: .clavixInk3)
                    Text(subtitle)
                        .font(ClavisTypography.clavixMono(9, weight: .regular))
                        .tracking(0.3)
                        .foregroundColor(.clavixInk3)
                }

                Spacer(minLength: 0)

                if !done {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.clavixInk4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(done)
    }
}
