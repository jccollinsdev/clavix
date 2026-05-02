import SwiftUI

struct TickerDetailView: View {
    let ticker: String
    let positionId: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var detail: TickerDetailResponse?
    @State private var priceHistory: [PricePoint] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isMutatingWatchlist = false
    @State private var isRefreshingTicker = false
    @State private var selectedDays: Int = 30
    @State private var hasLoaded = false

    init(ticker: String, positionId: String? = nil) {
        self.ticker = ticker
        self.positionId = positionId
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                CX2NavBar(
                    title: ticker,
                    subtitle: detail?.profile.companyName ?? detail?.profile.sector ?? "Ticker detail"
                ) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 1) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Holdings")
                                .font(.system(size: 15, weight: .regular))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundColor(.informational)
                    }
                    .buttonStyle(.plain)
                } trailing: {
                    if authViewModel.subscriptionTier == "pro" || authViewModel.subscriptionTier == "admin" {
                        CX2IconButton(action: { Task { await refreshTicker() } }) {
                            Image(systemName: isRefreshingTicker ? "hourglass" : "arrow.clockwise")
                                .font(.system(size: 15, weight: .medium))
                        }
                    }

                    CX2IconButton(action: { Task { await toggleWatchlist() } }) {
                        Image(systemName: isInWatchlist ? "star.fill" : "star")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isInWatchlist ? .informational : .textPrimary)
                    }
                }

                if let errorMessage {
                    DashboardErrorCard(message: errorMessage)
                }

                if isLoading && detail == nil {
                    ClavisLoadingCard(
                        title: "Loading \(ticker)",
                        subtitle: "Pulling the latest market data and risk summary."
                    )
                } else if let detail {
                    TickerHeroCard(
                        ticker: ticker,
                        companyName: detail.profile.companyName ?? ticker,
                        sector: detail.profile.sector ?? detail.profile.industry ?? "Market view",
                        grade: displayGrade(for: detail),
                        score: displayScore(for: detail),
                        previousScore: estimatedPreviousScore(for: detail),
                        direction: detail.position.riskTrend,
                        rationale: tickerRationale(for: detail),
                        evidenceStrength: detail.currentScore?.evidenceStrength ?? (detail.position.evidenceStrength),
                        scoreSource: detail.currentScore?.scoreSource ?? detail.position.scoreSource,
                        scoreAsOf: detail.currentScore?.scoreAsOf ?? detail.position.scoreAsOf ?? detail.freshness.analysisAsOf
                    )

                    TickerPriceCard(
                        price: currency(detail.latestPrice.price),
                        changeText: priceChangeText(for: detail),
                        changeDirection: priceChangeDirection(for: detail),
                        selectedDays: $selectedDays,
                        priceHistory: priceHistory,
                        onDaysChange: { days in
                            Task { await loadPriceHistory(days: days) }
                        }
                    )

                    TickerMetricGridCard(metrics: fundamentals(for: detail))

                    if let dimensions = riskDimensions(for: detail) {
                        TickerRiskDimensionsCard(dimensions: dimensions, rationale: detail.dimensionBreakdown)
                    }

                    ratingRationaleCard(detail)

                    TickerDriverCardsSection(analysis: detail.currentAnalysis)


                    if !detail.latestEventAnalyses.isEmpty {
                        TickerEventAnalysesCard(
                            events: Array(detail.latestEventAnalyses.prefix(4)),
                            isHeld: detail.userContext.isHeld
                        )
                    }

                    if !watchItems(for: detail).isEmpty {
                        TickerBulletedListCard(title: "What to watch", items: watchItems(for: detail))
                    }

                    if !detail.recentAlerts.isEmpty {
                        TickerAlertsListCard(alerts: Array(detail.recentAlerts.prefix(3)))
                    }

                    if !detail.recentNews.isEmpty {
                        TickerRecentNewsCard(stories: Array(detail.recentNews.prefix(3)))
                    }
                }
            }
            .padding(.horizontal, ClavisTheme.screenPadding)
            .padding(.top, 0)
            .padding(.bottom, ClavisTheme.floatingTabHeight + ClavisTheme.floatingTabInset + ClavisTheme.extraLargeSpacing)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.bottom, 0, for: .scrollContent)
        .background(ClavisAtmosphereBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await reloadAll()
        }
        .refreshable {
            await reloadAll()
        }
    }

    private var isInWatchlist: Bool {
        detail?.userContext.isInWatchlist ?? false
    }

    private var navTitle: String {
        if let companyName = detail?.profile.companyName, !companyName.isEmpty {
            return "\(ticker) · \(companyName)"
        }
        return ticker
    }

    private func displayScore(for detail: TickerDetailResponse) -> Int {
        Int((detail.currentScore?.displayScore ?? detail.position.totalScore ?? 50).rounded())
    }

    private func displayGrade(for detail: TickerDetailResponse) -> String {
        detail.currentScore?.displayGrade ?? detail.position.riskGrade ?? "—"
    }

    private func estimatedPreviousScore(for detail: TickerDetailResponse) -> Int? {
        if let delta = detail.currentScore?.scoreDelta {
            return displayScore(for: detail) - delta
        }
        return nil
    }

    private func tickerRationale(for detail: TickerDetailResponse) -> String {
        if let reasoning = detail.currentScore?.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines), !reasoning.isEmpty {
            return reasoning
        }
        if let summary = detail.latestRiskSnapshot?.newsSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }
        return "Rating pending — data still being processed."
    }

    private func priceChangePercent(for detail: TickerDetailResponse) -> Double? {
        guard let price = detail.latestPrice.price,
              let previous = detail.latestPrice.previousClose,
              previous != 0 else { return nil }
        return ((price - previous) / previous) * 100
    }

    private func priceChangeText(for detail: TickerDetailResponse) -> String {
        guard let change = priceChangePercent(for: detail) else { return "--" }
        return String(format: "%@%.1f%%", change >= 0 ? "+" : "", change)
    }

    private func priceChangeDirection(for detail: TickerDetailResponse) -> TickerChangeDirection {
        guard let change = priceChangePercent(for: detail) else { return .flat }
        if change > 0 { return .up }
        if change < 0 { return .down }
        return .flat
    }

    private func fundamentals(for detail: TickerDetailResponse) -> [TickerMetricItem] {
        [
            TickerMetricItem(label: "P/E", value: number(detail.profile.peRatio)),
            TickerMetricItem(label: "Mkt cap", value: compactCurrency(detail.profile.marketCap)),
            TickerMetricItem(label: "Volatility", value: score(detail.latestRiskSnapshot?.factorBreakdown?.volatilityScore))
        ]
    }

    private func riskDimensions(for detail: TickerDetailResponse) -> [TickerRiskDimensionItem]? {
        if let ai = detail.currentScore?.factorBreakdown?.aiDimensions ?? detail.latestRiskSnapshot?.factorBreakdown?.aiDimensions {
            var dimensions = [
                TickerRiskDimensionItem(title: "News risk signals", value: ai.newsSentiment, accent: .riskA),
                TickerRiskDimensionItem(title: "Macro exposure", value: ai.macroExposure, accent: .riskB),
                TickerRiskDimensionItem(title: "Volatility trend", value: ai.volatilityTrend, accent: .riskD),
            ]
            if detail.userContext.isHeld {
                dimensions.insert(TickerRiskDimensionItem(title: "Position sizing", value: ai.positionSizing, accent: .riskC), at: 2)
            }
            return dimensions
        }

        guard let score = detail.currentScore else { return nil }
        var dimensions = [
            TickerRiskDimensionItem(title: "News risk signals", value: score.newsSentiment, accent: .riskA),
            TickerRiskDimensionItem(title: "Macro exposure", value: score.macroExposure, accent: .riskB),
            TickerRiskDimensionItem(title: "Volatility trend", value: score.volatilityTrend, accent: .riskD),
        ]
        if detail.userContext.isHeld {
            dimensions.insert(TickerRiskDimensionItem(title: "Position sizing", value: score.positionSizing, accent: .riskC), at: 2)
        }
        return dimensions
    }

    private func watchItems(for detail: TickerDetailResponse) -> [String] {
        if let items = detail.currentAnalysis?.watchItems, !items.isEmpty {
            return Array(items.prefix(3)).map { $0.sanitizedDisplayText }
        }

        let eventDrivenItems = detail.latestEventAnalyses.prefix(3).compactMap { event in
            let title = event.title.sanitizedDisplayText
            let summary = event.summary?.sanitizedDisplayText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if summary.isEmpty { return title }
            return "\(title) — \(summary)"
        }
        if !eventDrivenItems.isEmpty {
            return eventDrivenItems
        }

        let articleDrivenItems = detail.recentNews.prefix(3).compactMap { article in
            let title = article.title.sanitizedDisplayText
            let summary = article.summary?.sanitizedDisplayText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if summary.isEmpty { return title }
            return "\(title) — \(summary)"
        }
        if !articleDrivenItems.isEmpty {
            return articleDrivenItems
        }

        return detail.recentAlerts.prefix(2).map { $0.message.sanitizedDisplayText }
    }

    @ViewBuilder
    private func ratingRationaleCard(_ detail: TickerDetailResponse) -> some View {
        let rationale = tickerRationale(for: detail)

        if !rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ClavisStandardCard(fill: .surface) {
                VStack(alignment: .leading, spacing: 10) {
                    CX2SectionLabel(text: "Score rationale")

                    Text(rationale)
                        .font(ClavisTypography.body)
                        .foregroundColor(.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func fundamentalsCard(_ detail: TickerDetailResponse) -> some View {
        ClavisStandardCard(fill: .surface) {
            VStack(alignment: .leading, spacing: ClavisTheme.mediumSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Snapshot")
                        .font(ClavisTypography.cardTitle)
                        .foregroundColor(.textPrimary)

                    Text("Latest market view")
                        .font(ClavisTypography.footnote)
                        .foregroundColor(.textSecondary)
                }

                HStack(spacing: ClavisTheme.smallSpacing) {
                    metricPill(title: "P/E", value: number(detail.profile.peRatio))
                    metricPill(title: "52W High", value: currency(detail.profile.week52High))
                    metricPill(title: "52W Low", value: currency(detail.profile.week52Low))
                }

                HStack(spacing: ClavisTheme.smallSpacing) {
                    metricPill(title: "Open", value: currency(detail.latestPrice.openPrice))
                    metricPill(title: "Day High", value: currency(detail.latestPrice.dayHigh))
                    metricPill(title: "Day Low", value: currency(detail.latestPrice.dayLow))
                }

                VStack(alignment: .leading, spacing: ClavisTheme.smallSpacing) {
                    Text(detail.profile.companyName ?? ticker)
                        .font(ClavisTypography.bodyEmphasis)
                        .foregroundColor(.textPrimary)
                    Text(detail.profile.sector ?? detail.profile.industry ?? "Market view")
                        .font(ClavisTypography.footnote)
                        .foregroundColor(.textSecondary)

                    if let summary = detail.latestRiskSnapshot?.newsSummary ?? detail.latestRiskSnapshot?.reasoning {
                        Text(summary)
                            .font(ClavisTypography.footnote)
                            .foregroundColor(.textSecondary)
                    }

                    HStack(spacing: ClavisTheme.smallSpacing) {
                        metricPill(title: "Price", value: currency(detail.latestPrice.price))
                        metricPill(title: "Score", value: score(Double(displayScore(for: detail))))
                        metricPill(title: "Freshness", value: freshnessText(detail.freshness.analysisAsOf))
                    }

                    if detail.userContext.isHeld {
                        Text("Already in holdings")
                            .font(ClavisTypography.footnoteEmphasis)
                            .foregroundColor(.riskA)
                    }
                }
            }
        }
    }

@ViewBuilder
    private func alertsCard(_ alerts: [Alert]) -> some View {
        ClavisStandardCard(fill: .surface) {
            VStack(alignment: .leading, spacing: ClavisTheme.mediumSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Alerts")
                        .font(ClavisTypography.cardTitle)
                        .foregroundColor(.textPrimary)

                    Text("Ticker-specific changes for your account")
                        .font(ClavisTypography.footnote)
                        .foregroundColor(.textSecondary)
                }

                ForEach(alerts.prefix(5)) { alert in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(alert.type.displayName)
                            .font(ClavisTypography.footnoteEmphasis)
                            .foregroundColor(.textPrimary)
                        Text(alert.message)
                            .font(ClavisTypography.body)
                            .foregroundColor(.textSecondary)
                        if let reason = alert.changeReason?.sanitizedDisplayText, !reason.isEmpty {
                            Text(reason)
                                .font(ClavisTypography.footnote)
                                .foregroundColor(.textTertiary)
                        }
                        Text(alert.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(ClavisTypography.footnote)
                            .foregroundColor(.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(ClavisTheme.cardPadding)
                    .clavisCardStyle(fill: .surfaceElevated)
                }
            }
        }
    }

    private func metricPill(title: String, value: String, accent: Color = .textPrimary) -> some View {
        HoldingsStatPill(title: title, value: value, accent: accent)
    }

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await APIService.shared.fetchTickerDetail(ticker: ticker, positionId: positionId)
            errorMessage = nil
        } catch {
            errorMessage = ClavisCopy.Errors.tickerLoad(ticker: ticker, error: error)
        }
    }

    private func loadPriceHistory(days: Int = 30) async {
        do {
            let response = try await APIService.shared.fetchPriceHistory(ticker: ticker, days: days)
            priceHistory = response.prices
            errorMessage = nil
        } catch {
            if priceHistory.isEmpty {
                errorMessage = nil
            }
        }
    }

    private func reloadAll() async {
        await loadDetail()
        await loadPriceHistory(days: selectedDays)
    }

    private func toggleWatchlist() async {
        isMutatingWatchlist = true
        defer { isMutatingWatchlist = false }
        do {
            if isInWatchlist {
                _ = try await APIService.shared.removeFromWatchlist(ticker: ticker)
            } else {
                _ = try await APIService.shared.addToWatchlist(ticker: ticker)
            }
            await loadDetail()
        } catch {
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

    private func currency(_ value: Double?) -> String {
        guard let value else { return "--" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "--"
    }

    private func number(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f", value)
    }

    private func compactCurrency(_ value: Double?) -> String {
        guard let value else { return "--" }

        let absValue = abs(value)
        if absValue >= 1_000_000_000_000 {
            return String(format: "$%.1fT", value / 1_000_000_000_000)
        }
        if absValue >= 1_000_000_000 {
            return String(format: "$%.1fB", value / 1_000_000_000)
        }
        if absValue >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        }
        return currency(value)
    }

    private func score(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))"
    }

    private func freshnessText(_ date: Date?) -> String {
        ClavisCopy.Status.timestamp(date)
    }
}

private struct TickerInlineNavBar: View {
    let isWatchlisted: Bool
    let isRefreshing: Bool
    let canRefresh: Bool
    let onBack: () -> Void
    let onToggleWatchlist: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Text("‹ Back")
                    .font(ClavisTypography.footnoteEmphasis)
                    .foregroundColor(.informational)
            }
            .buttonStyle(.plain)

            Spacer()

            if canRefresh {
                Button(action: onRefresh) {
                    Image(systemName: isRefreshing ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Button(action: onToggleWatchlist) {
                Image(systemName: isWatchlisted ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isWatchlisted ? .informational : .textSecondary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct TickerHeroCard: View {
    let ticker: String
    let companyName: String
    let sector: String
    let grade: String
    let score: Int
    let previousScore: Int?
    let direction: RiskTrend?
    let rationale: String
    var evidenceStrength: EvidenceStrength? = nil
    var scoreSource: String? = nil
    var scoreAsOf: Date? = nil

    private var parsedRationale: (header: String, drivers: [String]) {
        let lines = rationale
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        let header = lines.first ?? rationale
        let drivers = Array(lines.dropFirst()).map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        return (header, Array(drivers.prefix(2)))
    }

    var body: some View {
        ClavisStandardCard(fill: .surface) {
                VStack(alignment: .leading, spacing: 16) {
                    GradeDisplay(
                        grade: grade,
                        score: score,
                        trend: direction,
                        evidence: evidenceStrength,
                        previousScore: previousScore,
                        style: .hero
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(ticker)
                            .font(ClavisTypography.label)
                            .foregroundColor(.textSecondary)

                        Text(companyName)
                            .font(ClavisTypography.bodyEmphasis)
                            .foregroundColor(.textPrimary)
                    }

                    HStack(spacing: 6) {
                        ScoreSourceChip(source: scoreSource)
                        FreshnessChip(date: scoreAsOf)
                    Spacer()
                    Text(sector)
                        .font(ClavisTypography.footnote)
                        .foregroundColor(.textSecondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(parsedRationale.header)
                        .font(ClavisTypography.bodyEmphasis)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(parsedRationale.drivers, id: \.self) { driver in
                        Text(driver)
                            .font(ClavisTypography.body)
                            .foregroundColor(.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private enum TickerChangeDirection {
    case up
    case down
    case flat
}



private struct TickerPriceCard: View {
    let price: String
    let changeText: String
    let changeDirection: TickerChangeDirection
    @Binding var selectedDays: Int
    let priceHistory: [PricePoint]
    let onDaysChange: (Int) -> Void

    private let dayOptions: [Int] = [1, 7, 30, 90, 365]

    var body: some View {
        ClavisStandardCard(fill: .surface) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(price)
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .foregroundColor(.textPrimary)
                        Text(labelForDays(selectedDays))
                            .font(ClavisTypography.footnote)
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(changeText)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(changeColor)
                        Text("Today")
                            .font(ClavisTypography.label)
                            .foregroundColor(.textSecondary)
                    }
                }

                TickerSparkline(priceHistory: priceHistory, direction: changeDirection)
                    .frame(height: 56)

                HStack(spacing: 6) {
                    ForEach(dayOptions, id: \.self) { days in
                        ClavisSelectablePill(title: labelForDays(days), isSelected: selectedDays == days) {
                            selectedDays = days
                            onDaysChange(days)
                        }
                    }
                }
            }
        }
    }

    private var changeColor: Color {
        switch changeDirection {
        case .up: return .riskA
        case .down: return .riskD
        case .flat: return .textSecondary
        }
    }

    private func labelForDays(_ days: Int) -> String {
        switch days {
        case 1: return "1D"
        case 7: return "1W"
        case 30: return "1M"
        case 90: return "3M"
        default: return "1Y"
        }
    }
}

    private struct TickerSparkline: View {
        let priceHistory: [PricePoint]
        let direction: TickerChangeDirection

        private var orderedHistory: [PricePoint] {
            priceHistory.sorted { $0.recordedAt < $1.recordedAt }
        }

        var body: some View {
            GeometryReader { geometry in
                Path { path in
                    let points = normalizedPoints(in: geometry.size)
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }

        private var lineColor: Color {
            switch direction {
            case .up: return .riskA
            case .down: return .riskD
            case .flat: return .textSecondary
            }
        }

        private func normalizedPoints(in size: CGSize) -> [CGPoint] {
            let values = orderedHistory.map(\.price)
            guard values.count > 1,
                  let minValue = values.min(),
                  let maxValue = values.max() else {
                return [CGPoint(x: 0, y: size.height / 2), CGPoint(x: size.width, y: size.height / 2)]
            }

            let range = max(maxValue - minValue, 0.001)
            return values.enumerated().map { index, value in
                let x = (CGFloat(index) / CGFloat(max(values.count - 1, 1))) * size.width
                let y = size.height - ((CGFloat(value - minValue) / CGFloat(range)) * (size.height - 6)) - 3
                return CGPoint(x: x, y: y)
            }
        }
    }

private struct TickerEventAnalysesCard: View {
    let events: [EventAnalysis]
    let isHeld: Bool

    var body: some View {
        ClavisFlushListCard(fill: .surface) {
            VStack(alignment: .leading, spacing: 0) {
                Text(isHeld ? "Event analyses" : "Recent news")
                    .font(ClavisTypography.label)
                    .foregroundColor(.textSecondary)
                    .padding(.vertical, 12)

                ForEach(events) { event in
                    NavigationLink(destination: TickerEventAnalysisDetailView(event: event)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.title)
                                .font(ClavisTypography.bodyEmphasis)
                                .foregroundColor(.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            if let summary = event.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                                Text(summary)
                                    .font(ClavisTypography.footnote)
                                    .foregroundColor(.textSecondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack {
                                if let source = event.source {
                                    Text(source)
                                        .font(ClavisTypography.footnote)
                                        .foregroundColor(.textTertiary)
                                }
                                Spacer()
                                Text("Open")
                                    .font(ClavisTypography.footnoteEmphasis)
                                    .foregroundColor(.informational)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if event.id != events.last?.id {
                        Divider().overlay(Color.border)
                    }
                }
            }
        }
    }
}

private struct TickerEventAnalysisDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let event: EventAnalysis

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                HStack {
                    Button(action: { dismiss() }) {
                        Text("‹ Back")
                            .font(ClavisTypography.footnoteEmphasis)
                            .foregroundColor(.informational)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title)
                        .font(ClavisTypography.h2)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        if let source = event.source {
                            Text(source)
                                .font(ClavisTypography.footnote)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Text(event.publishedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
                            .font(ClavisTypography.footnote)
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(ClavisTheme.cardPadding)
                .clavisCardStyle(fill: .surface)

                if let summary = event.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                    TickerAnalysisDetailSection(title: "What happened", text: strippedAnalysis(summary, title: event.title))
                }

                if let longAnalysis = event.longAnalysis?.trimmingCharacters(in: .whitespacesAndNewlines), !longAnalysis.isEmpty {
                    TickerAnalysisDetailSection(title: "Analysis", text: strippedAnalysis(longAnalysis, title: event.title))
                }

                if let scenario = event.scenarioSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !scenario.isEmpty {
                    TickerAnalysisDetailSection(title: "What it means", text: strippedAnalysis(scenario, title: event.title))
                }

                if let implications = event.keyImplications, !implications.isEmpty {
                    TickerAnalysisListSection(title: "Key implications", items: implications)
                }

                if let followups = event.recommendedFollowups, !followups.isEmpty {
                    TickerAnalysisListSection(title: "Follow-up notes", items: followups)
                }

                if let sourceURLString = event.sourceURL,
                   let url = URL(string: sourceURLString) {
                    Link(destination: url) {
                        Text("Open source article →")
                            .font(ClavisTypography.footnoteEmphasis)
                            .foregroundColor(.informational)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(ClavisTheme.cardPadding)
                    .clavisCardStyle(fill: .surfaceElevated)
                }
            }
            .padding(.horizontal, ClavisTheme.screenPadding)
            .padding(.vertical, ClavisTheme.largeSpacing)
            .padding(.bottom, ClavisTheme.largeSpacing)
        }
        .background(ClavisAtmosphereBackground())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func strippedAnalysis(_ text: String, title: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !normalizedTitle.isEmpty else { return trimmed }

        let lowerText = trimmed.lowercased()
        let lowerTitle = normalizedTitle.lowercased()
        if lowerText == lowerTitle {
            return ""
        }
        if lowerText.hasPrefix(lowerTitle) {
            let startIndex = trimmed.index(trimmed.startIndex, offsetBy: min(trimmed.count, normalizedTitle.count))
            let remainder = trimmed[startIndex...].trimmingCharacters(in: CharacterSet(charactersIn: " \n\t:-—–"))
            if !remainder.isEmpty {
                return String(remainder)
            }
        }
        return trimmed
    }
}

private struct TickerAnalysisDetailSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(ClavisTypography.label)
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(text)
                .font(ClavisTypography.body)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
        }
        .padding(ClavisTheme.cardPadding)
        .clavisCardStyle(fill: .surface)
    }
}

private struct TickerAnalysisListSection: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(ClavisTypography.label)
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                        .font(ClavisTypography.body)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(ClavisTheme.cardPadding)
        .clavisCardStyle(fill: .surface)
    }
}

private struct TickerMetricItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct TickerMetricGridCard: View {
    let metrics: [TickerMetricItem]

    var body: some View {
        ClavisStandardCard(fill: .surface) {
            VStack(alignment: .leading, spacing: 8) {
                CX2SectionLabel(text: "Fundamentals")

                ClavisFlushListCard(fill: .surface, padding: 0) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
                        ForEach(metrics) { metric in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(metric.label)
                                    .font(ClavisTypography.label)
                                    .foregroundColor(.textSecondary)
                                Text(metric.value)
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.textPrimary)
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.surface)
                            .overlay(alignment: .trailing) {
                                Rectangle()
                                    .fill(Color.border)
                                    .frame(width: 1)
                                    .opacity(metric.id == metrics.last?.id ? 0 : 1)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TickerRiskDimensionItem: Identifiable {
    let id = UUID()
    let title: String
    let value: Double?
    let accent: Color
}

private struct TickerRiskDimensionsCard: View {
    let dimensions: [TickerRiskDimensionItem]
    var rationale: [String: String]? = nil

    var body: some View {
        ClavisStandardCard(fill: .surface) {
            VStack(alignment: .leading, spacing: 10) {
                CX2SectionLabel(text: "Risk dimensions")

                VStack(spacing: 10) {
                    ForEach(dimensions) { item in
                        TickerRiskDimensionRow(item: item, rationaleText: rationaleText(for: item.title))
                    }
                }
            }
        }
    }

    private func rationaleText(for title: String) -> String? {
        guard let rationale else { return nil }
        let normalizedKey = title.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "risk signals", with: "sentiment")
        return rationale[normalizedKey]?.sanitizedDisplayText
    }
}

private struct TickerRiskDimensionRow: View {
    let item: TickerRiskDimensionItem
    var rationaleText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(valueText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textPrimary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.border)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.textPrimary.opacity(0.55))
                        .frame(width: geo.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)

            if let rationaleText, !rationaleText.isEmpty {
                Text(rationaleText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.textTertiary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var progress: CGFloat {
        guard let value = item.value else { return 0.1 }
        return CGFloat(max(0, min(value, 100)) / 100)
    }

    private var valueText: String {
        guard let value = item.value else { return "--" }
        return "\(Int(value.rounded()))"
    }
}

private struct TickerBulletedListCard: View {
    let title: String
    let items: [String]

    var body: some View {
        ClavisStandardCard(fill: .surface) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(ClavisTypography.label)
                    .foregroundColor(.textSecondary)

                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.textSecondary)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(item)
                            .font(ClavisTypography.body)
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct TickerAlertsListCard: View {
    let alerts: [Alert]

    var body: some View {
        ClavisFlushListCard(fill: .surface) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline) {
                    CX2SectionLabel(text: "Recent alerts")
                    Spacer()
                    Text("All alerts")
                        .font(ClavisTypography.body)
                        .foregroundColor(.informational)
                }
                .padding(.vertical, 12)

                VStack(spacing: 0) {
                    ForEach(alerts) { alert in
                        HStack(alignment: .top, spacing: 12) {
                            GradeBadge(grade: alert.newGrade ?? alert.previousGrade ?? "—", size: .compact)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(alert.type.displayName)
                                    .font(ClavisTypography.label)
                                    .foregroundColor(.textSecondary)
                                Text(alert.message)
                                    .font(ClavisTypography.body)
                                    .foregroundColor(.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            Text(alert.createdAt.formatted(date: .omitted, time: .shortened))
                                .font(ClavisTypography.footnote)
                                .foregroundColor(.textSecondary)
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }
}

private struct TickerRecentNewsCard: View {
    let stories: [NewsItem]

    var body: some View {
        ClavisFlushListCard(fill: .surface) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline) {
                    CX2SectionLabel(text: "Recent news")
                    Spacer()
                    Text("All news")
                        .font(ClavisTypography.body)
                        .foregroundColor(.informational)
                }
                .padding(.vertical, 12)

                VStack(spacing: 0) {
                    ForEach(stories) { story in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                if let ticker = story.ticker {
                                    Text(ticker)
                                        .font(ClavisTypography.label)
                                        .foregroundColor(.textSecondary)
                                }

                                Spacer()

                                if let source = story.source, !source.isEmpty {
                                    Text(source)
                                        .font(ClavisTypography.footnote)
                                        .foregroundColor(.textSecondary)
                                }
                            }

                            Text(story.title)
                                .font(ClavisTypography.bodyEmphasis)
                                .foregroundColor(.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            if let summary = story.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(summary)
                                    .font(ClavisTypography.footnote)
                                    .foregroundColor(.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack {
                                if let publishedAt = story.publishedAt {
                                    Text(publishedAt.formatted(date: .omitted, time: .shortened))
                                        .font(ClavisTypography.footnote)
                                        .foregroundColor(.textTertiary)
                                }
                                Spacer()
                            }
                        }
                        .padding(.vertical, 12)

                        if story.id != stories.last?.id {
                            Divider().overlay(Color.border)
                        }
                    }
                }
            }
        }
    }
}

private struct WhyThisGradeItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let horizon: String?
}

private struct TickerWhyThisGradeCard: View {
    let items: [WhyThisGradeItem]

    var body: some View {
        ClavisFlushListCard(fill: .surface) {
            VStack(alignment: .leading, spacing: 0) {
                CX2SectionLabel(text: "Why this grade")
                    .padding(.vertical, 12)

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 8) {
                                Text(item.title)
                                    .font(ClavisTypography.bodyEmphasis)
                                    .foregroundColor(.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)

                                if let horizon = item.horizon, !horizon.isEmpty {
                                    Text(horizon.capitalized)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.textSecondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                            }

                            Text(item.detail)
                                .font(ClavisTypography.footnote)
                                .foregroundColor(.textSecondary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 12)

                        if index < items.count - 1 {
                            Divider().overlay(Color.border)
                        }
                    }
                }
            }
        }
    }
}

struct TickerSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [TickerSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                        TextField("Search tickers", text: $query)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, newValue in
                            Task { await search(newValue) }
                        }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.riskF)
                    }
                }

                if isSearching {
                    Section {
                        ProgressView()
                    }
                }

                Section("Results") {
                    ForEach(results) { result in
                        NavigationLink(destination: TickerDetailView(ticker: result.ticker)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.ticker)
                                        .font(ClavisTypography.bodyEmphasis)
                                    Text(result.companyName)
                                        .font(ClavisTypography.footnote)
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                GradeBadge(grade: result.grade ?? "—", size: .compact)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search Tickers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func search(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            errorMessage = nil
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let fetched = try await APIService.shared.searchTickers(query: trimmed, limit: 50)
            results = prioritizedResults(fetched, query: trimmed)
            errorMessage = nil
        } catch {
            results = []
            errorMessage = ClavisCopy.Errors.tickerSearch(error)
        }
    }

    private func prioritizedResults(_ results: [TickerSearchResult], query: String) -> [TickerSearchResult] {
        let normalizedQuery = query.uppercased()

        return results.sorted { left, right in
            let leftRank = searchRank(for: left, query: normalizedQuery)
            let rightRank = searchRank(for: right, query: normalizedQuery)

            if leftRank != rightRank {
                return leftRank < rightRank
            }

            return left.ticker < right.ticker
        }
    }

    private func searchRank(for result: TickerSearchResult, query: String) -> Int {
        let ticker = result.ticker.uppercased()
        let company = result.companyName.uppercased()

        if ticker == query { return 0 }
        if ticker.hasPrefix(query) { return 1 }
        if company.hasPrefix(query) { return 2 }
        if ticker.contains(query) { return 3 }
        if company.contains(query) { return 4 }
        return 5
    }
}
