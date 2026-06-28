import SwiftUI

struct MorningReportView: View {
    @ObservedObject var viewModel: DigestViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var expandedPosition: DigestPositionImpact?
    @State private var expandedSector: DigestSectorOverviewItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.todayDigest.map(reportTitle(for:)) ?? "Morning Digest")
                    .font(ClavisTypography.clavixSerif(28, weight: .medium))
                    .tracking(-0.5)
                    .foregroundColor(.clavixInk)
                    .padding(.top, 4)

                if let digest = viewModel.todayDigest {
                    if let latestDigestMessage = latestDigestMessage(for: digest) {
                        ClavixInlineNoticeCard(
                            eyebrow: "Latest Available",
                            title: "Showing the most recent saved briefing",
                            message: latestDigestMessage,
                            footnote: "Use Holdings for the live book. Saved briefings can lag behind new positions, removals, watchlist edits, or refreshed scores.",
                            glyph: "clock.arrow.circlepath",
                            fill: .clavixPaper2,
                            secondary: .clavixInk3
                        )
                    }
                    masthead(digest)
                    macroSection(digest)
                    sectorSection(digest)
                    positionsSection(digest)
                    watchlistSection(digest)
                    whatToWatchSection(digest)
                    methodologyCard(digest)
                } else {
                    ClavixInlineNoticeCard(
                        eyebrow: "Not yet generated",
                        title: "Your first Morning Report is on its way",
                        message: "Clavix generates a personalised Morning Report each weekday morning using the positions in your book. Check back tomorrow. Once your portfolio has been through a full analysis cycle, the briefing will appear here.",
                        footnote: "Reports run overnight. Your portfolio risk grades and the Today tab update independently and are already live.",
                        glyph: "newspaper"
                    )
                }
            }
            .padding(.horizontal, ClavixLayout.pad)
            .padding(.top, 8)
            .padding(.bottom, ClavixLayout.bottomPad)
        }
        .background(Color.clavixPage.ignoresSafeArea())
        .sheet(item: $expandedPosition) { positionDetailSheet($0) }
        .sheet(item: $expandedSector) { sectorDetailSheet($0) }
        .safeAreaInset(edge: .top, spacing: 0) {
            morningReportBar
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var morningReportBar: some View {
        ZStack {
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.clavixInk)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            Text("CLAVIX")
                .font(ClavisTypography.clavixMono(21, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.clavixInk)
        }
        .padding(.horizontal, ClavixLayout.pad)
        .padding(.vertical, 10)
        .background(Color.clavixPage.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.clavixRule).frame(height: 1) }
    }

    // MARK: - Portfolio rating hero

    private func masthead(_ digest: Digest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ClavixEyebrow("Portfolio rating")
            HStack(alignment: .center, spacing: 12) {
                ClavixGradeBadge(portfolioGrade(digest), size: 44)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(compositeScoreDisplay(digest))
                        .font(ClavisTypography.clavixMono(32, weight: .semibold))
                        .foregroundColor(.clavixInk)
                    Text("/100")
                        .font(ClavisTypography.clavixMono(12, weight: .regular))
                        .foregroundColor(.clavixInk3)
                }
                Spacer(minLength: 8)
                mastheadDelta()
            }
            Text(mastheadDateLabel(digest))
                .font(ClavisTypography.clavixMono(10, weight: .regular))
                .tracking(0.7)
                .foregroundColor(.clavixInk3)
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.clavixRule).frame(height: 1) }
    }

    // How much the portfolio score moved since the last trading day. Hidden on
    // weekends (markets closed, so nothing changed) and when there is no move.
    @ViewBuilder
    private func mastheadDelta() -> some View {
        if let delta = portfolioScoreDelta() {
            let up = delta >= 0
            HStack(spacing: 4) {
                Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("\(abs(Int(delta.rounded())))")
                    .font(ClavisTypography.clavixMono(15, weight: .bold))
            }
            .foregroundColor(up ? .clavixGood : .clavixBad)
            .overlay(alignment: .topTrailing) {
                if let day = lastTradingDayLabel() {
                    Text("vs \(day)")
                        .font(ClavisTypography.clavixMono(9, weight: .regular))
                        .foregroundColor(.clavixInk3)
                        .fixedSize()
                        .offset(y: -11)
                }
            }
        }
    }

    private func portfolioScoreDelta() -> Double? {
        guard !isWeekendEastern() else { return nil }
        guard let portfolio = viewModel.today?.portfolio else { return nil }
        let delta: Double?
        if let d = portfolio.scoreDelta {
            delta = d
        } else if let current = portfolio.compositeScore, let prev = portfolio.previousScore {
            delta = current - prev
        } else {
            delta = nil
        }
        guard let d = delta, abs(d) >= 0.5 else { return nil }
        return d
    }

    private func isWeekendEastern() -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let weekday = cal.component(.weekday, from: Date())
        return weekday == 1 || weekday == 7  // Sunday or Saturday
    }

    private func lastTradingDayLabel() -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        guard var day = cal.date(byAdding: .day, value: -1, to: Date()) else { return nil }
        var hops = 0
        while hops < 7 {
            let weekday = cal.component(.weekday, from: day)
            if weekday != 1 && weekday != 7 { break }
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
            hops += 1
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = cal.timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: day)
    }

    // MARK: - Macro overnight

    private func macroSection(_ digest: Digest) -> some View {
        let section = digest.structuredSections?.overnightMacro
        return ReportRomanSection("I", "Macro overnight") {
            Text(section?.brief.sanitizedDisplayText ?? "Overnight macro section is being generated.")
                .font(ClavisTypography.clavixSerif(16))
                .foregroundColor(.clavixInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Your sectors

    private func sectorSection(_ digest: Digest) -> some View {
        let sectorHeat = digest.structuredSections?.sectorHeat ?? []
        let todaySectors = viewModel.today?.sectorExposure ?? []
        let sectorBriefs = sectorHeat.filter {
            !$0.brief.sanitizedDisplayText.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let briefs = Array(sectorBriefs.prefix(8))
        return ReportRomanSection("II", "Your sectors") {
            if !briefs.isEmpty {
                ClavixCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(briefs.enumerated()), id: \.element.id) { index, item in
                            Button { expandedSector = item } label: {
                                sectorBriefRow(item)
                            }
                            .buttonStyle(.plain)
                            if index < briefs.count - 1 {
                                Rectangle().fill(Color.clavixRule).frame(height: 1)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }

            if !todaySectors.isEmpty {
                ClavixCard(padding: 0) {
                    SectorHeatmapView(
                        items: todaySectors.prefix(6).map { s in
                            SectorHeatmapItem(
                                id: s.sector,
                                symbol: s.etf ?? "—",
                                name: s.sector.humanizedTitleCasedDisplayText,
                                weight: s.portfolioWeightPct / 100.0,
                                changePct: s.etfDayChangePct
                            )
                        }
                    )
                    .frame(height: SectorHeatmapView.height(for: todaySectors.count))
                }
            } else if !sectorHeat.isEmpty {
                ClavixCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(sectorHeat.prefix(3).enumerated()), id: \.element.id) { index, sector in
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("—")
                                        .font(ClavisTypography.clavixMono(12, weight: .bold))
                                        .foregroundColor(.clavixInk)
                                    Text(sector.sector.humanizedTitleCasedDisplayText)
                                        .font(ClavisTypography.clavixCaption)
                                        .foregroundColor(.clavixInk2)
                                        .lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(12)
                            if index < min(sectorHeat.count, 3) - 1 {
                                Rectangle().fill(Color.clavixRule).frame(height: 1)
                            }
                        }
                    }
                }
            } else {
                ClavixCard {
                    Text("Sector detail is being assembled for your holdings.")
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixInk3)
                }
            }
        }
    }

    // MARK: - Position changes

    private func positionsSection(_ digest: Digest) -> some View {
        let positions = digest.structuredSections?.positions ?? []
        return ReportRomanSection("III", "Position changes") {
            if positions.isEmpty {
                ClavixCard {
                    Text("No material position changes in this briefing.")
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixInk3)
                }
            } else {
                ForEach(positions, id: \.id) { item in
                    Button { expandedPosition = item } label: {
                        positionCard(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func positionCard(_ item: DigestPositionImpact) -> some View {
        let (preview, isTruncated) = truncatedText(fullBlurb(item), limit: 100)
        return ClavixCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Text(item.ticker)
                        .font(ClavisTypography.clavixMono(14, weight: .bold))
                        .foregroundColor(.clavixInk)
                    Spacer()
                    HStack(spacing: 8) {
                        ClavixGradeBadge(viewModel.grade(for: item.ticker), size: 22)
                        Text(deltaText(item.ticker))
                            .font(ClavisTypography.clavixMono(10, weight: .bold))
                            .foregroundColor(deltaTone(item.ticker))
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                Text(preview)
                    .font(ClavisTypography.clavixCaption)
                    .foregroundColor(.clavixInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isTruncated {
                    Text("Read more →")
                        .font(ClavisTypography.clavixMono(11, weight: .semibold))
                        .foregroundColor(.clavixAccent)
                }
            }
        }
    }

    private func fullBlurb(_ item: DigestPositionImpact) -> String {
        // Just the connected-dots impact summary. We no longer staple a raw
        // forward-looking watch-item fragment onto the end (it read as an
        // incomplete sentence). Watch items live in their own sections now.
        let main = item.impactSummary.sanitizedDisplayText.trimmingCharacters(in: .whitespacesAndNewlines)
        return main.isEmpty ? "No standout change for this holding today." : main
    }

    // MARK: - Watchlist alerts

    // Only real events: a holding crossing a whole letter grade, or material
    // news. When nothing happened we hide the whole section (header included)
    // rather than showing a placeholder.
    @ViewBuilder
    private func watchlistSection(_ digest: Digest) -> some View {
        let items = watchlistAlertItems(digest)
        if !items.isEmpty {
            ReportRomanSection("IV", "Watchlist alerts") {
                ClavixCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            Text(item)
                                .font(ClavisTypography.clavixSerif(15))
                                .foregroundColor(.clavixInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if index < items.count - 1 {
                                Rectangle().fill(Color.clavixRule).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - What to Watch

    private func whatToWatchSection(_ digest: Digest) -> some View {
        let brief = digest.structuredSections?.whatToWatchToday?.brief?.sanitizedDisplayText
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Keep the section numbers contiguous when the watchlist is hidden.
        let roman = watchlistAlertItems(digest).isEmpty ? "IV" : "V"
        return ReportRomanSection(roman, "What to Watch") {
            ClavixCard {
                Text(brief.isEmpty
                    ? "Nothing in today's macro, sector, or company flow rose to the level of a portfolio call to action."
                    : brief)
                    .font(ClavisTypography.clavixSerif(16))
                    .foregroundColor(brief.isEmpty ? .clavixInk3 : .clavixInk)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Generated by card (no section header)

    private func methodologyCard(_ digest: Digest) -> some View {
        ClavixCard(padding: 12, fill: .clavixPaper2) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Generated by Clavix at \(digest.generatedAt.formatted(date: .omitted, time: .shortened)).")
                    .font(ClavisTypography.clavixCaption)
                    .foregroundColor(.clavixInk3)
                NavigationLink(destination: MethodologyView()) {
                    Text("View methodology →")
                        .font(ClavisTypography.clavixMono(11, weight: .semibold))
                        .foregroundColor(.clavixAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func portfolioGrade(_ digest: Digest) -> String {
        if let grade = viewModel.today?.portfolio.grade, !grade.isEmpty { return grade }
        if let weighted = PortfolioMath.weightedScore(viewModel.holdings), weighted > 0 {
            return PortfolioMath.weightedGrade(viewModel.holdings)
        }
        return digest.structuredSections?.header?.portfolioGrade ?? digest.overallGrade ?? "—"
    }

    private func portfolioScoreValue(_ digest: Digest) -> Double? {
        if let score = viewModel.today?.portfolio.compositeScore { return score }
        if let weighted = PortfolioMath.weightedScore(viewModel.holdings) { return weighted }
        return digest.overallScore
    }

    private func compositeScoreDisplay(_ digest: Digest) -> String {
        guard let score = portfolioScoreValue(digest) else { return "—" }
        return "\(Int(score.rounded()))"
    }

    private func mastheadDateLabel(_ digest: Digest) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: digest.generatedAt).uppercased()
    }

    private func reportTitle(for digest: Digest) -> String {
        isDigestFromToday(digest) ? "Morning Digest" : "Latest Morning Digest"
    }

    private func latestDigestMessage(for digest: Digest) -> String? {
        guard !isDigestFromToday(digest) else { return nil }
        return "This digest was generated on \(mastheadDateLabel(digest)) and may not reflect holdings, watchlist, or score changes made after that time."
    }

    private func isDigestFromToday(_ digest: Digest) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar.isDate(digest.generatedAt, inSameDayAs: Date())
    }

    private func deltaText(_ ticker: String) -> String {
        guard let delta = viewModel.scoreDelta(for: ticker) else { return "—" }
        if delta == 0 { return "—" }
        return delta > 0 ? "+\(delta)" : "\(delta)"
    }

    private func deltaTone(_ ticker: String) -> Color {
        guard let delta = viewModel.scoreDelta(for: ticker) else { return .clavixInk3 }
        if delta == 0 { return .clavixInk3 }
        return delta > 0 ? .clavixGood : .clavixBad
    }

    private func watchlistAlertItems(_ digest: Digest) -> [String] {
        (digest.structuredSections?.watchlistUpdates?.alerts ?? [])
            .map { $0.sanitizedDisplayText }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Cut a blurb to a preview length on a word boundary. Returns the preview
    /// and whether anything was trimmed off.
    private func truncatedText(_ text: String, limit: Int) -> (String, Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return (trimmed, false) }
        let endIdx = trimmed.index(trimmed.startIndex, offsetBy: limit)
        var cut = String(trimmed[..<endIdx])
        if let lastSpace = cut.lastIndex(of: " ") {
            cut = String(cut[..<lastSpace])
        }
        return (cut.trimmingCharacters(in: .whitespaces) + "…", true)
    }

    private func sectorBriefRow(_ item: DigestSectorOverviewItem) -> some View {
        HStack(spacing: 8) {
            Text(item.sector.humanizedTitleCasedDisplayText)
                .font(ClavisTypography.clavixSerif(16))
                .foregroundColor(.clavixInk)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.clavixInk3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Detail sheets (tap to read the full write-up)

    private func positionDetailSheet(_ item: DigestPositionImpact) -> some View {
        let ticker = item.ticker
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ClavixEyebrow("Position change")
                HStack(alignment: .center, spacing: 12) {
                    Text(ticker)
                        .font(ClavisTypography.clavixMono(28, weight: .bold))
                        .foregroundColor(.clavixInk)
                    ClavixGradeBadge(viewModel.grade(for: ticker), size: 28)
                    Spacer()
                    Text(deltaText(ticker))
                        .font(ClavisTypography.clavixMono(14, weight: .bold))
                        .foregroundColor(deltaTone(ticker))
                }
                Rectangle().fill(Color.clavixRule).frame(height: 1)
                Text(fullBlurb(item))
                    .font(ClavisTypography.clavixSerif(18))
                    .foregroundColor(.clavixInk)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(ClavixLayout.pad)
            .padding(.top, 12)
        }
        .background(Color.clavixPage.ignoresSafeArea())
        .presentationDetents([.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
    }

    private func sectorDetailSheet(_ item: DigestSectorOverviewItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ClavixEyebrow("Sector")
                Text(item.sector.humanizedTitleCasedDisplayText)
                    .font(ClavisTypography.clavixSerif(26, weight: .medium))
                    .foregroundColor(.clavixInk)
                Rectangle().fill(Color.clavixRule).frame(height: 1)
                Text(item.brief.sanitizedDisplayText)
                    .font(ClavisTypography.clavixSerif(18))
                    .foregroundColor(.clavixInk)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(ClavixLayout.pad)
            .padding(.top, 12)
        }
        .background(Color.clavixPage.ignoresSafeArea())
        .presentationDetents([.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
    }

}

private struct ReportRomanSection<Content: View>: View {
    let roman: String
    let title: String
    @ViewBuilder let content: Content

    init(_ roman: String, _ title: String, @ViewBuilder content: () -> Content) {
        self.roman = roman
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("§ \(roman)")
                    .font(ClavisTypography.clavixSerif(22, weight: .medium))
                    .foregroundColor(.clavixInk)
                Text(title)
                    .font(ClavisTypography.clavixSerif(22, weight: .medium))
                    .foregroundColor(.clavixInk)
                Spacer()
            }
            content
        }
        .padding(.top, 8)
    }
}
