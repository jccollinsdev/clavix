import SwiftUI

struct SectorExposureAuditView: View {
    @Environment(\.dismiss) private var dismiss
    let ticker: String
    let methodology: MethodologyResponse?
    var isETF: Bool = false

    private var dimension: MethodologySectorExposure? { methodology?.dimensions.sectorExposure }
    private var isReferenceMode: Bool { methodology == nil }

    @State private var tickerPoints: [PriceSeriesAnalytics.Point] = []
    @State private var sectorPoints: [PriceSeriesAnalytics.Point] = []
    @State private var loadedHistory = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                if isReferenceMode {
                    AuditReferenceContextView(
                        dimensionName: isETF ? "Concentration" : "Sector Resilience",
                        message: isETF
                            ? "Open a fund to inspect top-holding concentration from its latest constituent file."
                            : "Open a ticker from Search, Holdings, Alerts, or the Morning Report to inspect live sector beta, momentum, breadth, and narrative context for that stock."
                    )
                } else {
                    AuditHeaderCard(
                        title: isETF ? "Concentration" : "Sector Resilience",
                        ticker: ticker,
                        score: dimension?.score,
                        subtitle: isETF
                            ? "\(dimension?.holdingsCount ?? 0) reported holdings"
                            : "\(dimension?.sector ?? "Sector unavailable") \u{00B7} \(dimension?.sectorEtf ?? "ETF unavailable")"
                    )

                    if isETF {
                        concentrationHeroCard
                        concentrationCard
                    } else {
                        // Narrative first: set the scene before the numbers.
                        if let narrative = dimension?.narrative, !narrative.isEmpty {
                            AuditSectionCard(title: "Sector Backdrop") {
                                Text(cleanedNarrative(narrative))
                                    .font(ClavisTypography.body)
                                    .foregroundColor(.clavixInk3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        sectorHealthCard
                        sectorTrendCard
                        relativeStrengthCard
                    }
                }

                AuditSectionCard(title: "How to read this") {
                    Text(isETF
                         ? "Concentration measures how much of the fund is controlled by its largest reported holdings. Lower concentration generally improves diversification resilience."
                         : "Sector Resilience measures how exposed a stock is to the state of its sector. It weighs how the sector has been trading lately, how broadly it has been rising, and how much this stock amplifies its sector's moves.")
                        .font(ClavisTypography.body)
                        .foregroundColor(.clavixInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, ClavisTheme.screenPadding)
            .padding(.vertical, ClavisTheme.sectionSpacing)
        }
        .background(Color.clavixPage.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            ClavixReportBar(onBack: { dismiss() })
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: ticker) { await loadHistory() }
    }

    private func loadHistory() async {
        guard !isReferenceMode, !isETF, !loadedHistory else { return }
        let etf = dimension?.sectorEtf
        async let tickerResp = try? APIService.shared.fetchPriceHistory(ticker: ticker, days: 200)
        async let sectorResp: PriceHistoryResponse? = {
            guard let etf, !etf.isEmpty else { return nil }
            return try? await APIService.shared.fetchPriceHistory(ticker: etf, days: 200)
        }()
        let (t, s) = await (tickerResp, sectorResp)
        if let t { tickerPoints = PriceSeriesAnalytics.points(from: t.prices) }
        if let s { sectorPoints = PriceSeriesAnalytics.points(from: s.prices) }
        loadedHistory = true
    }

    // MARK: - Sector price trend (sparkline of the sector ETF)

    @ViewBuilder
    private var sectorTrendCard: some View {
        if sectorPoints.count > 5, let etf = dimension?.sectorEtf {
            let change90 = PriceSeriesAnalytics.percentChange(sectorPoints, days: 90)
            AuditSectionCard(title: "How \(etf) Has Traded") {
                if let change90 {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(signedPercent(change90))
                            .font(ClavisTypography.clavixMono(24, weight: .semibold))
                            .foregroundColor(change90 >= 0 ? .clavixGoodInk : .clavixBadInk)
                        Text("over 90 days")
                            .font(ClavisTypography.clavixMono(10, weight: .regular))
                            .foregroundColor(.clavixInk4)
                        Spacer()
                    }
                }
                MiniLineChart(points: Array(sectorPoints.suffix(126)),
                              color: (change90 ?? 0) >= 0 ? .clavixGoodInk : .clavixBadInk)
                    .frame(height: 60)
                Text("The actual price path of the \(dimension?.sector ?? "sector") ETF over roughly the last six months.")
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .foregroundColor(.clavixInk4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Relative strength + correlation (ticker vs its sector)

    @ViewBuilder
    private var relativeStrengthCard: some View {
        let rel = relativeStrength90
        let corr = PriceSeriesAnalytics.correlation(tickerPoints, other: sectorPoints, trailing: 120)
        if rel != nil || corr != nil {
            AuditSectionCard(title: "\(ticker) vs Its Sector") {
                if let rel {
                    AuditStatRow(
                        label: "Relative Strength (90-day)",
                        caption: "Its return minus the sector's",
                        value: signedPercent(rel),
                        valueColor: rel >= 0 ? .clavixGoodInk : .clavixBadInk,
                        pill: rel >= 0.02 ? "Outperforming" : (rel <= -0.02 ? "Lagging" : "In line"),
                        pillInk: rel >= 0.02 ? .clavixGoodInk : (rel <= -0.02 ? .clavixBadInk : .clavixInk3),
                        pillFill: rel >= 0.02 ? .clavixGoodSoft : (rel <= -0.02 ? .clavixBadSoft : .clavixPaper2),
                        explainer: relExplainer(rel)
                    )
                }
                if rel != nil, corr != nil {
                    Rectangle().fill(Color.clavixRule2).frame(height: 1)
                }
                if let corr {
                    AuditStatRow(
                        label: "Tracks Its Sector",
                        caption: "How tightly it moves with the group",
                        value: String(format: "%.2f", corr),
                        valueColor: .clavixInk,
                        pill: corrWord(corr),
                        pillInk: .clavixInk3,
                        pillFill: .clavixPaper2,
                        explainer: corrExplainer(corr)
                    )
                }
            }
        }
    }

    private var relativeStrength90: Double? {
        guard let t = PriceSeriesAnalytics.percentChange(tickerPoints, days: 90),
              let s = PriceSeriesAnalytics.percentChange(sectorPoints, days: 90) else { return nil }
        return t - s
    }

    private func relExplainer(_ rel: Double) -> String {
        let mag = String(format: "%.1f%%", abs(rel) * 100)
        let sector = dimension?.sector ?? "its sector"
        if rel >= 0.02 { return "\(ticker) has outrun \(sector) by \(mag) over the past three months, a sign of its own momentum on top of the sector's." }
        if rel <= -0.02 { return "\(ticker) has trailed \(sector) by \(mag) over the past three months, lagging its own group." }
        return "\(ticker) has moved roughly in step with \(sector) over the past three months." }

    private func corrWord(_ c: Double) -> String {
        if c >= 0.7 { return "Tightly" }
        if c >= 0.4 { return "Loosely" }
        return "Barely"
    }
    private func corrExplainer(_ c: Double) -> String {
        let pct = Int((max(0, c) * 100).rounded())
        if c >= 0.7 { return "About \(pct)% of \(ticker)'s day-to-day movement lines up with its sector, so sector swings carry a lot of weight here." }
        if c >= 0.4 { return "Only a moderate share of \(ticker)'s moves line up with its sector, so a lot of what drives it is company-specific." }
        return "\(ticker) mostly moves on its own story rather than with its sector." }

    private func signedPercent(_ value: Double) -> String {
        String(format: "%+.1f%%", value * 100)
    }

    // MARK: - ETF concentration hero (top-10 weight + verdict)

    @ViewBuilder
    private var concentrationHeroCard: some View {
        if let top10 = dimension?.top10WeightPct {
            AuditSectionCard(title: "Concentration") {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.0f%%", top10))
                        .font(ClavisTypography.clavixMono(38, weight: .semibold))
                        .tracking(-1)
                        .foregroundColor(concentrationInk(top10))
                    Text("in the top 10")
                        .font(ClavisTypography.clavixMono(12, weight: .regular))
                        .foregroundColor(.clavixInk4)
                    Spacer(minLength: 8)
                    AuditSquareTag(text: concentrationWord(top10), ink: concentrationInk(top10), fill: concentrationSoft(top10))
                }
                Text(concentrationRead(top10: top10, top: dimension?.topHoldingWeightPct))
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func concentrationWord(_ top10: Double) -> String {
        if top10 >= 55 { return "Concentrated" }
        if top10 >= 35 { return "Balanced" }
        return "Diversified"
    }
    private func concentrationInk(_ top10: Double) -> Color {
        if top10 >= 55 { return .clavixBadInk }
        if top10 >= 35 { return .clavixWarnInk }
        return .clavixGoodInk
    }
    private func concentrationSoft(_ top10: Double) -> Color {
        if top10 >= 55 { return .clavixBadSoft }
        if top10 >= 35 { return .clavixWarnSoft }
        return .clavixGoodSoft
    }
    private func concentrationRead(top10: Double, top: Double?) -> String {
        let topClause = top.map { String(format: " Its single biggest position is %.0f%% of the fund.", $0) } ?? ""
        let base: String
        if top10 >= 55 {
            base = "The ten largest holdings make up over half the fund, so its returns hinge on a handful of names."
        } else if top10 >= 35 {
            base = "The top ten carry a meaningful but not dominant share, a fairly typical spread for a focused fund."
        } else {
            base = "No small group of holdings dominates, so the fund is well spread across its constituents."
        }
        return base + topClause
    }

    // MARK: - ETF weight-breakdown donut

    @ViewBuilder
    private var concentrationCard: some View {
        if let top = dimension?.topHoldingWeightPct, let top10 = dimension?.top10WeightPct, top10 >= top {
            let next9 = max(0, top10 - top)
            let rest = max(0, 100 - top10)
            let slices = [
                AuditDonutSlice(id: "top", label: "Top holding", value: top, color: .clavixWarn),
                AuditDonutSlice(id: "next9", label: "Next 9", value: next9, color: .clavixAccent),
                AuditDonutSlice(id: "rest", label: "Rest of fund", value: rest, color: .clavixGood),
            ]
            AuditSectionCard(title: "Weight Breakdown") {
                HStack(alignment: .center, spacing: 18) {
                    AuditDonutChart(
                        slices: slices,
                        centerPrimary: "\(dimension?.holdingsCount ?? 0)",
                        centerDetail: "holdings"
                    )
                    .frame(width: 112, height: 112)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(slices) { slice in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(slice.color).frame(width: 9, height: 9)
                                Text(slice.label)
                                    .font(ClavisTypography.inter(13, weight: .medium))
                                    .foregroundColor(.clavixInk)
                                Spacer(minLength: 8)
                                Text("\(Int(slice.value.rounded()))%")
                                    .font(ClavisTypography.clavixMono(13, weight: .semibold))
                                    .foregroundColor(.clavixInk)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Slices show what share of the fund sits in its single largest holding, the next nine, and everything else.")
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .foregroundColor(.clavixInk4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Stock sector health

    private var sectorHealthCard: some View {
        AuditSectionCard(title: "Sector Health") {
            trendRow
            Rectangle().fill(Color.clavixRule2).frame(height: 1)
            momentumRow
            Rectangle().fill(Color.clavixRule2).frame(height: 1)
            betaRow
        }
    }

    // Positive-day ratio of the sector ETF over the last ~30 trading days — i.e.
    // how often the sector itself closed higher, NOT how many stocks advanced.
    @ViewBuilder
    private var trendRow: some View {
        if let breadth = dimension?.sectorBreadth {
            let clamped = max(0, min(1, breadth))
            let upDays = Int((clamped * 30).rounded())
            let downDays = max(0, 30 - upDays)
            let slices = [
                AuditDonutSlice(id: "up", label: "Up days", value: Double(upDays), color: .clavixGood),
                AuditDonutSlice(id: "down", label: "Down days", value: Double(downDays), color: .clavixBad),
            ]
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Sector Trend")
                    .font(ClavisTypography.inter(14, weight: .semibold))
                    .foregroundColor(.clavixInk)
                Text("How often \(dimension?.sectorEtf ?? "the sector") closed higher over the last 30 trading days")
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .foregroundColor(.clavixInk3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .center, spacing: 18) {
                    AuditDonutChart(slices: slices, centerPrimary: "\(Int((clamped * 100).rounded()))%", centerDetail: "up days")
                        .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(slices) { slice in
                            HStack(spacing: 8) {
                                Circle().fill(slice.color).frame(width: 8, height: 8)
                                Text(slice.label)
                                    .font(ClavisTypography.inter(13, weight: .medium))
                                    .foregroundColor(.clavixInk)
                                Spacer(minLength: 8)
                                Text("\(Int(slice.value))")
                                    .font(ClavisTypography.clavixMono(13, weight: .semibold))
                                    .foregroundColor(.clavixInk)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 4)
        } else {
            unavailableRow(label: "Recent Sector Trend", caption: "How often the sector has closed higher lately")
        }
    }

    @ViewBuilder
    private var momentumRow: some View {
        if let momentum = dimension?.sectorMomentum30d {
            let isUp = momentum >= 0
            AuditStatRow(
                label: "Sector Momentum (30-day)",
                caption: "How the sector itself has been trading",
                value: percent(momentum),
                valueColor: isUp ? .clavixGoodInk : .clavixBadInk,
                pill: momentumStatus(momentum),
                pillInk: isUp ? .clavixGoodInk : .clavixBadInk,
                pillFill: isUp ? .clavixGoodSoft : .clavixBadSoft,
                explainer: momentumExplainer(momentum)
            )
        } else {
            unavailableRow(label: "Sector Momentum (30-day)", caption: "How the sector itself has been trading")
        }
    }

    @ViewBuilder
    private var betaRow: some View {
        if let beta = dimension?.sectorBeta {
            AuditStatRow(
                label: "Sector Sensitivity",
                caption: "How much it amplifies its sector",
                value: String(format: "%.2f\u{00D7}", beta),
                valueColor: .clavixInk,
                pill: betaWord(beta),
                pillInk: betaInk(beta),
                pillFill: betaSoft(beta),
                explainer: betaExplainer(beta)
            )
        } else {
            unavailableRow(label: "Sector Sensitivity", caption: "How much it amplifies its sector")
        }
    }

    private func unavailableRow(label: String, caption: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(ClavisTypography.inter(14, weight: .semibold))
                    .foregroundColor(.clavixInk)
                Text(caption)
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .foregroundColor(.clavixInk3)
            }
            Spacer(minLength: 8)
            Text("Unavailable")
                .font(ClavisTypography.clavixMono(13, weight: .semibold))
                .foregroundColor(.clavixInk4)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Copy helpers

    /// The backend builds this narrative by joining lowercase clauses with ". ",
    /// which leaves mid-string sentences uncapitalized ("...its sector. breadth
    /// has been constructive."). Capitalize the first letter of each sentence so
    /// it reads cleanly.
    private func cleanedNarrative(_ raw: String) -> String {
        var result = ""
        var capitalizeNext = true
        for char in raw {
            if capitalizeNext, char.isLetter {
                result.append(Character(char.uppercased()))
                capitalizeNext = false
            } else {
                result.append(char)
                if char == "." || char == "!" || char == "?" {
                    capitalizeNext = true
                }
            }
        }
        return result
    }

    private func momentumStatus(_ value: Double?) -> String {
        guard let value else { return "\u{2014}" }
        if value > 0.005 { return "Tailwind" }
        if value < -0.005 { return "Headwind" }
        return "Flat"
    }

    private func momentumExplainer(_ value: Double) -> String {
        let etf = dimension?.sectorEtf ?? "The sector"
        let mag = String(format: "%.1f%%", abs(value) * 100)
        if value > 0.005 {
            return "\(etf) is up \(mag) over the past 30 days: a tailwind for names in the group."
        }
        if value < -0.005 {
            return "\(etf) is down \(mag) over the past 30 days: a headwind this stock has to fight against."
        }
        return "\(etf) has been roughly flat over the past 30 days: neither a clear tailwind nor headwind."
    }

    private func betaWord(_ beta: Double) -> String {
        if beta >= 1.15 { return "Amplifies" }
        if beta >= 0.85 { return "In line" }
        return "Defensive"
    }
    private func betaInk(_ beta: Double) -> Color {
        if beta >= 1.15 { return .clavixWarnInk }
        if beta >= 0.85 { return .clavixInk3 }
        return .clavixGoodInk
    }
    private func betaSoft(_ beta: Double) -> Color {
        if beta >= 1.15 { return .clavixWarnSoft }
        if beta >= 0.85 { return .clavixPaper2 }
        return .clavixGoodSoft
    }
    private func betaExplainer(_ beta: Double) -> String {
        let sector = dimension?.sector ?? "its sector"
        let mag = String(format: "%.1f", beta)
        if beta >= 1.15 {
            return "When \(sector) moves 1%, \(ticker) has moved about \(mag)%: it amplifies its sector's swings, so a sector wobble lands harder here."
        }
        if beta >= 0.85 {
            return "\(ticker) has moved roughly step-for-step with \(sector), so it tracks the group closely."
        }
        return "When \(sector) moves 1%, \(ticker) has moved only about \(mag)%: it rides out sector swings more calmly than the group."
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "\u{2014}" }
        return String(format: "%+.1f%%", value * 100)
    }
}

// MARK: - Mini line chart (sector price sparkline)

private struct MiniLineChart: View {
    let points: [PriceSeriesAnalytics.Point]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let closes = points.map(\.close)
            let minC = closes.min() ?? 0
            let maxC = closes.max() ?? 1
            let span = max(maxC - minC, 0.0001)
            let n = points.count
            let pad = geo.size.height * 0.12
            let plotH = geo.size.height - pad * 2
            ZStack {
                if n >= 2 {
                    Path { p in
                        for i in 0..<n {
                            let x = CGFloat(i) / CGFloat(n - 1) * geo.size.width
                            let y = pad + (plotH - CGFloat((closes[i] - minC) / span) * plotH)
                            let pt = CGPoint(x: x, y: y)
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}
