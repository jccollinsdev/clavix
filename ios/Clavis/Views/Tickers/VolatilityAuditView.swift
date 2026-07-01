import SwiftUI

struct VolatilityAuditView: View {
    @Environment(\.dismiss) private var dismiss
    let ticker: String
    let methodology: MethodologyResponse?

    @State private var points: [PriceSeriesAnalytics.Point] = []
    @State private var benchmark: [PriceSeriesAnalytics.Point] = []
    @State private var loadedHistory = false

    private var dimension: MethodologyVolatility? { methodology?.dimensions.volatility }
    private var isReferenceMode: Bool { methodology == nil }

    // Annualized vol -> a typical single-day move (÷ √252 trading days).
    private let tradingDaysRoot = 252.0.squareRoot()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                if isReferenceMode {
                    AuditReferenceContextView(
                        dimensionName: "Price Stability",
                        message: "Open a ticker from Search, Holdings, Alerts, or the Morning Report to inspect live realized volatility, drawdown, and beta for that stock."
                    )
                } else {
                    AuditHeaderCard(
                        title: "Price Stability",
                        ticker: ticker,
                        score: dimension?.score,
                        subtitle: "Updated \(AuditSupport.formattedAsOfDate(dimension?.asOfDate))"
                    )

                    swingCard
                    drawdownCard
                    distributionCard
                    rangeCard
                    marketBehaviorCard
                }

                AuditSectionCard(title: "How to read this") {
                    Text("Price Stability is about how wild the ride has been. It looks at how much the price swings on a typical day, whether those swings are picking up or settling down, the worst fall from a high over the past year, and how it behaves when the market rises and falls.")
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
        guard !isReferenceMode, !loadedHistory else { return }
        async let tickerResp = try? APIService.shared.fetchPriceHistory(ticker: ticker, days: 365)
        async let spyResp = try? APIService.shared.fetchPriceHistory(ticker: "SPY", days: 365)
        let (t, s) = await (tickerResp, spyResp)
        if let t { points = PriceSeriesAnalytics.points(from: t.prices) }
        if let s { benchmark = PriceSeriesAnalytics.points(from: s.prices) }
        loadedHistory = true
    }

    // MARK: - Typical daily swing (translated from annualized realized vol)

    @ViewBuilder
    private var swingCard: some View {
        AuditSectionCard(title: "Typical Daily Swing") {
            if let vol30 = dimension?.realizedVol30d {
                let daily30 = vol30 / tradingDaysRoot
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "\u{00B1}%.1f%%", daily30 * 100))
                        .font(ClavisTypography.clavixMono(38, weight: .semibold))
                        .tracking(-1)
                        .foregroundColor(swingColor(vol30))
                    Text("a day")
                        .font(ClavisTypography.clavixMono(12, weight: .regular))
                        .foregroundColor(.clavixInk4)
                    Spacer(minLength: 8)
                    squareTag(trendWord, ink: trendInk, fill: trendSoft)
                }
                Text(swingExplainer(vol30: vol30, vol90: dimension?.realizedVol90d))
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(annualizedCaption(vol30: vol30, vol90: dimension?.realizedVol90d))
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .foregroundColor(.clavixInk4)
            } else {
                Text("Realized volatility unavailable for this stock.")
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
            }
        }
    }

    private func swingColor(_ vol30: Double) -> Color {
        switch vol30 {
        case ..<0.25: return .clavixGoodInk
        case 0.25..<0.50: return .clavixWarnInk
        default: return .clavixBadInk
        }
    }

    private var trendWord: String {
        guard let ratio = dimension?.volRatio else { return "Steady" }
        if ratio > 1.05 { return "Heating up" }
        if ratio < 0.95 { return "Calming down" }
        return "Steady"
    }
    private var trendInk: Color {
        guard let ratio = dimension?.volRatio else { return .clavixInk3 }
        if ratio > 1.05 { return .clavixWarnInk }
        if ratio < 0.95 { return .clavixGoodInk }
        return .clavixInk3
    }
    private var trendSoft: Color {
        guard let ratio = dimension?.volRatio else { return .clavixPaper2 }
        if ratio > 1.05 { return .clavixWarnSoft }
        if ratio < 0.95 { return .clavixGoodSoft }
        return .clavixPaper2
    }

    private func swingExplainer(vol30: Double, vol90: Double?) -> String {
        let d30 = String(format: "%.1f%%", (vol30 / tradingDaysRoot) * 100)
        guard let vol90 else {
            return "On a typical day over the last month, \(ticker)'s price has moved about \(d30) up or down."
        }
        let d90 = String(format: "%.1f%%", (vol90 / tradingDaysRoot) * 100)
        let tail: String
        if let ratio = dimension?.volRatio, ratio > 1.05 {
            tail = "bigger than the \(d90) it averaged over the past three months, so the ride is getting bumpier."
        } else if let ratio = dimension?.volRatio, ratio < 0.95 {
            tail = "smaller than the \(d90) it averaged over the past three months, so things are settling down."
        } else {
            tail = "in line with the \(d90) it averaged over the past three months, so the ride has been steady."
        }
        return "On a typical day over the last month, \(ticker) has swung about \(d30) up or down: \(tail)"
    }

    private func annualizedCaption(vol30: Double, vol90: Double?) -> String {
        let a30 = String(format: "%.0f%%", vol30 * 100)
        guard let vol90 else { return "Annualized volatility: \(a30) (30-day)." }
        let a90 = String(format: "%.0f%%", vol90 * 100)
        return "Annualized volatility: \(a30) over 30 days, \(a90) over 90 days."
    }

    // MARK: - Max drawdown (real price chart)

    @ViewBuilder
    private var drawdownCard: some View {
        AuditSectionCard(title: "Max Drawdown") {
            if let window = PriceSeriesAnalytics.drawdownWindow(points) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(percent(window.drawdownPct))
                        .font(ClavisTypography.clavixMono(34, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundColor(drawdownColor(window.drawdownPct))
                    Spacer(minLength: 8)
                    squareTag(drawdownWord(window.drawdownPct), ink: drawdownColor(window.drawdownPct), fill: drawdownSoft(window.drawdownPct))
                }
                DrawdownPriceChart(window: window, color: drawdownColor(window.drawdownPct))
                    .frame(height: 130)
                    .padding(.top, 4)
                HStack {
                    Text("Peak \(shortDate(window.peakDate))")
                        .font(ClavisTypography.clavixMono(9, weight: .regular))
                        .foregroundColor(.clavixInk4)
                    Spacer()
                    Text(window.recovered ? "Recovered since" : "Trough \(shortDate(window.troughDate))")
                        .font(ClavisTypography.clavixMono(9, weight: .regular))
                        .foregroundColor(.clavixInk4)
                }
                Text(drawdownExplainer(window))
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let drawdown = dimension?.maxDrawdown252d {
                // Fallback to the backend number while price history loads.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(percent(-abs(drawdown)))
                        .font(ClavisTypography.clavixMono(34, weight: .semibold))
                        .foregroundColor(drawdownColor(-abs(drawdown)))
                    Spacer(minLength: 8)
                    squareTag(drawdownWord(-abs(drawdown)), ink: drawdownColor(-abs(drawdown)), fill: drawdownSoft(-abs(drawdown)))
                }
                if !loadedHistory {
                    Text("Loading price history\u{2026}")
                        .font(ClavisTypography.clavixMono(9, weight: .regular))
                        .foregroundColor(.clavixInk4)
                }
            } else {
                Text("Drawdown unavailable for this stock.")
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
            }
        }
    }

    private func drawdownExplainer(_ window: PriceSeriesAnalytics.DrawdownWindow) -> String {
        let mag = String(format: "%.0f%%", abs(window.drawdownPct) * 100)
        let base = "From its high on \(shortDate(window.peakDate)), \(ticker) fell about \(mag) to its low on \(shortDate(window.troughDate))."
        return window.recovered
            ? base + " It has since climbed back above that high."
            : base + " It has not fully recovered that high yet."
    }

    private func drawdownWord(_ value: Double) -> String {
        switch abs(value) {
        case 0..<0.15: return "Mild"
        case 0.15..<0.35: return "Notable"
        default: return "Severe"
        }
    }
    private func drawdownColor(_ value: Double) -> Color {
        switch abs(value) {
        case 0..<0.15: return .clavixGoodInk
        case 0.15..<0.35: return .clavixWarnInk
        default: return .clavixBadInk
        }
    }
    private func drawdownSoft(_ value: Double) -> Color {
        switch abs(value) {
        case 0..<0.15: return .clavixGoodSoft
        case 0.15..<0.35: return .clavixWarnSoft
        default: return .clavixBadSoft
        }
    }

    // MARK: - Daily-move distribution

    @ViewBuilder
    private var distributionCard: some View {
        let buckets = PriceSeriesAnalytics.returnDistribution(points)
        if buckets.contains(where: { $0.count > 0 }) {
            let maxCount = max(buckets.map(\.count).max() ?? 1, 1)
            AuditSectionCard(title: "How Its Days Are Spread") {
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(buckets) { bucket in
                        VStack(spacing: 5) {
                            Text(bucket.count > 0 ? "\(bucket.count)" : " ")
                                .font(ClavisTypography.clavixMono(9, weight: .semibold))
                                .foregroundColor(.clavixInk3)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(bucketColor(bucket))
                                .frame(height: max(3, CGFloat(bucket.count) / CGFloat(maxCount) * 74))
                            Text(bucket.label)
                                .font(ClavisTypography.clavixMono(7, weight: .regular))
                                .foregroundColor(.clavixInk4)
                                .fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 108, alignment: .bottom)
                if let wb = PriceSeriesAnalytics.worstBestDay(points) {
                    Text("Over the past year, \(ticker)'s worst day was \(signedPercent(wb.worst)) and its best was \(signedPercent(wb.best)). Each bar counts how many days landed in that range.")
                        .font(ClavisTypography.footnote)
                        .foregroundColor(.clavixInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func bucketColor(_ b: PriceSeriesAnalytics.ReturnBucket) -> Color {
        if b.count == 0 { return .clavixRule2 }
        if b.isCenter { return .clavixInk3 }
        return b.isNegative ? .clavixBad : .clavixGood
    }

    // MARK: - 52-week range

    @ViewBuilder
    private var rangeCard: some View {
        if let pos = PriceSeriesAnalytics.rangePosition(points) {
            AuditSectionCard(title: "52-Week Range") {
                RangeBar(pos: pos)
                    .frame(height: 46)
                Text(rangeExplainer(pos))
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rangeExplainer(_ pos: PriceSeriesAnalytics.RangePosition) -> String {
        let pct = Int((pos.fraction * 100).rounded())
        let where_: String
        if pos.fraction >= 0.85 { where_ = "near its 52-week high" }
        else if pos.fraction <= 0.15 { where_ = "near its 52-week low" }
        else if pos.fraction >= 0.5 { where_ = "in the upper half of its 52-week range" }
        else { where_ = "in the lower half of its 52-week range" }
        return "\(ticker) is trading \(where_), \(pct)% of the way up from its yearly low."
    }

    // MARK: - Up vs down markets (capture) + beta

    @ViewBuilder
    private var marketBehaviorCard: some View {
        AuditSectionCard(title: "In Up vs Down Markets") {
            if let cap = PriceSeriesAnalytics.capture(points, benchmark: benchmark) {
                HStack(spacing: 12) {
                    captureCell(title: "When market rises", value: cap.upCapture, positiveIsGood: true)
                    Rectangle().fill(Color.clavixRule2).frame(width: 1, height: 52)
                    captureCell(title: "When market falls", value: cap.downCapture, positiveIsGood: false)
                }
                Text(captureExplainer(cap))
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(Color.clavixRule2).frame(height: 1).padding(.vertical, 2)
            }

            if let beta = dimension?.betaToSpy {
                AuditStatRow(
                    label: "Beta to the S&P 500",
                    caption: "How much it moves with the market",
                    value: String(format: "%.2f\u{00D7}", beta),
                    valueColor: .clavixInk,
                    pill: betaWord(beta),
                    pillInk: betaInk(beta),
                    pillFill: betaSoft(beta),
                    explainer: betaExplainer(beta)
                )
            } else if PriceSeriesAnalytics.capture(points, benchmark: benchmark) == nil {
                Text("Market-behavior data unavailable for this stock.")
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
            }
        }
    }

    private func captureCell(title: String, value: Double, positiveIsGood: Bool) -> some View {
        // >1 up-capture is good; >1 down-capture is bad.
        let ink: Color
        if positiveIsGood {
            ink = value >= 1.0 ? .clavixGoodInk : .clavixInk
        } else {
            ink = value >= 1.0 ? .clavixBadInk : .clavixGoodInk
        }
        return VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(ClavisTypography.clavixMono(8, weight: .bold))
                .tracking(0.4)
                .foregroundColor(.clavixInk4)
            Text(String(format: "%.2f\u{00D7}", value))
                .font(ClavisTypography.clavixMono(22, weight: .semibold))
                .foregroundColor(ink)
            Text("the market's move")
                .font(ClavisTypography.clavixMono(8, weight: .regular))
                .foregroundColor(.clavixInk4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func captureExplainer(_ cap: PriceSeriesAnalytics.CaptureStats) -> String {
        let up = String(format: "%.2f\u{00D7}", cap.upCapture)
        let down = String(format: "%.2f\u{00D7}", cap.downCapture)
        return "On up days for the S&P 500, \(ticker) has moved about \(up) the market's gain; on down days it has taken about \(down) the loss."
    }

    private func betaWord(_ beta: Double) -> String {
        if beta >= 1.15 { return "Amplifies" }
        if beta >= 0.85 { return "In line" }
        if beta >= 0 { return "Defensive" }
        return "Counter"
    }
    private func betaInk(_ beta: Double) -> Color {
        if beta >= 1.15 { return .clavixBadInk }
        if beta >= 0.85 { return .clavixWarnInk }
        return .clavixGoodInk
    }
    private func betaSoft(_ beta: Double) -> Color {
        if beta >= 1.15 { return .clavixBadSoft }
        if beta >= 0.85 { return .clavixWarnSoft }
        return .clavixGoodSoft
    }
    private func betaExplainer(_ beta: Double) -> String {
        let mag = String(format: "%.1f", abs(beta))
        if beta < 0 {
            return "\(ticker) has tended to move opposite the market, an unusual counter-cyclical pattern that can cushion broad sell-offs."
        }
        if beta >= 1.15 {
            return "When the S&P 500 moves 1%, \(ticker) has moved about \(mag)%: it amplifies market swings, so both rallies and sell-offs land harder here."
        }
        if beta >= 0.85 {
            return "\(ticker) has moved roughly step-for-step with the S&P 500."
        }
        return "When the S&P 500 moves 1%, \(ticker) has moved only about \(mag)%: it rides out market swings more calmly than average."
    }

    // MARK: - Shared bits

    private func squareTag(_ text: String, ink: Color, fill: Color) -> some View {
        Text(text.uppercased())
            .font(ClavisTypography.clavixMono(9, weight: .bold))
            .tracking(0.5)
            .foregroundColor(ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "\u{2014}" }
        return String(format: "%.1f%%", value * 100)
    }
    private func signedPercent(_ value: Double) -> String {
        String(format: "%+.1f%%", value * 100)
    }

    private static let shortDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
    private func shortDate(_ d: Date) -> String { Self.shortDateFmt.string(from: d) }
}

// MARK: - Drawdown price chart

private struct DrawdownPriceChart: View {
    let window: PriceSeriesAnalytics.DrawdownWindow
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let closes = window.slice.map(\.close)
            let minC = closes.min() ?? 0
            let maxC = closes.max() ?? 1
            let span = max(maxC - minC, 0.0001)
            let topPad = h * 0.12
            let plotH = h - topPad * 2
            let n = window.slice.count

            let x: (Int) -> CGFloat = { i in
                n > 1 ? CGFloat(i) / CGFloat(n - 1) * w : w / 2
            }
            let y: (Double) -> CGFloat = { c in
                topPad + (plotH - CGFloat((c - minC) / span) * plotH)
            }

            let peak = CGPoint(x: x(window.peakSliceIndex), y: y(window.peakClose))
            let trough = CGPoint(x: x(window.troughSliceIndex), y: y(window.troughClose))

            ZStack {
                // Prior-high reference line.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: peak.y))
                    p.addLine(to: CGPoint(x: w, y: peak.y))
                }
                .stroke(Color.clavixRule2, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // Shaded drop region above the price: price path up to the prior-high level.
                Path { p in
                    p.move(to: peak)
                    for i in window.peakSliceIndex...window.troughSliceIndex {
                        p.addLine(to: CGPoint(x: x(i), y: y(closes[i])))
                    }
                    p.addLine(to: CGPoint(x: trough.x, y: peak.y))
                    p.closeSubpath()
                }
                .fill(color.opacity(0.10))

                // Shaded drop region below the price: price path down to the axis, same span.
                Path { p in
                    let bottomY = topPad + plotH
                    p.move(to: CGPoint(x: peak.x, y: bottomY))
                    for i in window.peakSliceIndex...window.troughSliceIndex {
                        p.addLine(to: CGPoint(x: x(i), y: y(closes[i])))
                    }
                    p.addLine(to: CGPoint(x: trough.x, y: bottomY))
                    p.closeSubpath()
                }
                .fill(color.opacity(0.10))

                // Full price line, muted.
                Path { p in
                    for i in 0..<n {
                        let pt = CGPoint(x: x(i), y: y(closes[i]))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Color.clavixInk3, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

                // The drawdown leg, emphasized.
                Path { p in
                    for i in window.peakSliceIndex...window.troughSliceIndex {
                        let pt = CGPoint(x: x(i), y: y(closes[i]))
                        if i == window.peakSliceIndex { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                Circle()
                    .fill(Color.clavixInk3)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.clavixPaper, lineWidth: 1.5))
                    .position(peak)
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.clavixPaper, lineWidth: 1.5))
                    .position(trough)
            }
        }
    }
}

// MARK: - 52-week range bar

private struct RangeBar: View {
    let pos: PriceSeriesAnalytics.RangePosition

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let markerX = max(8, min(w - 8, CGFloat(pos.fraction) * w))
            let labelX = max(26, min(w - 26, markerX))
            let barY = geo.size.height * 0.5
            ZStack(alignment: .topLeading) {
                // Current price, floating above the marker.
                Text(currency(pos.last))
                    .font(ClavisTypography.clavixMono(11, weight: .semibold))
                    .foregroundColor(.clavixAccent)
                    .fixedSize()
                    .position(x: labelX, y: 7)

                // Track + filled portion + marker.
                Capsule().fill(Color.clavixPaper2)
                    .overlay(Capsule().stroke(Color.clavixRule, lineWidth: 1))
                    .frame(width: w, height: 8)
                    .position(x: w / 2, y: barY)
                Capsule().fill(Color.clavixAccent.opacity(0.35))
                    .frame(width: markerX, height: 8)
                    .position(x: markerX / 2, y: barY)
                Circle()
                    .fill(Color.clavixAccent)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.clavixPaper, lineWidth: 2))
                    .position(x: markerX, y: barY)

                // 52-week low / high anchors.
                Text(currency(pos.low))
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .foregroundColor(.clavixInk4)
                    .fixedSize()
                    .position(x: 20, y: geo.size.height - 7)
                Text(currency(pos.high))
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .foregroundColor(.clavixInk4)
                    .fixedSize()
                    .position(x: w - 22, y: geo.size.height - 7)
            }
        }
    }

    private func currency(_ v: Double) -> String {
        if v >= 1000 { return String(format: "$%.0f", v) }
        return String(format: "$%.2f", v)
    }
}
