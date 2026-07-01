import SwiftUI

struct FinancialHealthAuditView: View {
    @Environment(\.dismiss) private var dismiss
    let ticker: String
    let methodology: MethodologyResponse?
    var isETF: Bool = false

    private var dimension: MethodologyFinancialHealth? { methodology?.dimensions.financialHealth }
    private var isReferenceMode: Bool { methodology == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                if isReferenceMode {
                    AuditReferenceContextView(
                        dimensionName: isETF ? "Holdings Quality" : "Financial Health",
                        message: isETF
                            ? "Open a fund to inspect the weighted risk quality of its underlying holdings."
                            : "Open a ticker from Search, Holdings, Alerts, or the Morning Report to inspect live balance-sheet and cash-flow inputs for that company."
                    )
                } else {
                    AuditHeaderCard(
                        title: isETF ? "Holdings Quality" : "Financial Health",
                        ticker: ticker,
                        score: dimension?.score,
                        subtitle: "Source: \(isETF ? "ETF holdings" : "Finnhub"), updated \(AuditSupport.formattedAsOfDate(dimension?.asOfDate))"
                    )

                    if dimension?.limitedData == true {
                        ClavixInlineNoticeCard(
                            eyebrow: "Data Limited",
                            title: "Fewer than 2 financial ratios available",
                            message: "Finnhub does not report all metrics for this company (common for banks, REITs, foreign-listed, and some small caps). The Financial Health score defaults to neutral (50) where data is absent. Treat it as directional only.",
                            footnote: "Ratios available: \(dimension?.ratiosAvailable ?? 0) of 5",
                            glyph: "exclamationmark.triangle",
                            fill: .clavixWarnSoft,
                            foreground: .clavixWarnInk,
                            secondary: .clavixWarnInk
                        )
                    }

                    if isETF {
                        holdingsQualityCard
                        if !(dimension?.holdings ?? []).isEmpty {
                            topHoldingsCard
                        }
                    } else {
                        ratiosCard
                    }
                }

                AuditSectionCard(title: "Methodology") {
                    Text(isETF
                         ? "Holdings Quality is the constituent-weighted Clavix score of the fund's latest available top holdings. It does not use company balance-sheet ratios for the ETF shell."
                         : "Financial Health measures the structural strength of the company. It uses balance-sheet and cash-flow inputs such as debt-to-equity ratio, free cash flow margin, current ratio, interest coverage, revenue growth trend, and profitability trend.")
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

    // MARK: - ETF holdings-quality grade mix

    @ViewBuilder
    private var holdingsQualityCard: some View {
        let scored = (dimension?.holdings ?? []).filter { $0.score != nil }
        if scored.count >= 3 {
            let strong = scored.filter { ($0.score ?? 0) >= 67 }.count
            let moderate = scored.filter { let s = $0.score ?? 0; return s >= 34 && s < 67 }.count
            let weak = scored.filter { ($0.score ?? 0) < 34 }.count
            let slices = [
                AuditDonutSlice(id: "strong", label: "Strong", value: Double(strong), color: .clavixGood),
                AuditDonutSlice(id: "moderate", label: "Moderate", value: Double(moderate), color: .clavixWarn),
                AuditDonutSlice(id: "weak", label: "Weak", value: Double(weak), color: .clavixBad),
            ].filter { $0.value > 0 }
            AuditSectionCard(title: "Quality of Holdings") {
                HStack(alignment: .center, spacing: 18) {
                    AuditDonutChart(
                        slices: slices,
                        centerPrimary: "\(scored.count)",
                        centerDetail: "scored"
                    )
                    .frame(width: 112, height: 112)

                    VStack(alignment: .leading, spacing: 10) {
                        qualityLegendRow("Strong", "67+", strong, .clavixGood)
                        qualityLegendRow("Moderate", "34–66", moderate, .clavixWarn)
                        qualityLegendRow("Weak", "below 34", weak, .clavixBad)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(qualityRead(strong: strong, moderate: moderate, weak: weak, total: scored.count))
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                Text("\(dimension?.holdingsScoredCount ?? scored.count) of \(dimension?.holdingsCount ?? scored.count) holdings scored · \(weightCoveredText) of weight covered")
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .foregroundColor(.clavixInk4)
            }
        } else {
            AuditSectionCard(title: "Quality of Holdings") {
                Text("Not enough of this fund's holdings are individually scored yet to break down their quality. Coverage so far: \(dimension?.holdingsScoredCount ?? 0) of \(dimension?.holdingsCount ?? 0) holdings, \(weightCoveredText) of fund weight.")
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func qualityLegendRow(_ label: String, _ range: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(ClavisTypography.inter(13, weight: .medium))
                    .foregroundColor(.clavixInk)
                Text(range)
                    .font(ClavisTypography.clavixMono(8, weight: .regular))
                    .foregroundColor(.clavixInk4)
            }
            Spacer(minLength: 8)
            Text("\(count)")
                .font(ClavisTypography.clavixMono(15, weight: .semibold))
                .foregroundColor(.clavixInk)
        }
    }

    private func qualityRead(strong: Int, moderate: Int, weak: Int, total: Int) -> String {
        guard total > 0 else { return "" }
        let strongPct = Int((Double(strong) / Double(total) * 100).rounded())
        if strong >= moderate + weak {
            return "Most of the scored holdings (\(strongPct)%) are strong-rated names, so the fund is built on a healthy base."
        }
        if weak > strong {
            return "More of the scored holdings lean weak than strong, which drags on the fund's overall quality."
        }
        return "The fund's scored holdings are a mix of strong and softer names, so quality is middling rather than uniform."
    }

    private var weightCoveredText: String {
        dimension?.holdingsWeightCoveredPct.map { String(format: "%.0f%%", $0) } ?? "an unknown share"
    }

    // MARK: - ETF top holdings, sized by weight

    private var topHoldingsCard: some View {
        let holdings = dimension?.holdings ?? []
        let shownCount = holdings.count
        let total = dimension?.totalHoldings
        let subtitle: String = {
            if let total, total > shownCount {
                return "Top \(shownCount) of \(total) holdings"
            }
            return "\(shownCount) holdings"
        }()
        return AuditSectionCard(title: "Top Holdings") {
            // Column header
            HStack(spacing: 8) {
                Text("TICKER")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("WEIGHT")
                    .frame(width: 74, alignment: .trailing)
                Text("CLAVIX")
                    .frame(width: 58, alignment: .trailing)
            }
            .font(ClavisTypography.clavixMono(9, weight: .bold))
            .tracking(0.6)
            .foregroundColor(.clavixInk4)

            Rectangle().fill(Color.clavixRule2).frame(height: 1)

            VStack(spacing: 0) {
                ForEach(Array(holdings.enumerated()), id: \.element.id) { index, holding in
                    HoldingTableRow(holding: holding)
                    if index < holdings.count - 1 {
                        Rectangle().fill(Color.clavixRule2).frame(height: 1)
                    }
                }
            }

            Text("\(subtitle) · number is each holding's own Clavix score (0–100).")
                .font(ClavisTypography.clavixMono(9, weight: .regular))
                .foregroundColor(.clavixInk4)
                .padding(.top, 2)
        }
    }

    // MARK: - Ratio position bands (non-ETF)

    private var ratiosCard: some View {
        let specs = ratioSpecs
        return AuditSectionCard(title: "Balance Sheet Ratios") {
            Text("Each ratio is placed against its sector peers. The blue band is where the typical peer sits (middle 50%); the line inside it is the sector median.")
                .font(ClavisTypography.footnote)
                .foregroundColor(.clavixInk3)
                .fixedSize(horizontal: false, vertical: true)

            ratioBandLegend

            ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
                RatioBandRow(spec: spec)
                if index < specs.count - 1 {
                    Rectangle().fill(Color.clavixRule2).frame(height: 1)
                }
            }

            trendRow

            if let peers = dimension?.peerComparisons, !peers.isEmpty {
                Text("Peers: " + peers.prefix(5).compactMap(\.ticker).joined(separator: ", "))
                    .font(ClavisTypography.footnoteEmphasis)
                    .foregroundColor(.clavixInk)
                    .padding(.top, 4)
            }
        }
    }

    private var ratioBandLegend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Circle().fill(Color.clavixAccent).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.clavixPaper, lineWidth: 1))
                Text("\(ticker)")
                    .font(ClavisTypography.clavixMono(9, weight: .bold))
                    .foregroundColor(.clavixInk3)
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.clavixAccent.opacity(0.22))
                    .frame(width: 16, height: 9)
                Text("Typical peer")
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .foregroundColor(.clavixInk3)
            }
            HStack(spacing: 5) {
                Rectangle().fill(Color.clavixInk2).frame(width: 2, height: 10)
                Text("Median")
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .foregroundColor(.clavixInk3)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var trendRow: some View {
        HStack(alignment: .top, spacing: 20) {
            trendChip(label: "Revenue Growth", value: dimension?.revenueGrowthTrend)
            trendChip(label: "Profitability", value: dimension?.profitabilityTrend)
        }
        .padding(.top, 6)
    }

    private func trendChip(label: String, value: String?) -> some View {
        let text = value?.humanizedTitleCasedDisplayText ?? "Unavailable"
        let lower = value?.lowercased() ?? ""
        let glyph: String
        let color: Color
        if lower.contains("positive") || lower.contains("improving") || lower.contains("up") {
            glyph = "arrow.up.right"
            color = .clavixGoodInk
        } else if lower.contains("negative") || lower.contains("declining") || lower.contains("down") {
            glyph = "arrow.down.right"
            color = .clavixBadInk
        } else {
            glyph = "minus"
            color = .clavixInk3
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(ClavisTypography.clavixMono(8, weight: .bold))
                .tracking(0.4)
                .foregroundColor(.clavixInk4)
            HStack(spacing: 4) {
                Image(systemName: glyph)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
                Text(text)
                    .font(ClavisTypography.inter(12, weight: .semibold))
                    .foregroundColor(.clavixInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ratioSpecs: [RatioSpec] {
        let medians = dimension?.sectorMedianComparison ?? [:]
        return [
            makeSpec(id: "debt_to_equity", label: "Debt to Equity", caption: "Leverage vs shareholder equity", ownValue: dimension?.debtToEquity, medians: medians),
            makeSpec(id: "fcf_margin", label: "FCF Margin", caption: "Free cash flow as % of revenue", ownValue: dimension?.fcfMargin, medians: medians),
            makeSpec(id: "current_ratio", label: "Current Ratio", caption: "Short-term assets vs liabilities", ownValue: dimension?.currentRatio, medians: medians),
            makeSpec(id: "interest_coverage", label: "Interest Coverage", caption: "Operating income vs interest expense", ownValue: dimension?.interestCoverage, medians: medians),
        ]
    }

    private func makeSpec(id: String, label: String, caption: String, ownValue: Double?, medians: [String: MethodologySectorMedian]) -> RatioSpec {
        let m = medians[id]
        let verdict: AuditVerdict = ownValue.map { ratioVerdict(id, $0) } ?? .neutral
        return RatioSpec(
            id: id,
            label: label,
            caption: caption,
            ownValue: ownValue,
            formattedOwn: ownValue.map { formattedRatioValue(id, $0) },
            verdict: verdict,
            median: m?.median,
            p25: m?.p25,
            p75: m?.p75,
            nTickers: m?.nTickers,
            formattedMedian: m?.median.map { formattedRatioValue(id, $0) }
        )
    }

    private func formattedRatioValue(_ metric: String, _ value: Double) -> String {
        switch metric {
        case "fcf_margin": return String(format: "%.1f%%", value * 100)
        case "interest_coverage": return String(format: "%.1f\u{00D7}", value)
        default: return String(format: "%.2f", value)
        }
    }

    private func ratioVerdict(_ metric: String, _ value: Double) -> AuditVerdict {
        switch metric {
        case "debt_to_equity": return value < 1 ? .good : value < 2 ? .warn : .bad
        case "current_ratio": return value >= 1.5 ? .good : value >= 1 ? .warn : .bad
        case "fcf_margin": return value >= 0.15 ? .good : value >= 0 ? .warn : .bad
        case "interest_coverage": return value >= 5 ? .good : value >= 2 ? .warn : .bad
        default: return .neutral
        }
    }
}

// MARK: - Ratio band row

private struct RatioSpec: Identifiable {
    let id: String
    let label: String
    let caption: String
    let ownValue: Double?
    let formattedOwn: String?
    let verdict: AuditVerdict
    let median: Double?
    let p25: Double?
    let p75: Double?
    let nTickers: Int?
    let formattedMedian: String?
}

private func ratioVerdictLabel(_ v: AuditVerdict) -> String {
    switch v {
    case .good: return "HEALTHY"
    case .warn: return "WATCH"
    case .bad: return "STRESSED"
    case .neutral: return "\u{2014}"
    }
}

private struct RatioBandRow: View {
    let spec: RatioSpec

    private var hasBand: Bool {
        guard spec.ownValue != nil, spec.median != nil, let p25 = spec.p25, let p75 = spec.p75, p75 > p25 else { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.label)
                        .font(ClavisTypography.inter(14, weight: .semibold))
                        .foregroundColor(.clavixInk)
                    Text(spec.caption)
                        .font(ClavisTypography.clavixMono(9, weight: .regular))
                        .foregroundColor(.clavixInk3)
                }
                Spacer(minLength: 8)
                if let formattedOwn = spec.formattedOwn {
                    Text(formattedOwn)
                        .font(ClavisTypography.clavixMono(16, weight: .semibold))
                        .foregroundColor(auditVerdictInk(spec.verdict))
                    Text(ratioVerdictLabel(spec.verdict))
                        .font(ClavisTypography.clavixMono(8, weight: .bold))
                        .tracking(0.4)
                        .foregroundColor(auditVerdictInk(spec.verdict))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(auditVerdictFill(spec.verdict))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Text("Unavailable")
                        .font(ClavisTypography.clavixMono(13, weight: .semibold))
                        .foregroundColor(.clavixInk4)
                }
            }

            if hasBand, let ownValue = spec.ownValue, let median = spec.median, let p25 = spec.p25, let p75 = spec.p75 {
                RatioRangeBand(ownValue: ownValue, median: median, p25: p25, p75: p75, color: .clavixAccent)
                    .frame(height: 20)
                if let n = spec.nTickers, let formattedMedian = spec.formattedMedian {
                    Text("Median \(formattedMedian) \u{00B7} n=\(n) tickers")
                        .font(ClavisTypography.clavixMono(9, weight: .regular))
                        .foregroundColor(.clavixInk4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Horizontal positioning band: shaded track spans the sector's 25th-75th
/// percentile, a tick marks the median, and a colored dot marks this ticker's
/// own value — so a ratio reads as "where do I sit vs peers" instead of a
/// bare number next to a health-word pill.
private struct RatioRangeBand: View {
    let ownValue: Double
    let median: Double
    let p25: Double
    let p75: Double
    let color: Color

    private var domain: (lo: Double, hi: Double) {
        let lo = min(p25, ownValue, median)
        let hi = max(p75, ownValue, median)
        let span = hi - lo
        let pad = span > 0 ? span * 0.18 : max(abs(hi) * 0.1, 0.1)
        return (lo - pad, hi + pad)
    }

    private func x(_ value: Double, _ width: CGFloat) -> CGFloat {
        let (lo, hi) = domain
        guard hi > lo else { return width / 2 }
        return CGFloat((value - lo) / (hi - lo)) * width
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let midY = geo.size.height / 2
            let xp25 = x(p25, w)
            let xp75 = x(p75, w)
            let bandStart = min(xp25, xp75)
            let bandWidth = max(4, abs(xp75 - xp25))

            ZStack {
                // Full-domain lane — a clearly defined rail so the "outside the
                // peer range" space reads as space, not emptiness.
                Capsule()
                    .fill(Color.clavixPaper2)
                    .overlay(Capsule().stroke(Color.clavixRule, lineWidth: 1))
                    .frame(width: w, height: 12)
                    .position(x: w / 2, y: midY)
                // Typical-peer band — a visible blue tint, not faint grey.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.clavixAccent.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4).stroke(Color.clavixAccent.opacity(0.45), lineWidth: 1)
                    )
                    .frame(width: bandWidth, height: 12)
                    .position(x: bandStart + bandWidth / 2, y: midY)
                // Sector median tick.
                Rectangle()
                    .fill(Color.clavixInk2)
                    .frame(width: 2, height: 16)
                    .position(x: x(median, w), y: midY)
                // This ticker's value.
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.clavixPaper, lineWidth: 2))
                    .position(x: x(ownValue, w), y: midY)
            }
        }
    }
}

// MARK: - ETF holdings table row (ticker · weight · Clavix score)

private struct HoldingTableRow: View {
    let holding: MethodologyETFHolding

    var body: some View {
        HStack(spacing: 8) {
            Text(holding.ticker)
                .font(ClavisTypography.clavixMono(13, weight: .bold))
                .foregroundColor(.clavixInk)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(holding.weightPct.map { String(format: "%.2f%%", $0) } ?? "\u{2014}")
                .font(ClavisTypography.clavixMono(12, weight: .semibold))
                .foregroundColor(.clavixInk2)
                .frame(width: 74, alignment: .trailing)

            if let score = holding.score {
                Text(String(format: "%.0f", score))
                    .font(ClavisTypography.clavixMono(13, weight: .bold))
                    .foregroundColor(auditBandInk(score))
                    .frame(width: 58, alignment: .trailing)
            } else {
                Text("\u{2014}")
                    .font(ClavisTypography.clavixMono(12, weight: .regular))
                    .foregroundColor(.clavixInk4)
                    .frame(width: 58, alignment: .trailing)
            }
        }
        .padding(.vertical, 9)
    }
}

// MARK: - Shared audit components (editorial redesign)

func auditBandColor(_ score: Double?) -> Color {
    guard let score else { return .clavixInk4 }
    switch score {
    case 67...:      return .clavixGood
    case 34..<67:    return .clavixWarn
    default:         return .clavixBad
    }
}

func auditBandLabel(_ score: Double?) -> String {
    guard let score else { return "NO READ" }
    switch score {
    case 67...:   return "STRONG"
    case 34..<67: return "MODERATE"
    default:      return "WEAK"
    }
}

/// Readable ink color for a score band (for text/pills on paper).
func auditBandInk(_ score: Double?) -> Color {
    guard let score else { return .clavixInk3 }
    switch score {
    case 67...:   return .clavixGoodInk
    case 34..<67: return .clavixWarnInk
    default:      return .clavixBadInk
    }
}

/// Soft tinted fill for a score band (pill backgrounds).
func auditBandSoft(_ score: Double?) -> Color {
    guard let score else { return .clavixPaper2 }
    switch score {
    case 67...:   return .clavixGoodSoft
    case 34..<67: return .clavixWarnSoft
    default:      return .clavixBadSoft
    }
}

func auditGrade(for score: Double?) -> String {
    guard let score else { return "\u{2014}" }
    return PortfolioMath.grade(forScore: score)
}

enum AuditVerdict { case good, warn, bad, neutral }

func auditVerdictFill(_ v: AuditVerdict) -> Color {
    switch v {
    case .good:    return .clavixGoodSoft
    case .warn:    return .clavixWarnSoft
    case .bad:     return .clavixBadSoft
    case .neutral: return .clavixPaper2
    }
}

func auditVerdictInk(_ v: AuditVerdict) -> Color {
    switch v {
    case .good:    return .clavixGoodInk
    case .warn:    return .clavixWarnInk
    case .bad:     return .clavixBadInk
    case .neutral: return .clavixInk3
    }
}

/// Squared verdict tag matching the design language (not a rounded pill).
struct AuditSquareTag: View {
    let text: String
    let ink: Color
    let fill: Color

    var body: some View {
        Text(text.uppercased())
            .font(ClavisTypography.clavixMono(9, weight: .bold))
            .tracking(0.5)
            .foregroundColor(ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

/// Dimension masthead, styled like the ticker-view "Risk rating" card: ticker
/// eyebrow, serif name, grade badge, big score, and a colored verdict pill — no
/// horizontal fill bar.
struct AuditHeaderCard: View {
    let title: String
    let ticker: String
    let score: Double?
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ticker)
                        .font(ClavisTypography.clavixMono(10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(.clavixAccent)
                    Text(title)
                        .font(ClavisTypography.clavixSerif(26, weight: .medium))
                        .tracking(-0.4)
                        .foregroundColor(.clavixInk)
                }
                Spacer(minLength: 8)
                ClavixGradeBadge(auditGrade(for: score), size: 44)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(score.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(ClavisTypography.clavixMono(40, weight: .semibold))
                    .tracking(-1)
                    .foregroundColor(.clavixInk)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                Text("/ 100")
                    .font(ClavisTypography.clavixMono(13, weight: .regular))
                    .foregroundColor(.clavixInk4)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                Text(auditBandLabel(score))
                    .font(ClavisTypography.clavixMono(10, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(auditBandInk(score))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(auditBandSoft(score))
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }

            Text(subtitle)
                .font(ClavisTypography.clavixMono(10, weight: .regular))
                .foregroundColor(.clavixInk3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.clavixPaper)
        .overlay(Rectangle().stroke(Color.clavixRule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Bordered section with a mono header and a hairline, terminal-ledger style.
struct AuditSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(ClavisTypography.clavixMono(10, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.clavixInk3)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            Rectangle().fill(Color.clavixRule).frame(height: 1)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
        }
        .background(Color.clavixPaper)
        .overlay(Rectangle().stroke(Color.clavixRule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Metric row: label (+ optional unit caption), prominent mono value, and a
/// color-coded verdict pill. Health words (Healthy/Watch/Stressed) read as
/// colored verdicts; plain units (Annualized/Correlation/Metric) read as muted
/// chips, so the row is never an ambiguous three-column wall of text.
struct AuditValueRow: View {
    let label: String
    let value: String
    let status: String
    var caption: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(ClavisTypography.inter(14, weight: .semibold))
                    .foregroundColor(.clavixInk)
                if let caption {
                    Text(caption)
                        .font(ClavisTypography.clavixMono(9, weight: .regular))
                        .foregroundColor(.clavixInk3)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(ClavisTypography.clavixMono(15, weight: .semibold))
                .foregroundColor((value == "Unavailable" || value == "—") ? .clavixInk4 : .clavixInk)
            statusPill
        }
    }

    private var statusPill: some View {
        let verdict = Self.classify(status)
        return Text(status.uppercased())
            .font(ClavisTypography.clavixMono(8, weight: .bold))
            .tracking(0.4)
            .foregroundColor(ink(verdict))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(fill(verdict))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func fill(_ v: AuditVerdict) -> Color { auditVerdictFill(v) }
    private func ink(_ v: AuditVerdict) -> Color { auditVerdictInk(v) }

    static func classify(_ status: String) -> AuditVerdict {
        switch status.lowercased() {
        case "healthy", "live", "falling": return .good
        case "watch", "rising", "estimated", "active": return .warn
        case "stressed": return .bad
        default: return .neutral
        }
    }
}

struct AuditLimitedDataView: View {
    let message: String

    var body: some View {
        ClavixCard(fill: .clavixPaper) {
            Text(message)
                .font(ClavisTypography.body)
                .foregroundColor(.clavixInk3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AuditReferenceContextView: View {
    let dimensionName: String
    let message: String

    var body: some View {
        ClavixInlineNoticeCard(
            eyebrow: "Reference Mode",
            title: "\(dimensionName) needs a live ticker",
            message: message,
            footnote: "Reference pages explain the framework. Live inputs appear when you open this audit from a stock.",
            glyph: "scope",
            fill: .clavixPaper2,
            secondary: .clavixInk3
        )
    }
}

// MARK: - Shared static donut (no interactivity — used where a dimension
// needs a composition breakdown, e.g. concentration, without the tap-to-select
// behavior of the Holdings screen's donut).

struct AuditDonutSlice: Identifiable {
    let id: String
    let label: String
    let value: Double
    let color: Color
}

struct AuditDonutChart: View {
    let slices: [AuditDonutSlice]
    let centerPrimary: String
    let centerDetail: String

    private var total: Double { max(slices.reduce(0) { $0 + $1.value }, 0.0001) }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let outer = side / 2
            let ring = max(12, outer * 0.34)
            let centerline = outer - ring / 2
            let visibleCount = slices.filter { $0.value > 0 }.count
            let gap: Double = visibleCount > 1 ? 1.6 : 0

            ZStack {
                Circle()
                    .stroke(Color.clavixRule2, lineWidth: ring)
                    .padding(ring / 2)

                ForEach(cumulative(), id: \.id) { seg in
                    AuditDonutArc(
                        startDeg: -90 + seg.start * 360 + gap,
                        endDeg: -90 + seg.end * 360 - gap,
                        centerlineRadius: centerline
                    )
                    .stroke(seg.color, style: StrokeStyle(lineWidth: ring, lineCap: .butt))
                }

                VStack(spacing: 1) {
                    Text(centerPrimary)
                        .font(ClavisTypography.clavixMono(18, weight: .bold))
                        .foregroundColor(.clavixInk)
                    Text(centerDetail)
                        .font(ClavisTypography.clavixMono(8, weight: .regular))
                        .tracking(0.4)
                        .foregroundColor(.clavixInk3)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private struct Seg: Identifiable { let id: String; let start: Double; let end: Double; let color: Color }

    private func cumulative() -> [Seg] {
        var acc = 0.0
        return slices.compactMap { slice in
            guard slice.value > 0 else { return nil }
            let start = acc / total
            acc += slice.value
            return Seg(id: slice.id, start: start, end: acc / total, color: slice.color)
        }
    }
}

private struct AuditDonutArc: Shape {
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

/// A clean, bar-free stat row: label (+ caption), a prominent value, an optional
/// colored verdict pill, and a plain-language explainer sentence. Replaces the
/// shaded-region-and-dot gauges for metrics judged against a plain-English idea
/// (beta, momentum) rather than a peer distribution.
struct AuditStatRow: View {
    let label: String
    var caption: String? = nil
    let value: String
    var valueColor: Color = .clavixInk
    var pill: String? = nil
    var pillInk: Color = .clavixInk3
    var pillFill: Color = .clavixPaper2
    var explainer: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(ClavisTypography.inter(14, weight: .semibold))
                        .foregroundColor(.clavixInk)
                    if let caption {
                        Text(caption)
                            .font(ClavisTypography.clavixMono(9, weight: .regular))
                            .foregroundColor(.clavixInk3)
                    }
                }
                Spacer(minLength: 8)
                Text(value)
                    .font(ClavisTypography.clavixMono(18, weight: .semibold))
                    .foregroundColor(valueColor)
                if let pill {
                    Text(pill.uppercased())
                        .font(ClavisTypography.clavixMono(8, weight: .bold))
                        .tracking(0.4)
                        .foregroundColor(pillInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(pillFill)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            if let explainer {
                Text(explainer)
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Literal peak-to-trough illustration: a dashed "prior high" reference line and
/// a curve that falls away from it to the trough, so a drawdown reads as a price
/// dropping off a cliff — not an abstract severity bar. Text lives outside the
/// drawing area to avoid overlapping the curve.
struct AuditDrawdownDrop: View {
    let drawdown: Double        // negative fraction, e.g. -0.28
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let frac = CGFloat(min(1, abs(drawdown) / 0.6))   // full drop caps at -60%
            let peakY = h * 0.16
            let troughY = peakY + (h * 0.66) * frac
            let peakX = w * 0.14
            let troughX = w * 0.72
            let peak = CGPoint(x: peakX, y: peakY)
            let trough = CGPoint(x: troughX, y: troughY)

            ZStack {
                // Prior-high reference line.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: peakY))
                    p.addLine(to: CGPoint(x: w, y: peakY))
                }
                .stroke(Color.clavixRule2, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // The fall.
                Path { p in
                    p.move(to: peak)
                    p.addCurve(
                        to: trough,
                        control1: CGPoint(x: (peakX + troughX) / 2, y: peakY),
                        control2: CGPoint(x: (peakX + troughX) / 2, y: troughY)
                    )
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                // Partial recovery hint off the trough, faint.
                Path { p in
                    p.move(to: trough)
                    p.addLine(to: CGPoint(x: w * 0.92, y: troughY - (troughY - peakY) * 0.28))
                }
                .stroke(color.opacity(0.28), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                Circle()
                    .fill(Color.clavixInk3)
                    .frame(width: 7, height: 7)
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

enum AuditSupport {
    private static let isoFormatters: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]

        return [fractional, standard]
    }()

    private static let fallbackFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss"
        ]

        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter
        }
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func formattedAsOfDate(_ rawValue: String?) -> String {
        guard let rawValue, !rawValue.isEmpty else { return "Date unavailable" }
        if let parsedDate = isoFormatters.lazy.compactMap({ $0.date(from: rawValue) }).first {
            return displayFormatter.string(from: parsedDate)
        }
        if let parsedDate = fallbackFormatters.lazy.compactMap({ $0.date(from: rawValue) }).first {
            return displayFormatter.string(from: parsedDate)
        }
        return rawValue
    }
}

// MARK: - Price-series analytics (view-time, from data the app already fetches)

/// Pure, view-time analytics derived from a daily close series the app fetches
/// (`/prices/{ticker}`). Enriches audit views with real, always-fresh data points
/// (drawdown window, daily-move distribution, 52-week range, up/down capture,
/// sector correlation) without waiting on a backend recompute. The dimension
/// SCORE still comes from the backend; this is display enrichment only.
enum PriceSeriesAnalytics {

    struct Point {
        let date: Date
        let close: Double
    }

    struct DrawdownWindow {
        let peakIndex: Int
        let troughIndex: Int
        let peakDate: Date
        let peakClose: Double
        let troughDate: Date
        let troughClose: Double
        let drawdownPct: Double        // negative fraction, e.g. -0.278
        let recovered: Bool
        let slice: [Point]
        let peakSliceIndex: Int
        let troughSliceIndex: Int
    }

    struct ReturnBucket: Identifiable {
        let id: Int
        let label: String
        let count: Int
        let isNegative: Bool
        let isCenter: Bool
    }

    struct RangePosition {
        let low: Double
        let high: Double
        let last: Double
        let fraction: Double
    }

    struct CaptureStats {
        let upCapture: Double
        let downCapture: Double
        let upDays: Int
        let downDays: Int
    }

    // MARK: Series prep

    static func points(from prices: [PricePoint]) -> [Point] {
        var byDay: [Date: (Date, Double)] = [:]
        let cal = Calendar(identifier: .gregorian)
        for p in prices {
            let day = cal.startOfDay(for: p.recordedAt)
            byDay[day] = (p.recordedAt, p.price)
        }
        return byDay.keys.sorted().compactMap { day in
            byDay[day].map { Point(date: $0.0, close: $0.1) }
        }
    }

    static func dailyReturns(_ pts: [Point]) -> [(date: Date, ret: Double)] {
        guard pts.count > 1 else { return [] }
        var out: [(Date, Double)] = []
        for i in 1..<pts.count {
            let prev = pts[i - 1].close
            guard prev > 0 else { continue }
            out.append((pts[i].date, (pts[i].close - prev) / prev))
        }
        return out
    }

    // MARK: Drawdown window

    static func drawdownWindow(_ pts: [Point], trailing: Int = 252, contextBefore: Int = 15, contextAfter: Int = 30) -> DrawdownWindow? {
        guard pts.count >= 3 else { return nil }
        let series = Array(pts.suffix(trailing))
        var runningPeakIdx = 0
        var runningPeak = series[0].close
        var worst = 0.0
        var bestTrough = 0
        var bestPeakForTrough = 0
        for i in 0..<series.count {
            if series[i].close > runningPeak {
                runningPeak = series[i].close
                runningPeakIdx = i
            }
            if runningPeak > 0 {
                let dd = (series[i].close - runningPeak) / runningPeak
                if dd < worst {
                    worst = dd
                    bestTrough = i
                    bestPeakForTrough = runningPeakIdx
                }
            }
        }
        guard worst < 0 else { return nil }
        let peakIdx = bestPeakForTrough
        let troughIdx = bestTrough
        let sliceStart = max(0, peakIdx - contextBefore)
        let sliceEnd = min(series.count - 1, troughIdx + contextAfter)
        let slice = Array(series[sliceStart...sliceEnd])
        let recovered = series[troughIdx...].contains { $0.close >= series[peakIdx].close }
        return DrawdownWindow(
            peakIndex: peakIdx,
            troughIndex: troughIdx,
            peakDate: series[peakIdx].date,
            peakClose: series[peakIdx].close,
            troughDate: series[troughIdx].date,
            troughClose: series[troughIdx].close,
            drawdownPct: worst,
            recovered: recovered,
            slice: slice,
            peakSliceIndex: peakIdx - sliceStart,
            troughSliceIndex: troughIdx - sliceStart
        )
    }

    // MARK: Return distribution

    static func returnDistribution(_ pts: [Point], trailing: Int = 252) -> [ReturnBucket] {
        let rets = dailyReturns(Array(pts.suffix(trailing + 1))).map { $0.ret }
        let specs: [(String, Bool, Bool, (Double) -> Bool)] = [
            ("<-5%", true, false, { $0 <= -0.05 }),
            ("-5:-3", true, false, { $0 > -0.05 && $0 <= -0.03 }),
            ("-3:-1", true, false, { $0 > -0.03 && $0 <= -0.01 }),
            ("-1:+1", false, true, { $0 > -0.01 && $0 < 0.01 }),
            ("+1:+3", false, false, { $0 >= 0.01 && $0 < 0.03 }),
            ("+3:+5", false, false, { $0 >= 0.03 && $0 < 0.05 }),
            (">+5%", false, false, { $0 >= 0.05 }),
        ]
        return specs.enumerated().map { idx, spec in
            ReturnBucket(id: idx, label: spec.0, count: rets.filter { spec.3($0) }.count, isNegative: spec.1, isCenter: spec.2)
        }
    }

    static func worstBestDay(_ pts: [Point], trailing: Int = 252) -> (worst: Double, best: Double)? {
        let rets = dailyReturns(Array(pts.suffix(trailing + 1))).map { $0.ret }
        guard let worst = rets.min(), let best = rets.max() else { return nil }
        return (worst, best)
    }

    // MARK: 52-week range

    static func rangePosition(_ pts: [Point], trailing: Int = 252) -> RangePosition? {
        let series = Array(pts.suffix(trailing))
        guard let low = series.map(\.close).min(),
              let high = series.map(\.close).max(),
              let last = series.last?.close,
              high > low else { return nil }
        return RangePosition(low: low, high: high, last: last, fraction: (last - low) / (high - low))
    }

    // MARK: Up / down capture vs a benchmark

    static func capture(_ pts: [Point], benchmark: [Point], trailing: Int = 252) -> CaptureStats? {
        let cal = Calendar(identifier: .gregorian)
        func retsByDay(_ series: [Point]) -> [Date: Double] {
            var m: [Date: Double] = [:]
            for r in dailyReturns(series) { m[cal.startOfDay(for: r.date)] = r.ret }
            return m
        }
        let a = retsByDay(Array(pts.suffix(trailing + 1)))
        let b = retsByDay(Array(benchmark.suffix(trailing + 1)))
        let common = Set(a.keys).intersection(b.keys)
        guard common.count >= 20 else { return nil }
        var upA = 0.0, upB = 0.0, downA = 0.0, downB = 0.0, upN = 0, downN = 0
        for day in common {
            guard let ar = a[day], let br = b[day] else { continue }
            if br > 0 { upA += ar; upB += br; upN += 1 }
            else if br < 0 { downA += ar; downB += br; downN += 1 }
        }
        guard upB != 0, downB != 0, upN > 0, downN > 0 else { return nil }
        return CaptureStats(upCapture: upA / upB, downCapture: downA / downB, upDays: upN, downDays: downN)
    }

    /// Pearson correlation of daily returns between two aligned series (0..1 tightness).
    static func correlation(_ pts: [Point], other: [Point], trailing: Int = 120) -> Double? {
        let cal = Calendar(identifier: .gregorian)
        func retsByDay(_ series: [Point]) -> [Date: Double] {
            var m: [Date: Double] = [:]
            for r in dailyReturns(series) { m[cal.startOfDay(for: r.date)] = r.ret }
            return m
        }
        let a = retsByDay(Array(pts.suffix(trailing + 1)))
        let b = retsByDay(Array(other.suffix(trailing + 1)))
        let common = Array(Set(a.keys).intersection(b.keys))
        guard common.count >= 20 else { return nil }
        let xs = common.map { a[$0]! }
        let ys = common.map { b[$0]! }
        let mx = xs.reduce(0, +) / Double(xs.count)
        let my = ys.reduce(0, +) / Double(ys.count)
        var num = 0.0, dx = 0.0, dy = 0.0
        for i in 0..<xs.count {
            let a0 = xs[i] - mx, b0 = ys[i] - my
            num += a0 * b0; dx += a0 * a0; dy += b0 * b0
        }
        guard dx > 0, dy > 0 else { return nil }
        return num / (dx.squareRoot() * dy.squareRoot())
    }

    static func percentChange(_ pts: [Point], days: Int) -> Double? {
        let series = pts.suffix(days + 1)
        guard let first = series.first?.close, let last = series.last?.close, first > 0 else { return nil }
        return (last - first) / first
    }
}
