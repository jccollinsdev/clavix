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
                    snapshotSection(digest)
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

    // MARK: - Snapshot (grade mix + risk radar)

    @ViewBuilder
    private func snapshotSection(_ digest: Digest) -> some View {
        let dist = gradeDistribution()
        let axes = radarAxes()
        let hasRadar = axes.contains(where: { $0.value > 0 })
        let hasPie = !dist.isEmpty
        if hasRadar || hasPie {
            ClavixCard {
                VStack(alignment: .leading, spacing: 10) {
                    ClavixEyebrow("Your risk profile")
                    HStack(alignment: .center, spacing: 12) {
                        if hasRadar {
                            MiniRiskRadar(axes: axes)
                                .frame(width: 148, height: 132)
                        }
                        if hasRadar && hasPie {
                            Spacer(minLength: 0)
                        }
                        if hasPie {
                            HStack(spacing: 10) {
                                GradePieChart(dist: dist)
                                    .frame(width: 64, height: 64)
                                gradeMixLegend(dist)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func gradeDistribution() -> [(band: String, count: Int, color: Color)] {
        let order = ["A", "B", "C", "D", "F"]
        var counts: [String: Int] = [:]
        for holding in viewModel.holdings {
            let grade = viewModel.grade(for: holding.ticker).uppercased()
            guard let first = grade.first.map(String.init), order.contains(first) else { continue }
            counts[first, default: 0] += 1
        }
        return order.compactMap { band in
            let count = counts[band] ?? 0
            return count > 0 ? (band, count, ClavisGradeStyle.riskColor(for: band)) : nil
        }
    }

    private func gradeMixLegend(_ dist: [(band: String, count: Int, color: Color)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(dist, id: \.band) { seg in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(seg.color).frame(width: 9, height: 9)
                    Text(seg.band)
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixInk2)
                    Text("\(seg.count)")
                        .font(ClavisTypography.clavixMono(12, weight: .bold))
                        .foregroundColor(.clavixInk)
                }
            }
        }
    }

    private func radarAxes() -> [(label: String, value: Double)] {
        let order = ["FIN", "NEWS", "MAC", "SEC", "VOL"]
        var byCode: [String: Double] = [:]
        for dim in viewModel.today?.dimensions ?? [] {
            byCode[dim.code.uppercased()] = dim.score ?? 0
        }
        return order.map { ($0, byCode[$0] ?? 0) }
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
                                    .padding(.vertical, 10)
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
        let items = digest.structuredSections?.whatToWatchToday?.catalysts ?? []
        // Keep the section numbers contiguous when the watchlist is hidden.
        let roman = watchlistAlertItems(digest).isEmpty ? "IV" : "V"
        return ReportRomanSection(roman, "What to Watch") {
            if items.isEmpty {
                ClavixCard {
                    Text("No scheduled events surfaced for your portfolio today.")
                        .font(ClavisTypography.clavixCaption)
                        .foregroundColor(.clavixInk3)
                }
            } else {
                ClavixCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            whatToWatchRow(item)
                            if index < items.count - 1 {
                                Rectangle()
                                    .fill(Color.clavixInk4)
                                    .frame(height: 2)
                                    .padding(.vertical, 12)
                            }
                        }
                    }
                }
            }
        }
    }

    private func whatToWatchRow(_ item: DigestWhatMattersItem) -> some View {
        let ticker = whatToWatchTicker(item)
        return VStack(alignment: .leading, spacing: 8) {
            if let ticker {
                HStack(spacing: 8) {
                    Text(ticker)
                        .font(ClavisTypography.clavixMono(14, weight: .bold))
                        .foregroundColor(.clavixInk)
                    ClavixGradeBadge(viewModel.grade(for: ticker), size: 22)
                    Spacer()
                }
                Rectangle().fill(Color.clavixRule).frame(height: 1)
            }
            Text(whatToWatchBody(item, ticker: ticker))
                .font(ClavisTypography.clavixSerif(15))
                .foregroundColor(.clavixInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func whatToWatchTicker(_ item: DigestWhatMattersItem) -> String? {
        guard let raw = item.impactedPositions.first?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let upper = raw.uppercased()
        if upper == "FED" || upper == "MACRO" { return nil }
        return upper
    }

    private func whatToWatchBody(_ item: DigestWhatMattersItem, ticker: String?) -> String {
        var text = cleanWatchText(item)
        if let ticker {
            for prefix in ["\(ticker): ", "\(ticker) — ", "\(ticker) - "] where text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                break
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let (preview, isTruncated) = truncatedText(item.brief.sanitizedDisplayText, limit: 100)
        return VStack(alignment: .leading, spacing: 4) {
            Text(preview)
                .font(ClavisTypography.clavixSerif(16))
                .foregroundColor(.clavixInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isTruncated {
                Text("Read more →")
                    .font(ClavisTypography.clavixMono(11, weight: .semibold))
                    .foregroundColor(.clavixAccent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func cleanWatchText(_ item: DigestWhatMattersItem) -> String {
        let raw = item.catalyst.sanitizedDisplayText
        let (_, _, title) = parseCalendarLine(raw, tickers: item.impactedPositions)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? raw : t
    }

    private func parseCalendarLine(_ raw: String, tickers: [String]) -> (String, String, String) {
        let parts = raw.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        let timeRegex = try? NSRegularExpression(pattern: "^\\d{1,2}:\\d{2}$")
        if let first = parts.first,
           let regex = timeRegex,
           regex.firstMatch(in: first, range: NSRange(first.startIndex..., in: first)) != nil,
           parts.count >= 2 {
            let time = first
            let typeOrWord = parts[1]
            let isType = typeOrWord.uppercased() == typeOrWord && typeOrWord.count <= 6
            if isType, parts.count >= 3 {
                return (time, typeOrWord, parts[2].sanitizedDisplayText)
            }
            return (time, calendarType(tickers), parts.dropFirst().joined(separator: " ").sanitizedDisplayText)
        }
        return ("—", calendarType(tickers), raw.sanitizedDisplayText)
    }

    private func calendarType(_ tickers: [String]) -> String {
        if tickers.contains(where: { $0.uppercased() == "FED" || $0.uppercased() == "MACRO" }) { return "FED" }
        if !tickers.isEmpty { return "EARN" }
        return "DATA"
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

// MARK: - Mini risk radar (static 5-dimension shape)

private struct GradePieChart: View {
    let dist: [(band: String, count: Int, color: Color)]

    var body: some View {
        GeometryReader { geo in
            let total = max(dist.reduce(0) { $0 + $1.count }, 1)
            let radius = min(geo.size.width, geo.size.height) / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                ForEach(Array(slices(total: total).enumerated()), id: \.offset) { _, slice in
                    Path { p in
                        p.move(to: center)
                        p.addArc(center: center, radius: radius - 0.5, startAngle: slice.start, endAngle: slice.end, clockwise: false)
                        p.closeSubpath()
                    }
                    .fill(slice.color)
                }
                Circle().stroke(Color.clavixRule, lineWidth: 1)
            }
        }
    }

    private func slices(total: Int) -> [(start: Angle, end: Angle, color: Color)] {
        var result: [(Angle, Angle, Color)] = []
        var current = -90.0
        for seg in dist {
            let sweep = 360.0 * Double(seg.count) / Double(total)
            result.append((.degrees(current), .degrees(current + sweep), seg.color))
            current += sweep
        }
        return result
    }
}

private struct RadarPolygon: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

private func radarVertex(center: CGPoint, radius: CGFloat, index: Int, count: Int) -> CGPoint {
    let angle = (-90.0 + 360.0 / Double(count) * Double(index)) * .pi / 180.0
    return CGPoint(
        x: center.x + radius * CGFloat(cos(angle)),
        y: center.y + radius * CGFloat(sin(angle))
    )
}

private struct MiniRiskRadar: View {
    let axes: [(label: String, value: Double)]

    var body: some View {
        GeometryReader { geo in
            let n = max(axes.count, 3)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 * 0.55
            let dataPts = axes.enumerated().map { index, axis -> CGPoint in
                let clamped = max(0, min(100, axis.value))
                return radarVertex(center: center, radius: radius * CGFloat(clamped / 100), index: index, count: n)
            }
            ZStack {
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { fraction in
                    RadarPolygon(points: (0..<n).map {
                        radarVertex(center: center, radius: radius * CGFloat(fraction), index: $0, count: n)
                    })
                    .stroke(Color.clavixRule, lineWidth: fraction == 1.0 ? 1 : 0.5)
                }
                ForEach(0..<n, id: \.self) { i in
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: radarVertex(center: center, radius: radius, index: i, count: n))
                    }
                    .stroke(Color.clavixRule, lineWidth: 0.5)
                }
                RadarPolygon(points: dataPts).fill(Color.clavixAccent.opacity(0.22))
                RadarPolygon(points: dataPts).stroke(Color.clavixAccent, lineWidth: 2)
                ForEach(dataPts.indices, id: \.self) { i in
                    Circle().fill(Color.clavixAccent).frame(width: 4, height: 4).position(dataPts[i])
                }
                ForEach(axes.indices, id: \.self) { i in
                    let label = radarVertex(center: center, radius: radius + 13, index: i, count: n)
                    Text("\(axes[i].label) \(Int(axes[i].value.rounded()))")
                        .font(ClavisTypography.clavixMono(8, weight: .medium))
                        .foregroundColor(.clavixInk2)
                        .fixedSize()
                        .position(x: label.x, y: label.y)
                }
            }
        }
    }
}
