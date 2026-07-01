import SwiftUI

struct TickerDetailView: View {
    let ticker: String
    let positionId: String?
    #if DEBUG
    let debugFixture: TickerDetailDebugFixture?
    let debugScrollTarget: String?
    #endif

    @Environment(\.dismiss) private var dismiss
    @State private var detail: TickerDetailResponse?
    @State private var methodology: MethodologyResponse?
    @State private var priceHistory: [PricePoint] = []
    @State private var scoreHistory: [ScoreHistoryPoint] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var isRefreshingTicker = false
    @State private var isMutatingWatchlist = false
    @State private var watchlistOverride: Bool?
    @State private var selectedArticle: MethodologyArticle?
    @State private var showAddHoldingSheet = false
    @State private var showAllArticles = false
    @State private var aboutExpanded = false
    @State private var scoreHistoryDimensions: Set<String> = []
    @State private var selectedHistoryPeriod: TickerHistoryPeriod = .threeMonths
    @State private var showWatchlistLimitPaywall = false

    #if DEBUG
    init(
        ticker: String,
        positionId: String? = nil,
        debugFixture: TickerDetailDebugFixture? = nil,
        debugScrollTarget: String? = nil
    ) {
        self.ticker = ticker
        self.positionId = positionId
        self.debugFixture = debugFixture
        self.debugScrollTarget = debugScrollTarget
    }
    #else
    init(
        ticker: String,
        positionId: String? = nil
    ) {
        self.ticker = ticker
        self.positionId = positionId
    }
    #endif

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                    if let errorMessage, detail == nil {
                        DashboardErrorCard(message: errorMessage)
                    } else if isLoading && detail == nil {
                        loadingState
                    } else if let detail {
                        content(detail)
                    } else {
                        DashboardErrorCard(message: "Ticker detail unavailable.")
                    }
                }
                .padding(.horizontal, ClavisTheme.screenPadding)
                .padding(.top, ClavisTheme.sectionSpacing)
                .padding(.bottom, ClavisTheme.extraLargeSpacing)
            }
            .background(Color.clavixPage.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                topHeader {
                    guard hasExecutiveSummary else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("executive-summary", anchor: .top)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                #if DEBUG
                if let debugFixture {
                    apply(debugFixture)
                    if let debugScrollTarget {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        withAnimation(.none) {
                            proxy.scrollTo(debugScrollTarget, anchor: .top)
                        }
                    }
                } else {
                    await reloadAll()
                }
                #else
                await reloadAll()
                #endif
            }
            .refreshable {
                #if DEBUG
                if let debugFixture {
                    apply(debugFixture)
                    if let debugScrollTarget {
                        withAnimation(.none) {
                            proxy.scrollTo(debugScrollTarget, anchor: .top)
                        }
                    }
                } else {
                    await reloadAll()
                }
                #else
                await reloadAll()
                #endif
            }
        }
        .sheet(item: $selectedArticle) { article in
            ArticleDetailSheet(
                article: article,
                ticker: ticker,
                portfolioContext: articlePortfolioContext(detail: detail)
            )
        }
        .sheet(isPresented: $showAddHoldingSheet) {
            TickerAddHoldingSheet(
                ticker: ticker,
                companyName: detail?.profile.companyName,
                onComplete: {
                    showAddHoldingSheet = false
                    Task { await reloadAll() }
                }
            )
            .presentationBackground(Color.clavixPage)
        }
        .sheet(isPresented: $showWatchlistLimitPaywall) {
            PaywallView(triggerContext: .watchlistLimit)
                .environmentObject(SubscriptionManager.shared)
        }
    }

    private func topHeader(onSummaryTap: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.clavixInk)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(detail?.profile.companyName ?? ticker)
                    .font(ClavisTypography.clavixSerif(17, weight: .medium))
                    .foregroundColor(.clavixInk)
                    .lineLimit(1)
                Text(ticker)
                    .font(ClavisTypography.clavixMono(11, weight: .bold))
                    .foregroundColor(.clavixAccent)
            }

            Spacer(minLength: 6)

            HStack(spacing: 7) {
                if hasExecutiveSummary {
                    Button(action: onSummaryTap) {
                        Text("Summary")
                            .font(ClavisTypography.clavixMono(10, weight: .semibold))
                            .foregroundColor(.clavixAccent)
                            .padding(.horizontal, 8)
                            .frame(height: 30)
                            .background(Color.clavixPaper2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.clavixRule, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                watchlistNavButton
                holdingsNavButton
            }
        }
        .padding(.horizontal, ClavixLayout.pad)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.clavixPage.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.clavixRule)
                .frame(height: 1)
        }
    }

    private var hasExecutiveSummary: Bool {
        guard let summary = detail?.sharedAnalysis?.executiveSummaryBreakdown else {
            return false
        }
        return summary.hasAnyContent
    }

    @ViewBuilder
    private func content(_ detail: TickerDetailResponse) -> some View {
        if isOutsideUniverse(detail) {
            outsideUniverseBanner
        }
        heroSection(detail)
            .id("hero")
        priceSection(detail)
            .id("price")
        aboutSection(detail)
            .id("about")
        riskDimensionsSection(detail)
            .id("dimensions")
        if !detail.profile.isETF {
            driversSection(detail)
                .id("drivers")
        }
        executiveSummarySection(detail)
            .id("executive-summary")
        // ETFs do not ingest news — no recent-news section for funds.
        if !detail.profile.isETF {
            recentNewsSection(detail)
                .id("recent-news")
        }
    }

    private func isOutsideUniverse(_ detail: TickerDetailResponse) -> Bool {
        if detail.sharedAnalysis?.summary.outsideUniverse == true { return true }
        if detail.sharedAnalysis?.summary.isSupported == false { return true }
        return false
    }

    private var outsideUniverseBanner: some View {
        ClavixCard(fill: .clavixWarnSoft) {
            VStack(alignment: .leading, spacing: 6) {
                Text("OUTSIDE TRACKED UNIVERSE")
                    .font(ClavisTypography.clavixMono(10, weight: .bold))
                    .tracking(0.7)
                    .foregroundColor(.clavixWarnInk)
                Text("This ticker isn't in the Clavix tracked universe. Risk data may be limited until coverage is added.")
                    .font(ClavisTypography.clavixCaption)
                    .foregroundColor(.clavixWarnInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scoreHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            hifiSectionHeader(eyebrow: "Composite · \(selectedHistoryPeriod.label)", title: "Score history")
            ClavixCard(fill: .clavixPaper) {
                let snapshots = filteredScoreSnapshots
                if snapshots.count >= 2 {
                    VStack(alignment: .leading, spacing: 10) {
                        HistoryPeriodChips(selected: $selectedHistoryPeriod)
                        HStack(spacing: 6) {
                            ForEach(scoreHistoryToggles, id: \.key) { toggle in
                                Button(action: { toggleScoreDimension(toggle.key) }) {
                                    ClavixPill(label: toggle.label, active: scoreHistoryDimensions.contains(toggle.key) || (toggle.key == "composite" && scoreHistoryDimensions.isEmpty))
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                        ScoreHistoryChart(
                            snapshots: snapshots,
                            showAllDimensions: !scoreHistoryDimensions.isEmpty,
                            toggledDimensions: $scoreHistoryDimensions
                        )
                    }
                } else {
                    Text("New: score history requires at least 2 days of data.")
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixInk3)
                }
            }
        }
    }

    private var scoreHistoryToggles: [(key: String, label: String)] {
        [
            ("composite", "Composite"),
            ("news_sentiment", "News"),
            ("macro_exposure", "Macro"),
            ("volatility", "Vol")
        ]
    }

    private func toggleScoreDimension(_ key: String) {
        if key == "composite" {
            scoreHistoryDimensions = []
            return
        }
        if scoreHistoryDimensions.contains(key) {
            scoreHistoryDimensions.remove(key)
        } else {
            scoreHistoryDimensions.insert(key)
        }
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
            ClavixInlineNoticeCard(
                eyebrow: "Coverage",
                title: "Building \(ticker) coverage",
                message: "Clavix is pulling the latest rating, dimensions, and scored news for this name.",
                footnote: "If market data is thin or the name sits outside the tracked universe, the app should say so instead of guessing.",
                glyph: "chart.line.text.clipboard"
            )
            ClavisLoadingCard(title: "Loading \(ticker)", subtitle: "Pulling the latest rating, dimensions, and news.")
            ClavisLoadingCard(title: "Loading dimensions", subtitle: "Fetching methodology inputs and score components.")
            ClavisLoadingCard(title: "Loading recent news", subtitle: "Scoring the latest article set for this ticker.")
        }
    }

    private func heroSection(_ detail: TickerDetailResponse) -> some View {
        ClavixCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        ClavixEyebrow("Risk rating")

                        Spacer(minLength: 8)

                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            ClavixGradeBadge(displayGrade, size: 40)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(displayScoreText)
                                    .font(ClavisTypography.clavixMono(28, weight: .semibold))
                                    .tracking(-0.5)
                                    .foregroundColor(.clavixInk)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .layoutPriority(1)
                                Text("/100")
                                    .font(ClavisTypography.clavixMono(12, weight: .regular))
                                    .foregroundColor(.clavixInk3)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }

                        Spacer(minLength: 8)

                        VStack(alignment: .leading, spacing: 6) {
                            sessionDeltaLine(detail)
                            if isHeld {
                                todayChangeLine(detail)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)

                    Spacer(minLength: 8)

                    if hasAnyDimensionScore {
                        TickerRadarChart(dimensions: radarDimensions, size: 136)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "chart.pie")
                                .font(.system(size: 22))
                                .foregroundColor(.clavixInk4)
                            Text("Radar pending")
                                .font(ClavisTypography.clavixMono(9, weight: .regular))
                                .foregroundColor(.clavixInk4)
                        }
                        .frame(width: 136, height: 136)
                    }
                }
                .padding(16)
                .frame(height: 168)

                if displayScoreValue == nil && filteredPriceHistory.count < 2 {
                    Rectangle().fill(Color.clavixRule2).frame(height: 1)
                    ratingPendingCard
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private func priceSection(_ detail: TickerDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ClavixCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            ClavixEyebrow("Price · \(selectedHistoryPeriod.label)")
                            Text(priceLineText(detail))
                                .font(ClavisTypography.clavixMono(14, weight: .semibold))
                                .foregroundColor(priceLineColor(detail))
                        }
                        Spacer(minLength: 8)
                        HistoryPeriodChips(selected: $selectedHistoryPeriod, compact: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    TickerPriceChart(
                        prices: filteredPriceHistory,
                        tone: priceLineColor(detail)
                    )
                    .padding(.leading, 16)
                    .padding(.trailing, 6)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    /// "▲6 vs prior session" — same arrow-plus-caption pattern as the Morning Report's
    /// portfolio-rating masthead delta, so the two rating cards read consistently.
    @ViewBuilder
    private func sessionDeltaLine(_ detail: TickerDetailResponse) -> some View {
        if let delta = honestScoreDelta(detail), delta != 0 {
            heroDeltaLine(isUp: delta > 0, magnitude: "\(abs(delta))", suffix: "vs prior session", color: delta > 0 ? .clavixGood : .clavixBad)
        } else {
            Text("No change vs prior session")
                .font(ClavisTypography.clavixMono(11, weight: .regular))
                .foregroundColor(.clavixInk3)
        }
    }

    /// "▲7.68% today" — percent-only day change using the same delta-line style. The
    /// dollar figure lives in the Price card below, so this stays percent-only to avoid
    /// restating the same number twice on one screen.
    @ViewBuilder
    private func todayChangeLine(_ detail: TickerDetailResponse) -> some View {
        if let price = latestPrice, let previousClose = detail.latestPrice.previousClose, previousClose != 0, price != previousClose {
            let pct = abs(((price - previousClose) / previousClose) * 100)
            heroDeltaLine(isUp: price > previousClose, magnitude: String(format: "%.2f%%", pct), suffix: "today", color: price > previousClose ? .clavixGood : .clavixBad)
        } else {
            Text("Flat today")
                .font(ClavisTypography.clavixMono(11, weight: .regular))
                .foregroundColor(.clavixInk3)
        }
    }

    private func heroDeltaLine(isUp: Bool, magnitude: String, suffix: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 9, weight: .bold))
            Text(magnitude)
                .font(ClavisTypography.clavixMono(14, weight: .bold))
            Text(suffix)
                .font(ClavisTypography.clavixMono(11, weight: .regular))
                .foregroundColor(.clavixInk3)
        }
        .foregroundColor(color)
    }

    private func honestScoreDelta(_ detail: TickerDetailResponse) -> Int? {
        detail.sharedAnalysis?.summary.scoreDelta
    }

    private func dataFreshnessLine(_ detail: TickerDetailResponse) -> some View {
        let asOf = detail.freshness.analysisAsOf
        let label: String
        if let asOf {
            let age = -asOf.timeIntervalSinceNow
            if age < 3600 {
                label = "Updated \(Int(age / 60))m ago"
            } else if age < 86400 {
                label = "Updated \(Int(age / 3600))h ago"
            } else {
                label = "Updated \(Int(age / 86400))d ago"
            }
        } else {
            label = "Update time unavailable"
        }
        let isStale = asOf.map { -$0.timeIntervalSinceNow > 86400 } ?? false
        return Text(label)
            .font(ClavisTypography.clavixMono(10, weight: .regular))
            .foregroundColor(isStale ? .clavixWarnInk : .clavixInk4)
    }

    private var ratingPendingCard: some View {
        HStack(spacing: ClavisTheme.smallSpacing) {
            Text("Rating pending. Check back after market open.")
                .font(ClavisTypography.footnote)
                .foregroundColor(.clavixInk3)
            Spacer()
        }
        .padding(ClavisTheme.cardPadding)
        .background(Color.clavixPaper2)
        .clipShape(RoundedRectangle(cornerRadius: ClavisTheme.innerCornerRadius, style: .continuous))
    }

    private var hasAnyDimensionScore: Bool {
        radarDimensions.contains { $0.score != nil }
    }

    private var radarDimensions: [TickerRadarDimension] {
        guard let detail else {
            return [
                TickerRadarDimension(key: "financial_health", label: "FIN", score: nil),
                TickerRadarDimension(key: "news_sentiment", label: "NEWS", score: nil),
                TickerRadarDimension(key: "macro_exposure", label: "MAC", score: nil),
                TickerRadarDimension(key: "sector_exposure", label: "SEC", score: nil),
                TickerRadarDimension(key: "volatility", label: "VOL", score: nil),
            ]
        }
        let dimensions = dimensionItems(detail)
        return dimensions.map { item in
            TickerRadarDimension(key: item.key, label: item.abbrev, score: item.score)
        }
    }

    private func riskDimensionsSection(_ detail: TickerDetailResponse) -> some View {
        let dimensions = dimensionItems(detail)

        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(detail.ticker)'s Five Risk Dimensions")
                    .font(ClavisTypography.clavixSerif(18, weight: .medium))
                    .foregroundColor(.clavixInk)
            }

            ClavixCard(padding: 0, fill: .clavixPaper) {
                VStack(spacing: 0) {
                    ForEach(Array(dimensions.enumerated()), id: \.element.key) { index, dimension in
                        if let destination = auditDestination(for: dimension.key) {
                            NavigationLink {
                                auditDestinationView(for: destination)
                            } label: {
                                dimensionRow(dimension)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("dimension-row-\(dimension.key)")
                        } else {
                            dimensionRow(dimension)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if index < dimensions.count - 1 {
                            Rectangle()
                                .fill(Color.clavixRule2)
                                .frame(height: 1)
                        }
                    }
                }
            }

        }
    }

    private func dimensionRow(_ dimension: TickerDimensionItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dimension.abbrev)
                    .font(ClavisTypography.clavixMono(9, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.clavixInk3)
                Text(dimension.title)
                    .font(ClavisTypography.inter(12))
                    .foregroundColor(.clavixInk)
                    .lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)

            if let coverageLabel = dimension.coverageLabel {
                HStack(spacing: 5) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 10, weight: .semibold))
                    Text(coverageLabel)
                        .font(ClavisTypography.inter(11))
                        .lineLimit(1)
                }
                .foregroundColor(.clavixInk3)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ClavixScoreBar(score: dimension.score.map { Int($0.rounded()) } ?? 0)
                    .frame(height: 5)

                Text(dimension.scoreText)
                    .font(ClavisTypography.clavixMono(16, weight: .semibold))
                    .foregroundColor(scoreToneColor(dimension.score))
                    .frame(width: 38, alignment: .trailing)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.clavixInk4)
        }
        .contentShape(Rectangle())
    }

    private func scoreToneColor(_ score: Double?) -> Color {
        guard let score else { return .clavixInk3 }
        if score >= 70 { return .clavixGood }
        if score >= 50 { return .clavixInk }
        if score >= 30 { return .clavixWarn }
        return .clavixBad
    }

    @ViewBuilder
    private func aboutSection(_ detail: TickerDetailResponse) -> some View {
        let isETF = detail.profile.isETF
        let profile = methodology?.profile
        let desc = profile?.description?.sanitizedDisplayText
        let name = detail.profile.companyName ?? ticker
        let hasContent = (desc?.isEmpty == false) || (isETF && profile?.theme != nil)
        if hasContent {
            VStack(alignment: .leading, spacing: 10) {
                hifiSectionHeader(
                    eyebrow: isETF ? "Fund" : "Company",
                    title: isETF ? "About this fund" : "About \(name)"
                )
                ClavixCard {
                    VStack(alignment: .leading, spacing: 10) {
                        if isETF, let theme = profile?.theme {
                            Text(theme)
                                .font(ClavisTypography.clavixSerif(18, weight: .medium))
                                .foregroundColor(.clavixInk)
                                .fixedSize(horizontal: false, vertical: true)
                            if let benchmark = profile?.benchmark {
                                Text("Tracks the \(benchmark)" + (profile?.totalHoldings.map { " · \($0) holdings" } ?? ""))
                                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                                    .foregroundColor(.clavixInk4)
                            }
                        }
                        if let desc, !desc.isEmpty {
                            Text(desc)
                                .font(ClavisTypography.inter(13))
                                .foregroundColor(.clavixInk2)
                                .lineSpacing(2)
                                .lineLimit(aboutExpanded ? nil : 4)
                                .fixedSize(horizontal: false, vertical: true)
                            if desc.count > 200 {
                                Text(aboutExpanded ? "Show less" : "Read more")
                                    .font(ClavisTypography.clavixMono(11, weight: .semibold))
                                    .foregroundColor(.clavixAccent)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { aboutExpanded.toggle() } }
                }
            }
        }
    }

    private func driversSection(_ detail: TickerDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            hifiSectionHeader(eyebrow: "", title: "Key drivers")

            // The specific, plain-English driver cards below are the key drivers.
            // We intentionally no longer show a synthesized prose paragraph here:
            // it duplicated the cards and was the source of dense, jargon-heavy copy.
            TickerDriverCardsSection(analysis: detail.currentAnalysis)
        }
    }

    @ViewBuilder
    private func executiveSummarySection(_ detail: TickerDetailResponse) -> some View {
        if let summary = detail.sharedAnalysis?.executiveSummaryBreakdown,
           summary.hasAnyContent {
            VStack(alignment: .leading, spacing: 10) {
                hifiSectionHeader(eyebrow: "Summary", title: "Executive summary")
                VStack(alignment: .leading, spacing: 8) {
                    if let bullCase = summary.bullCase?.sanitizedDisplayText, !bullCase.isEmpty {
                        executiveSummaryCard(
                            title: "Bull case",
                            body: bullCase,
                            fill: .clavixGoodSoft,
                            ink: .clavixGoodInk
                        )
                    }
                    if let riskCase = summary.riskCase?.sanitizedDisplayText, !riskCase.isEmpty {
                        executiveSummaryCard(
                            title: "Risk case",
                            body: riskCase,
                            fill: .clavixBadSoft,
                            ink: .clavixBadInk
                        )
                    }
                    if let watch = summary.whatToWatch?.sanitizedDisplayText, !watch.isEmpty {
                        executiveSummaryCard(
                            title: "What to watch",
                            body: watch,
                            fill: .clavixWarnSoft,
                            ink: .clavixWarnInk
                        )
                    }
                }
            }
        }
    }

    private func executiveSummaryCard(title: String, body: String, fill: Color, ink: Color) -> some View {
        ClavixCard(fill: fill) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(ClavisTypography.clavixSerif(16, weight: .medium))
                    .foregroundColor(ink)
                Text(body)
                    .font(ClavisTypography.body)
                    .foregroundColor(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func hifiSectionHeader(eyebrow: String, title: String, action: String? = nil, onAction: (() -> Void)? = nil) -> some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if !eyebrow.isEmpty {
                    ClavixEyebrow(eyebrow)
                }
                Text(title)
                    .font(ClavisTypography.clavixSerif(18, weight: .medium))
                    .foregroundColor(.clavixInk)
            }
            Spacer()
            if let action {
                Button(action: { onAction?() }) {
                    Text(action)
                        .font(ClavisTypography.clavixMono(11, weight: .semibold))
                        .foregroundColor(.clavixAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func recentNewsSection(_ detail: TickerDetailResponse) -> some View {
        let articles = displayArticles(detail)
        let visibleArticles = showAllArticles ? articles : Array(articles.prefix(10))

        return VStack(alignment: .leading, spacing: 10) {
            hifiSectionHeader(
                eyebrow: "",
                title: "Recent news",
                action: articles.count > 10 ? (showAllArticles ? "Show less" : "See all →") : nil,
                onAction: { showAllArticles.toggle() }
            )

            if visibleArticles.isEmpty {
                ClavixInlineNoticeCard(
                    eyebrow: "Recent news",
                    title: "No scored articles are available yet",
                    message: "Clavix has not captured recent article coverage for this ticker in the current window.",
                    footnote: "That can mean the name is quiet, the feed is thin, or coverage has not been scored yet.",
                    glyph: "newspaper"
                )
            } else {
                ClavixCard(fill: .clavixPaper) {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleArticles.enumerated()), id: \.element.id) { index, article in
                            Button(action: { selectedArticle = article }) {
                                newsCard(article)
                            }
                            .buttonStyle(.plain)

                            if index < visibleArticles.count - 1 {
                                Rectangle()
                                    .fill(Color.clavixRule2)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func newsCard(_ article: MethodologyArticle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(article.source ?? "Unknown source")
                    .font(ClavisTypography.clavixMono(11, weight: .semibold))
                    .foregroundColor(.clavixInk2)
                    .lineLimit(1)
                Text("·")
                    .font(ClavisTypography.clavixMono(10, weight: .regular))
                    .foregroundColor(.clavixInk4)
                Text(formatArticleTimestamp(article.publishedAt))
                    .font(ClavisTypography.clavixMono(10, weight: .regular))
                    .foregroundColor(.clavixInk3)
                    .lineLimit(1)
                Spacer(minLength: 4)
                sentimentDot(article.sentimentScore)
            }

            Text(article.title ?? "Untitled article")
                .font(ClavisTypography.clavixSerif(16, weight: .medium))
                .foregroundColor(.clavixInk)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let tldr = article.tldr, !tldr.isEmpty {
                Text(tldr)
                    .font(ClavisTypography.clavixCaption)
                    .foregroundColor(.clavixInk3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 2)
    }

    private func sentimentDot(_ score: Double?) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(sentimentColor(score))
                .frame(width: 7, height: 7)
            Text(score.map { "\(Int($0.rounded()))" } ?? "—")
                .font(ClavisTypography.clavixMono(10, weight: .bold))
                .foregroundColor(sentimentColor(score))
        }
        .fixedSize()
    }

    private static let isoDateParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoDateParserNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let articleRelativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let articleShortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private func formatArticleTimestamp(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let date = TickerDetailView.isoDateParser.date(from: raw)
            ?? TickerDetailView.isoDateParserNoFraction.date(from: raw)
        guard let date else { return raw.prefix(10).description }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 * 60 * 24 * 3 {
            return TickerDetailView.articleRelativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return TickerDetailView.articleShortDateFormatter.string(from: date)
    }

    /// Compact top-nav action: add to / in holdings. Solid ink when actionable,
    /// muted check when already held. Mirrors the "in the corner with symbols"
    /// pattern from broker apps so the primary actions live in the header, not
    /// buried at the bottom of the scroll.
    private var holdingsNavButton: some View {
        Button(action: { if !isHeld { showAddHoldingSheet = true } }) {
            Image(systemName: isHeld ? "checkmark" : "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isHeld ? .clavixInk3 : .clavixPaper)
                .frame(width: 34, height: 30)
                .background(isHeld ? Color.clavixPaper2 : Color.clavixInk)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isHeld ? Color.clavixRule : Color.clear, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isHeld)
        .accessibilityLabel(isHeld ? "In holdings" : "Add to holdings")
    }

    /// Compact top-nav watchlist toggle. Bordered star when off, accent-filled
    /// when watching.
    private var watchlistNavButton: some View {
        Button(action: { Task { await toggleWatchlist() } }) {
            Group {
                if isMutatingWatchlist {
                    ProgressView().tint(.clavixAccent).scaleEffect(0.7)
                } else {
                    Image(systemName: isInWatchlist ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isInWatchlist ? .clavixAccentInk : .clavixInk2)
                }
            }
            .frame(width: 34, height: 30)
            .background(isInWatchlist ? Color.clavixAccentSoft : Color.clavixPaper)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isInWatchlist ? Color.clavixAccent.opacity(0.45) : Color.clavixRule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isMutatingWatchlist)
        .accessibilityLabel(isInWatchlist ? "Remove from watchlist" : "Add to watchlist")
    }

    private func auditDestination(for key: String) -> AuditDestination? {
        switch key {
        case "financial_health": return .financialHealth
        case "news_sentiment": return .newsSentiment
        case "macro_exposure": return .macroExposure
        case "sector_exposure": return .sectorExposure
        case "volatility": return .volatility
        default: return nil
        }
    }

    @ViewBuilder
    private func auditDestinationView(for destination: AuditDestination) -> some View {
        switch destination {
        case .financialHealth:
            FinancialHealthAuditView(
                ticker: ticker,
                methodology: methodology,
                isETF: detail?.profile.isETF ?? false
            )
        case .newsSentiment:
            NewsSentimentAuditView(
                ticker: ticker,
                methodology: methodology,
                isETF: detail?.profile.isETF ?? false
            )
        case .macroExposure:
            MacroExposureAuditView(ticker: ticker, methodology: methodology)
        case .sectorExposure:
            SectorExposureAuditView(
                ticker: ticker,
                methodology: methodology,
                isETF: detail?.profile.isETF ?? false
            )
        case .volatility:
            VolatilityAuditView(
                ticker: ticker,
                methodology: methodology
            )
        }
    }

    private func reloadAll() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedDetail = try await APIService.shared.fetchTickerDetail(
                ticker: ticker,
                positionId: positionId,
                timeoutInterval: 15
            )

            await MainActor.run {
                detail = loadedDetail
                priceHistory = []
                scoreHistory = []
                errorMessage = nil
                watchlistOverride = nil
            }

            Task {
                do {
                    let loadedMethodology = try await APIService.shared.fetchTickerMethodology(ticker: ticker, timeoutInterval: 15)
                    await MainActor.run {
                        methodology = loadedMethodology
                    }
                } catch {
                    await MainActor.run {
                        methodology = nil
                    }
                }
            }

            Task {
                let loadedPrice = try? await APIService.shared.fetchPriceHistory(ticker: ticker, days: 365)
                let sortedPrices = (loadedPrice?.prices ?? []).sorted { $0.recordedAt < $1.recordedAt }
                await MainActor.run {
                    priceHistory = sortedPrices
                }
            }

            Task {
                let loadedScore = try? await APIService.shared.fetchScoreHistory(ticker: ticker, days: 365)
                await MainActor.run {
                    scoreHistory = loadedScore?.points ?? []
                }
            }

        } catch {
            await MainActor.run {
                errorMessage = ClavisCopy.Errors.tickerLoad(ticker: ticker, error: error)
            }
        }
    }

    #if DEBUG
    private func apply(_ fixture: TickerDetailDebugFixture) {
        detail = fixture.detail
        methodology = fixture.methodology
        priceHistory = fixture.priceHistory
        scoreHistory = fixture.scoreHistory
        errorMessage = nil
        isLoading = false
        watchlistOverride = nil
    }
    #endif

    private func toggleWatchlist() async {
        let targetState = !isInWatchlist
        isMutatingWatchlist = true
        watchlistOverride = targetState
        defer { isMutatingWatchlist = false }

        do {
            if targetState {
                _ = try await APIService.shared.addToWatchlist(ticker: ticker)
            } else {
                _ = try await APIService.shared.removeFromWatchlist(ticker: ticker)
            }
            NotificationCenter.default.post(name: .watchlistDidChange, object: nil)
            await reloadAll()
        } catch APIError.limitReached(let code) where code == "watchlist_limit_reached" {
            watchlistOverride = nil
            showWatchlistLimitPaywall = true
        } catch {
            watchlistOverride = nil
            errorMessage = ClavisCopy.Errors.watchlistUpdate(error)
        }
    }

    private func refreshTicker() async {
        isRefreshingTicker = true
        defer { isRefreshingTicker = false }

        do {
            _ = try await APIService.shared.refreshTicker(ticker: ticker)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await reloadAll()
        } catch {
            errorMessage = ClavisCopy.Errors.tickerRefresh(error)
        }
    }

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(ClavisTypography.label)
            .foregroundColor(.clavixInk3)
    }

    private func dimensionItems(_ detail: TickerDetailResponse) -> [TickerDimensionItem] {
        let shared = detail.sharedAnalysis?.riskDimensions
        let ai = detail.currentScore?.factorBreakdown?.aiDimensions
        let current = detail.currentScore
        let isETF = detail.profile.isETF
        let financialTitle = isETF ? "Holdings Quality" : "Financial Health"
        let financialAbbrev = isETF ? "HLD" : "FIN"
        let financialSubtitle = isETF
            ? "Weighted top-holding risk"
            : methodology?.dimensions.financialHealth.dataSource ?? "Quarterly fundamentals"
        let categoryTitle = isETF ? "Sector Strength" : "News Sentiment"
        let categoryAbbrev = isETF ? "STR" : "NEWS"
        let categorySubtitle = isETF ? "Coverage of the fund's space" : newsSubtitle
        let sectorTitle = isETF ? "Concentration" : "Sector Resilience"
        let sectorAbbrev = isETF ? "CONC" : "SEC"
        let sectorSubtitle = isETF
            ? "Sector and holding breadth"
            : methodology?.dimensions.sectorExposure.sector ?? detail.profile.sector ?? "Sector state"
        let volatilitySubtitle = isETF
            ? "Volatility, drawdown, beta"
            : methodology?.dimensions.volatility.asOfDate ?? "Daily price action"

        return [
            TickerDimensionItem(
                key: "financial_health",
                title: financialTitle,
                abbrev: financialAbbrev,
                score: shared?.financialHealth ?? ai?.financialHealth ?? current?.financialHealth,
                subtitle: financialSubtitle,
                isLimited: (shared?.financialHealth ?? ai?.financialHealth ?? current?.financialHealth) == nil
            ),
            TickerDimensionItem(
                key: "news_sentiment",
                title: categoryTitle,
                abbrev: categoryAbbrev,
                score: shared?.newsSentiment ?? ai?.newsSentiment ?? current?.newsSentiment,
                subtitle: categorySubtitle,
                isLimited: methodology?.dimensions.newsSentiment.limitedData ?? false
            ),
            TickerDimensionItem(
                key: "macro_exposure",
                title: "Macro Resilience",
                abbrev: "MAC",
                score: shared?.macroExposure ?? ai?.macroExposure ?? current?.macroExposure,
                subtitle: methodology?.dimensions.macroExposure.asOfDate ?? "Macro regression",
                isLimited: methodology?.dimensions.macroExposure.limitedData ?? false
            ),
            TickerDimensionItem(
                key: "sector_exposure",
                title: sectorTitle,
                abbrev: sectorAbbrev,
                score: shared?.sectorExposure ?? ai?.sectorExposure ?? current?.sectorExposure,
                subtitle: sectorSubtitle,
                isLimited: (shared?.sectorExposure ?? ai?.sectorExposure ?? current?.sectorExposure) == nil
            ),
            TickerDimensionItem(
                key: "volatility",
                title: "Price Stability",
                abbrev: "VOL",
                score: shared?.volatility ?? ai?.volatility ?? current?.volatility,
                subtitle: volatilitySubtitle,
                isLimited: (shared?.volatility ?? ai?.volatility ?? current?.volatility) == nil
            )
        ]
    }

    private var newsSubtitle: String {
        if let methodology {
            return "\(methodology.dimensions.newsSentiment.articleCount7d ?? 0) articles · 7d"
        }
        return "Recent article set"
    }

    private func displayArticles(_ detail: TickerDetailResponse) -> [MethodologyArticle] {
        if let methodologyArticles = methodology?.dimensions.newsSentiment.articles, !methodologyArticles.isEmpty {
            return methodologyArticles
        }
        return detail.recentNews
    }

    private func articlePortfolioContext(detail: TickerDetailResponse?) -> String? {
        guard let detail,
              let weight = detail.portfolioOverlay?.portfolioWeight,
              isHeld else {
            return nil
        }

        let weightText = String(format: "%.1f", weight * 100)
        if let grade = detail.sharedAnalysis?.summary.currentGrade ?? detail.position.resolvedRiskGrade {
            return "\(ticker) is \(weightText)% of your book, so this signal has visible portfolio-level impact even while the ticker rating remains \(grade)."
        }
        return "\(ticker) is \(weightText)% of your book, so this signal has visible portfolio-level impact."
    }

    private func priceLineText(_ detail: TickerDetailResponse) -> String {
        guard let lastPrice = filteredPriceHistory.last?.price ?? latestPrice else {
            return "—"
        }
        let basePrice = filteredPriceHistory.first?.price
            ?? detail.latestPrice.previousClose
            ?? detail.sharedAnalysis?.previousClose
        guard let basePrice, basePrice != 0 else {
            return currency(lastPrice)
        }
        let changePct = ((lastPrice - basePrice) / basePrice) * 100
        return "\(currency(lastPrice)) · \(changePct >= 0 ? "+" : "−")\(String(format: "%.2f", abs(changePct)))%"
    }

    private func priceLineColor(_ detail: TickerDetailResponse) -> Color {
        let lastPrice = filteredPriceHistory.last?.price ?? latestPrice
        let basePrice = filteredPriceHistory.first?.price
            ?? detail.latestPrice.previousClose
            ?? detail.sharedAnalysis?.previousClose
        guard let lastPrice, let basePrice else { return .clavixInk3 }
        if lastPrice > basePrice { return .clavixGood }
        if lastPrice < basePrice { return .clavixBad }
        return .clavixInk3
    }


    private func sentimentPill(score: Double?) -> some View {
        dimensionBadge(
            text: score.map { "\(Int($0.rounded()))" } ?? "—",
            foreground: sentimentColor(score),
            background: sentimentBackground(score)
        )
    }

    private func impactPill(text: String) -> some View {
        dimensionBadge(text: text, foreground: .clavixAccentInk, background: .clavixAccentSoft)
    }

    private func dimensionBadge(text: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(ClavisTypography.label)
            .foregroundColor(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: ClavisTheme.innerCornerRadius, style: .continuous))
    }

    private func sentimentColor(_ score: Double?) -> Color {
        guard let score else { return .clavixInk3 }
        if score >= 70 { return .clavixGood }
        if score >= 50 { return .clavixWarn }
        return .clavixBad
    }

    private func sentimentBackground(_ score: Double?) -> Color {
        guard let score else { return .clavixPaper2 }
        if score >= 70 { return .clavixGoodSoft }
        if score >= 50 { return .clavixWarnSoft }
        return .clavixBadSoft
    }

    private func holdingSummary(_ detail: TickerDetailResponse) -> String {
        let sharesText = detail.portfolioOverlay?.shares ?? detail.position.shares
        let valueText = detail.portfolioOverlay?.marketValue ?? detail.position.currentValue
        let parts = [
            sharesText > 0 ? "\(sharesText.formatted()) shares" : nil,
            valueText.map { currency($0) }
        ].compactMap { $0 }

        if parts.isEmpty {
            return "Holding data is available in your portfolio."
        }
        return parts.joined(separator: " · ")
    }

    private func currency(_ value: Double?) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }

    private var latestPrice: Double? {
        detail?.latestPrice.price ?? detail?.portfolioOverlay?.currentPrice
    }

    private var filteredPriceHistory: [PricePoint] {
        guard !priceHistory.isEmpty else { return [] }
        // priceHistory is kept sorted at load time.
        let sorted = priceHistory
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -selectedHistoryPeriod.dayWindow, to: Date()) else {
            return Self.downsample(sorted)
        }
        let filtered = sorted.filter { $0.recordedAt >= cutoff }
        return Self.downsample(filtered.isEmpty ? sorted : filtered)
    }

    /// Even-stride downsample to keep Swift Charts responsive. Minute-level
    /// tickers can carry thousands of points per window; rendering a LineMark
    /// for each is what makes the chart lag. ~160 points keeps the curve shape
    /// while cutting the mark count by an order of magnitude. First and last
    /// points are always preserved so the endpoints stay accurate.
    static func downsample(_ points: [PricePoint], cap: Int = 160) -> [PricePoint] {
        guard points.count > cap, cap >= 2 else { return points }
        let step = Double(points.count - 1) / Double(cap - 1)
        var out: [PricePoint] = []
        out.reserveCapacity(cap)
        var idx = 0.0
        for _ in 0..<cap {
            out.append(points[min(Int(idx.rounded()), points.count - 1)])
            idx += step
        }
        if let realLast = points.last, out.last?.recordedAt != realLast.recordedAt {
            out[out.count - 1] = realLast
        }
        return out
    }

    private var filteredScoreSnapshots: [ScoreSnapshot] {
        let snapshots = ScoreHistoryConversion.snapshots(from: scoreHistory)
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -selectedHistoryPeriod.dayWindow, to: Date()) else {
            return snapshots
        }
        let filtered = snapshots.filter { $0.date >= cutoff }
        return filtered.isEmpty ? snapshots : filtered
    }


    private var displayScoreValue: Double? {
        detail?.sharedAnalysis?.summary.currentScore
            ?? detail?.currentScore?.totalScore
            ?? detail?.currentScore?.safetyScore
            ?? detail?.position.totalScore
    }

    private var displayScoreText: String {
        displayScoreValue.map { "\(Int($0.rounded()))" } ?? "—"
    }

    private var displayGrade: String {
        detail?.sharedAnalysis?.summary.currentGrade
            ?? detail?.currentScore?.grade
            ?? detail?.position.riskGrade
            ?? "—"
    }

    private var isHeld: Bool {
        detail?.portfolioOverlay?.isHeld ?? detail?.userContext.isHeld ?? false
    }

    private var isInWatchlist: Bool {
        watchlistOverride
            ?? detail?.portfolioOverlay?.isInWatchlist
            ?? detail?.userContext.isInWatchlist
            ?? false
    }

}

private struct TickerDimensionItem {
    let key: String
    let title: String
    let abbrev: String
    let score: Double?
    let subtitle: String
    let isLimited: Bool

    var scoreText: String {
        score.map { "\(Int($0.rounded()))" } ?? "—"
    }

    /// Honest coverage state when there is no usable score, so the row reads as a
    /// coverage gap (not a zero / worst rating). nil when a real score should show.
    /// News uses an explicit limited-data flag even when a suppressed score exists
    /// (CLAVIX TRUTH §6.2: <3 articles shows "Limited" instead of a score).
    var coverageLabel: String? {
        if key == "news_sentiment" && isLimited { return "Limited coverage" }
        if score == nil { return "Not yet rated" }
        return nil
    }

    var grade: String {
        guard let score else { return "F" }
        return PortfolioMath.grade(forScore: score)
    }
}

private enum TickerHistoryPeriod: String, CaseIterable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"

    var label: String { rawValue }

    var dayWindow: Int {
        switch self {
        case .oneMonth: return 30
        case .threeMonths: return 90
        case .sixMonths: return 182
        case .oneYear: return 365
        }
    }
}

private struct HistoryPeriodChips: View {
    @Binding var selected: TickerHistoryPeriod
    var compact: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(TickerHistoryPeriod.allCases, id: \.self) { period in
                    Button(action: { selected = period }) {
                        Text(period.label)
                            .font(ClavisTypography.clavixMono(11, weight: .semibold))
                            .foregroundColor(selected == period ? .clavixCanvas : .clavixInk3)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, compact ? 8 : 10)
                            .padding(.vertical, 6)
                            .frame(minWidth: compact ? 30 : 38)
                            .background(selected == period ? Color.clavixAccent : Color.clavixPaper2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(selected == period ? Color.clavixAccent : Color.clavixRule2, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.trailing)
    }
}

private struct TickerAddHoldingSheet: View {
    let ticker: String
    let companyName: String?
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shares = ""
    @State private var costBasis = ""
    @State private var purchaseDate = Date()
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        (Double(shares) ?? 0) > 0 && (Double(costBasis) ?? 0) >= 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clavixPage
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                        ClavixCard(fill: .clavixPaper) {
                            VStack(alignment: .leading, spacing: ClavisTheme.smallSpacing) {
                                Text(companyName ?? ticker)
                                    .font(ClavisTypography.cardTitle)
                                    .foregroundColor(.clavixInk)
                                Text(ticker)
                                    .font(ClavisTypography.footnoteEmphasis)
                                    .foregroundColor(.clavixAccent)
                            }
                        }

                        field(title: "Shares", text: $shares)
                        field(title: "Cost basis per share", text: $costBasis)

                        ClavixCard(fill: .clavixPaper) {
                            VStack(alignment: .leading, spacing: ClavisTheme.smallSpacing) {
                                Text("Purchase date")
                                    .font(ClavisTypography.label)
                                    .foregroundColor(.clavixInk3)
                                DatePicker("Purchase date", selection: $purchaseDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                            }
                        }

                        if let errorMessage {
                            DashboardErrorCard(message: errorMessage)
                        }

                    }
                    .padding(.horizontal, ClavisTheme.screenPadding)
                    .padding(.vertical, ClavisTheme.sectionSpacing)
                }
            }
            .navigationTitle("Add to Holdings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.clavixPage, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.clavixInk3)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Adding..." : "Add") {
                        Task { await submit() }
                    }
                    .foregroundColor(isValid ? .clavixAccent : .clavixInk4)
                    .disabled(!isValid || isSubmitting)
                }
            }
        }
    }

    private func field(title: String, text: Binding<String>) -> some View {
        ClavixCard(fill: .clavixPaper) {
            VStack(alignment: .leading, spacing: ClavisTheme.smallSpacing) {
                Text(title)
                    .font(ClavisTypography.label)
                    .foregroundColor(.clavixInk3)
                TextField(title, text: text, prompt: Text(title).foregroundColor(.clavixInk3))
                    .keyboardType(.decimalPad)
                    .font(ClavisTypography.body)
                    .foregroundColor(.clavixInk)
            }
        }
    }

    private func submit() async {
        guard let sharesValue = Double(shares), let costBasisValue = Double(costBasis) else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            _ = try await APIService.shared.createHolding(
                ticker: ticker,
                shares: sharesValue,
                purchasePrice: costBasisValue
            )
            onComplete()
        } catch {
            errorMessage = ClavisCopy.Errors.holdingAdd(error)
        }
    }
}
