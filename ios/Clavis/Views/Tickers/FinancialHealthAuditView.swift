import SwiftUI

struct FinancialHealthAuditView: View {
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
                        AuditSectionCard(title: "Holdings Coverage") {
                            AuditValueRow(
                                label: "Holdings scored",
                                value: "\(dimension?.holdingsScoredCount ?? 0) of \(dimension?.holdingsCount ?? 0)",
                                status: "Coverage"
                            )
                            AuditValueRow(
                                label: "Weight covered",
                                value: dimension?.holdingsWeightCoveredPct.map { String(format: "%.1f%%", $0) } ?? "Unavailable",
                                status: "Coverage"
                            )
                            AuditValueRow(
                                label: "Top holding",
                                value: dimension?.topHoldingWeightPct.map { String(format: "%.1f%%", $0) } ?? "Unavailable",
                                status: "Weight"
                            )
                            AuditValueRow(
                                label: "Top 10 holdings",
                                value: dimension?.top10WeightPct.map { String(format: "%.1f%%", $0) } ?? "Unavailable",
                                status: "Weight"
                            )
                        }

                        let holdings = dimension?.holdings ?? []
                        if !holdings.isEmpty {
                            AuditSectionCard(title: "Top Holdings") {
                                ForEach(holdings) { holding in
                                    AuditValueRow(
                                        label: holding.ticker,
                                        value: holding.score.map { String(format: "%.0f", $0) } ?? "Unscored",
                                        status: holding.weightPct.map { String(format: "%.1f%%", $0) } ?? "—"
                                    )
                                }
                            }
                        }
                    } else {
                    AuditSectionCard(title: "Ratio Table") {
                        AuditValueRow(label: "D/E", value: decimal(dimension?.debtToEquity), status: status(for: dimension?.debtToEquity, lowIsGood: true))
                        AuditValueRow(label: "FCF Margin", value: percent(dimension?.fcfMargin), status: status(for: dimension?.fcfMargin, lowIsGood: false))
                        AuditValueRow(label: "Current Ratio", value: decimal(dimension?.currentRatio), status: status(for: dimension?.currentRatio, lowIsGood: false))
                        AuditValueRow(label: "Revenue Growth Trend", value: dimension?.revenueGrowthTrend?.humanizedTitleCasedDisplayText ?? "Unavailable", status: "Trend")
                        AuditValueRow(label: "Profitability Trend", value: dimension?.profitabilityTrend?.humanizedTitleCasedDisplayText ?? "Unavailable", status: "Trend")
                    }

                    AuditSectionCard(title: "Industry Comparison") {
                        Text("Your ticker is shown against its sector median when comparative data is available.")
                            .font(ClavisTypography.footnote)
                            .foregroundColor(.clavixInk3)
                        let medians = dimension?.sectorMedianComparison ?? [:]
                        if medians.isEmpty {
                            Text("Sector median comparison unavailable.")
                                .font(ClavisTypography.footnoteEmphasis)
                                .foregroundColor(.clavixInk)
                        } else {
                            ForEach(medians.keys.sorted(), id: \.self) { metric in
                                if let row = medians[metric] {
                                    AuditValueRow(
                                        label: metric.humanizedTitleCasedDisplayText,
                                        value: decimal(row.median),
                                        status: row.nTickers.map { "\($0) tickers" } ?? "Median"
                                    )
                                }
                            }
                        }
                        let peers = dimension?.peerComparisons ?? []
                        if !peers.isEmpty {
                            Text("Peers: " + peers.prefix(5).compactMap(\.ticker).joined(separator: ", "))
                                .font(ClavisTypography.footnoteEmphasis)
                                .foregroundColor(.clavixInk)
                        }
                    }
                    }
                }

                AuditSectionCard(title: "Methodology") {
                    Text(isETF
                         ? "Holdings Quality is the constituent-weighted Clavix score of the fund's latest available top holdings. It does not use company balance-sheet ratios for the ETF shell."
                         : "Financial Health measures the structural strength of the company. It uses balance-sheet and cash-flow inputs such as debt-to-equity ratio, free cash flow margin, current ratio, revenue growth trend, and profitability trend.")
                        .font(ClavisTypography.body)
                        .foregroundColor(.clavixInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, ClavisTheme.screenPadding)
            .padding(.vertical, ClavisTheme.sectionSpacing)
        }
        .background(Color.clavixPage.ignoresSafeArea())
        .navigationTitle(isETF ? "Holdings Quality" : "Financial Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func decimal(_ value: Double?) -> String {
        guard let value else { return "Unavailable" }
        return String(format: "%.2f", value)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "Unavailable" }
        return String(format: "%.1f%%", value * 100)
    }

    private func status(for value: Double?, lowIsGood: Bool) -> String {
        guard let value else { return "Unavailable" }
        if lowIsGood {
            return value < 1 ? "Healthy" : value < 2 ? "Watch" : "Stressed"
        }
        return value > 1 ? "Healthy" : value > 0.5 ? "Watch" : "Stressed"
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

func auditGrade(for score: Double?) -> String {
    guard let score else { return "\u{2014}" }
    return PortfolioMath.grade(forScore: score)
}

/// Horizontal 0 to 100 score track, filled to the dimension score in its band color.
struct AuditScoreBar: View {
    let score: Double?
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.clavixPaper2)
                Rectangle()
                    .fill(auditBandColor(score))
                    .frame(width: max(0, min(1, (score ?? 0) / 100)) * geo.size.width)
            }
        }
        .frame(height: 6)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.clavixRule, lineWidth: 1))
    }
}

/// Dimension masthead: ticker eyebrow, serif name, big score, band verdict, score bar.
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
                Text("/ 100")
                    .font(ClavisTypography.clavixMono(13, weight: .regular))
                    .foregroundColor(.clavixInk4)
                Spacer()
                Text(auditBandLabel(score))
                    .font(ClavisTypography.clavixMono(10, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(auditBandColor(score))
            }

            AuditScoreBar(score: score)

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

enum AuditVerdict { case good, warn, bad, neutral }

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

    private func fill(_ v: AuditVerdict) -> Color {
        switch v {
        case .good:    return .clavixGoodSoft
        case .warn:    return .clavixWarnSoft
        case .bad:     return .clavixBadSoft
        case .neutral: return .clavixPaper2
        }
    }
    private func ink(_ v: AuditVerdict) -> Color {
        switch v {
        case .good:    return .clavixGoodInk
        case .warn:    return .clavixWarnInk
        case .bad:     return .clavixBadInk
        case .neutral: return .clavixInk3
        }
    }

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
