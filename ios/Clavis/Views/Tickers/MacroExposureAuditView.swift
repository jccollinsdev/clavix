import SwiftUI

struct MacroExposureAuditView: View {
    @Environment(\.dismiss) private var dismiss
    let ticker: String
    let methodology: MethodologyResponse?

    private var dimension: MethodologyMacroExposure? { methodology?.dimensions.macroExposure }
    // Canonical backend regression factors (services/macro_regression.py FACTOR_ORDER).
    // spy/dxy are percent-return regressors; ust10y/credit/vix are level-difference
    // regressors, so their raw coefficients are NOT comparable by magnitude — we
    // show the market multiplier on its own and everything else as direction only.
    private let secondaryFactorOrder = ["ust10y", "dxy", "credit", "vix"]
    private var isReferenceMode: Bool { methodology == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                if isReferenceMode {
                    AuditReferenceContextView(
                        dimensionName: "Macro Resilience",
                        message: "Open a ticker from Search, Holdings, Alerts, or the Morning Report to see which macro forces move that stock."
                    )
                } else {
                    AuditHeaderCard(
                        title: "Macro Resilience",
                        ticker: ticker,
                        score: dimension?.score,
                        subtitle: headerSubtitle
                    )

                    if dimension?.limitedData == true {
                        AuditLimitedDataView(message: "Limited data: there was not enough clean price history to measure how this stock reacts to macro forces.")
                    } else {
                        marketSensitivityCard
                        factorBreakdownCard
                        macroBackdropCard
                    }
                }

                AuditSectionCard(title: "How to read this") {
                    Text("Macro Resilience is about how hard big-picture forces push this stock around. A stock that amplifies market swings, or reacts sharply to rates and the dollar, is more at the mercy of the macro backdrop, so it scores lower. A steadier, more self-driven name scores higher.")
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
    }

    private var headerSubtitle: String {
        if let days = dimension?.tradingDaysUsed {
            return "Measured over the last \(days) trading days"
        }
        return "Measured from recent price history"
    }

    // MARK: - Market sensitivity (the dominant, score-driving lever)

    /// The market coefficient is the one macro regressor on the same %-return scale
    /// as the stock, so it reads directly as "moves N× the market" — and it is what
    /// drives the score. Fall back to the volatility dimension's beta if absent.
    private var marketMultiplier: Double? {
        if let spy = dimension?.coefficients?["spy"] ?? nil { return spy }
        return methodology?.dimensions.volatility.betaToSpy
    }

    @ViewBuilder
    private var marketSensitivityCard: some View {
        AuditSectionCard(title: "Market Sensitivity") {
            if let mult = marketMultiplier {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(multiplierText(mult))
                        .font(ClavisTypography.clavixMono(38, weight: .semibold))
                        .tracking(-1)
                        .foregroundColor(.clavixInk)
                    Text("the market")
                        .font(ClavisTypography.clavixMono(12, weight: .regular))
                        .foregroundColor(.clavixInk4)
                    Spacer(minLength: 8)
                    Text(exposureWord(mult).uppercased())
                        .font(ClavisTypography.clavixMono(9, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(exposureInk(mult))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(exposureSoft(mult))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                Text(marketExplainer(mult))
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("We could not measure how strongly \(ticker) tracks the broad market from the available price history.")
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func multiplierText(_ v: Double) -> String {
        String(format: "%.1f\u{00D7}", v)
    }

    private func exposureWord(_ mult: Double) -> String {
        if mult < 0 { return "Counter-cyclical" }
        if mult >= 1.3 { return "High exposure" }
        if mult >= 0.8 { return "Moderate" }
        return "Low exposure"
    }

    private func exposureInk(_ mult: Double) -> Color {
        if mult < 0 { return .clavixAccentInk }
        if mult >= 1.3 { return .clavixBadInk }
        if mult >= 0.8 { return .clavixWarnInk }
        return .clavixGoodInk
    }

    private func exposureSoft(_ mult: Double) -> Color {
        if mult < 0 { return .clavixAccentSoft }
        if mult >= 1.3 { return .clavixBadSoft }
        if mult >= 0.8 { return .clavixWarnSoft }
        return .clavixGoodSoft
    }

    private func marketExplainer(_ mult: Double) -> String {
        let m = String(format: "%.1f", abs(mult))
        if mult < 0 {
            return "When the market rises 1%, \(ticker) has tended to move the other way. That counter-cyclical pattern makes it a cushion when markets fall, which lifts its macro resilience."
        }
        if mult >= 1.3 {
            return "When the market moves 1%, \(ticker) has moved about \(m)% in the same direction. It amplifies market swings, so broad sell-offs hit it harder than most, which is the main reason its macro resilience is low."
        }
        if mult >= 0.8 {
            return "When the market moves 1%, \(ticker) has moved roughly \(m)% with it, close to the market's own pace, so its macro exposure sits in the middle."
        }
        return "When the market moves 1%, \(ticker) has moved only about \(m)% with it. It rides out broad swings more calmly than most, which supports a higher macro resilience."
    }

    // MARK: - Factor breakdown (ranked by unit-comparable contribution)

    private struct ContributionRow: Identifiable {
        let key: String
        let contribution: Double
        let share: Double          // 0..1 variance share (vol adds in quadrature)
        let risesWith: Bool
        var id: String { key }
    }

    private var contributionRows: [ContributionRow] {
        let contribs = dimension?.contributions ?? [:]
        let coeffs = dimension?.coefficients ?? [:]
        let pairs: [(String, Double, Bool)] = contribs.compactMap { key, value in
            guard let c = value, c > 0 else { return nil }
            let beta = (coeffs[key] ?? nil) ?? 0
            return (key, c, beta >= 0)
        }
        let sumSq = pairs.reduce(0.0) { $0 + $1.1 * $1.1 }
        guard sumSq > 0 else { return [] }
        return pairs
            .map { ContributionRow(key: $0.0, contribution: $0.1, share: ($0.1 * $0.1) / sumSq, risesWith: $0.2) }
            .sorted { $0.contribution > $1.contribution }
    }

    @ViewBuilder
    private var factorBreakdownCard: some View {
        let rows = contributionRows
        if rows.isEmpty {
            // Fallback until the API serves `contributions`: direction-only rows.
            otherForcesCard
        } else {
            AuditSectionCard(title: "What Drives Its Macro Exposure") {
                ForEach(rows) { row in
                    factorBar(row)
                }
                Text("Each factor's share of the macro-driven part of \(ticker)'s day-to-day moves, measured in comparable units. The arrow shows which way \(ticker) tends to move when that force rises.")
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .foregroundColor(.clavixInk4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                if let r = dimension?.rSquared {
                    Text(rSquaredFootnote(r))
                        .font(ClavisTypography.clavixMono(9, weight: .regular))
                        .foregroundColor(.clavixInk4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func factorBar(_ row: ContributionRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: row.risesWith ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.clavixAccent)
                Text(factorFullName(row.key))
                    .font(ClavisTypography.inter(13, weight: .semibold))
                    .foregroundColor(.clavixInk)
                Spacer(minLength: 8)
                Text(shareText(row.share))
                    .font(ClavisTypography.clavixMono(12, weight: .semibold))
                    .foregroundColor(.clavixInk)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.clavixRule2).frame(height: 6)
                    Capsule().fill(Color.clavixAccent).frame(width: max(4, geo.size.width * CGFloat(row.share)), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 3)
    }

    private func shareText(_ share: Double) -> String {
        share < 0.01 ? "<1%" : "\(Int((share * 100).rounded()))%"
    }

    private func factorFullName(_ key: String) -> String {
        key == "spy" ? "Broad market (S&P 500)" : factorName(key)
    }

    // MARK: - Today's macro backdrop (live FRED factor levels)

    private struct BackdropItem: Identifiable {
        let id: String
        let name: String
        let caption: String
        let value: String
        let tag: String?
        let tagInk: Color
        let tagFill: Color
    }

    private func levelValue(_ levels: [String: Double?], _ key: String) -> Double? {
        (levels[key] ?? nil)
    }

    private var backdropItems: [BackdropItem] {
        let levels = dimension?.currentFactorLevels ?? [:]
        var items: [BackdropItem] = []
        if let ust = levelValue(levels, "ust10y") {
            items.append(BackdropItem(id: "ust10y", name: "10-Year Treasury yield", caption: "The benchmark interest rate", value: String(format: "%.2f%%", ust), tag: nil, tagInk: .clavixInk3, tagFill: .clavixPaper2))
        }
        if let vix = levelValue(levels, "vix") {
            let (t, ink, fill): (String, Color, Color) = vix < 15 ? ("Calm", .clavixGoodInk, .clavixGoodSoft) : (vix <= 25 ? ("Normal", .clavixInk3, .clavixPaper2) : ("Elevated", .clavixBadInk, .clavixBadSoft))
            items.append(BackdropItem(id: "vix", name: "Market volatility (VIX)", caption: "The market's fear gauge", value: String(format: "%.1f", vix), tag: t, tagInk: ink, tagFill: fill))
        }
        if let dxy = levelValue(levels, "dxy") {
            items.append(BackdropItem(id: "dxy", name: "US dollar index", caption: "Strength of the dollar", value: String(format: "%.1f", dxy), tag: nil, tagInk: .clavixInk3, tagFill: .clavixPaper2))
        }
        if let credit = levelValue(levels, "credit") {
            let (t, ink, fill): (String, Color, Color) = credit < 3 ? ("Calm", .clavixGoodInk, .clavixGoodSoft) : (credit <= 5 ? ("Normal", .clavixInk3, .clavixPaper2) : ("Stressed", .clavixBadInk, .clavixBadSoft))
            items.append(BackdropItem(id: "credit", name: "High-yield credit spread", caption: "Stress in risky corporate debt", value: String(format: "%.2f%%", credit), tag: t, tagInk: ink, tagFill: fill))
        }
        return items
    }

    @ViewBuilder
    private var macroBackdropCard: some View {
        let items = backdropItems
        if !items.isEmpty {
            AuditSectionCard(title: "Today's Macro Backdrop") {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(ClavisTypography.inter(13, weight: .semibold))
                                .foregroundColor(.clavixInk)
                            Text(item.caption)
                                .font(ClavisTypography.clavixMono(9, weight: .regular))
                                .foregroundColor(.clavixInk3)
                        }
                        Spacer(minLength: 8)
                        Text(item.value)
                            .font(ClavisTypography.clavixMono(15, weight: .semibold))
                            .foregroundColor(.clavixInk)
                        if let tag = item.tag {
                            Text(tag.uppercased())
                                .font(ClavisTypography.clavixMono(8, weight: .bold))
                                .tracking(0.4)
                                .foregroundColor(item.tagInk)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(item.tagFill)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                    }
                    .padding(.vertical, 4)
                    if index < items.count - 1 {
                        Rectangle().fill(Color.clavixRule2).frame(height: 1)
                    }
                }
                Text("The macro environment every stock is trading in right now, from the Federal Reserve data feed.")
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .foregroundColor(.clavixInk4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Other macro forces (direction only, never comparable magnitudes)

    private struct SecondaryFactor: Identifiable {
        let key: String
        let beta: Double
        var id: String { key }
    }

    /// Per-factor "meaningful" floor, since the coefficients live on different unit
    /// scales (percent-returns vs level-differences) and cannot share one threshold.
    private func isMeaningful(_ key: String, _ beta: Double) -> Bool {
        switch key {
        case "dxy": return abs(beta) >= 0.20
        case "ust10y": return abs(beta) >= 0.05
        case "credit": return abs(beta) >= 0.05
        case "vix": return abs(beta) >= 0.02
        default: return abs(beta) >= 0.05
        }
    }

    private var secondaryFactors: [SecondaryFactor] {
        let coeffs = dimension?.coefficients ?? [:]
        return secondaryFactorOrder.compactMap { key -> SecondaryFactor? in
            guard let betaOpt = coeffs[key], let beta = betaOpt else { return nil }
            return SecondaryFactor(key: key, beta: beta)
        }
    }

    @ViewBuilder
    private var otherForcesCard: some View {
        let all = secondaryFactors
        let meaningful = all.filter { isMeaningful($0.key, $0.beta) }
        let negligible = all.filter { !isMeaningful($0.key, $0.beta) }
        if !all.isEmpty {
            AuditSectionCard(title: "Other Forces That Move It") {
                if meaningful.isEmpty {
                    Text("Beyond the market itself, no single macro force has left a clear mark on \(ticker)'s recent moves.")
                        .font(ClavisTypography.footnote)
                        .foregroundColor(.clavixInk3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(meaningful.enumerated()), id: \.element.id) { index, factor in
                        SecondaryFactorRow(name: factorName(factor.key), phrase: factorPhrase(factor.key, factor.beta), risesWith: factor.beta >= 0)
                        if index < meaningful.count - 1 {
                            Rectangle().fill(Color.clavixRule2).frame(height: 1)
                        }
                    }
                }
                if !negligible.isEmpty {
                    Text("Barely reacts to: " + negligible.map { factorShortName($0.key) }.joined(separator: ", ") + ".")
                        .font(ClavisTypography.clavixMono(9, weight: .regular))
                        .foregroundColor(.clavixInk4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                if let r = dimension?.rSquared {
                    Text(rSquaredFootnote(r))
                        .font(ClavisTypography.clavixMono(9, weight: .regular))
                        .foregroundColor(.clavixInk4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func rSquaredFootnote(_ r: Double) -> String {
        let pct = Int((max(0, min(1, r)) * 100).rounded())
        return "Together, these macro forces explain about \(pct)% of \(ticker)'s day-to-day moves: the rest is its own company-specific story."
    }

    private func factorName(_ key: String) -> String {
        switch key {
        case "ust10y": return "Interest rates (10-yr Treasury)"
        case "dxy": return "US dollar"
        case "credit": return "Credit stress (high-yield spreads)"
        case "vix": return "Market volatility (VIX)"
        default: return key.uppercased()
        }
    }

    private func factorShortName(_ key: String) -> String {
        switch key {
        case "ust10y": return "interest rates"
        case "dxy": return "the US dollar"
        case "credit": return "credit stress"
        case "vix": return "market volatility"
        default: return key.uppercased()
        }
    }

    private func factorPhrase(_ key: String, _ beta: Double) -> String {
        let up = beta >= 0
        switch key {
        case "ust10y": return up ? "Tends to firm up when yields rise" : "Tends to slip when yields rise"
        case "dxy": return up ? "Tends to firm up when the dollar strengthens" : "Tends to slip when the dollar strengthens"
        case "credit": return up ? "Tends to firm up when credit stress rises" : "Tends to slip when credit stress rises"
        case "vix": return up ? "Tends to firm up when volatility spikes" : "Tends to slip when volatility spikes"
        default: return up ? "Moves in the same direction" : "Moves in the opposite direction"
        }
    }
}

// MARK: - Secondary factor row (direction only, no magnitude bar)

private struct SecondaryFactorRow: View {
    let name: String
    let phrase: String
    let risesWith: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: risesWith ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.clavixAccent)
                .frame(width: 26, height: 26)
                .background(Color.clavixAccentSoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(ClavisTypography.inter(14, weight: .semibold))
                    .foregroundColor(.clavixInk)
                Text(phrase)
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
