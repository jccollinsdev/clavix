import SwiftUI

struct MacroExposureAuditView: View {
    @Environment(\.dismiss) private var dismiss
    let ticker: String
    let methodology: MethodologyResponse?

    private var dimension: MethodologyMacroExposure? { methodology?.dimensions.macroExposure }
    private let factorOrder = ["spy", "tnx", "dxy", "wti", "vix"]
    private var isReferenceMode: Bool { methodology == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                if isReferenceMode {
                    AuditReferenceContextView(
                        dimensionName: "Macro Exposure",
                        message: "Open a ticker from Search, Holdings, Alerts, or the Morning Report to see which macro forces move that stock."
                    )
                } else {
                    AuditHeaderCard(
                        title: "Macro Exposure",
                        ticker: ticker,
                        score: dimension?.score,
                        subtitle: headerSubtitle
                    )

                    if dimension?.limitedData == true {
                        AuditLimitedDataView(message: "Limited data: there was not enough clean price history to measure how this stock reacts to macro forces.")
                    } else {
                        AuditSectionCard(title: "What moves this stock") {
                            let rows = factorRows
                            if rows.isEmpty {
                                Text("No macro force stands out. This stock trades mostly on its own story rather than broad rates, the dollar, oil, or volatility.")
                                    .font(ClavisTypography.footnote)
                                    .foregroundColor(.clavixInk3)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(rows) { row in
                                    MacroFactorRow(row: row)
                                }
                                Text("Sensitivity is how strongly this stock has moved with each force over the measured window, not a forecast.")
                                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                                    .foregroundColor(.clavixInk4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 2)
                            }
                        }
                    }
                }

                AuditSectionCard(title: "How to read this") {
                    Text("Macro Exposure measures how much a stock is pushed around by broad forces rather than its own fundamentals. A higher score means it is more self-driven and less at the mercy of rates, the dollar, oil, and market-wide swings. We measure it from the historical relationship between this stock's returns and each of those forces.")
                        .font(ClavisTypography.body)
                        .foregroundColor(.clavixInk3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let narrative = dimension?.narrative, !narrative.isEmpty {
                        Text(narrative)
                            .font(ClavisTypography.footnote)
                            .foregroundColor(.clavixInk3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
        var parts: [String] = []
        if let r = dimension?.rSquared {
            parts.append("Broad forces explain \(Int((r * 100).rounded()))% of recent moves")
        }
        if let days = dimension?.tradingDaysUsed {
            parts.append("\(days) trading days")
        }
        return parts.isEmpty ? "Measured from recent price history" : parts.joined(separator: " · ")
    }

    private var factorRows: [MacroFactor] {
        let coeffs = dimension?.coefficients ?? [:]
        return factorOrder.compactMap { key -> MacroFactor? in
            guard let beta = coeffs[key] ?? nil, abs(beta) >= 0.08 else { return nil }
            return MacroFactor(key: key, beta: beta)
        }
        .sorted { abs($0.beta) > abs($1.beta) }
    }
}

// MARK: - Macro factor row

private struct MacroFactor: Identifiable {
    let key: String
    let beta: Double
    var id: String { key }

    var name: String {
        switch key {
        case "spy": return "Broad market (S&P 500)"
        case "tnx": return "10-Year Treasury yield"
        case "dxy": return "US Dollar"
        case "wti": return "Crude oil"
        case "vix": return "Market volatility (VIX)"
        default: return key.uppercased()
        }
    }

    /// Plain-language description of the historical relationship (with direction).
    var phrase: String {
        let up = beta >= 0
        switch key {
        case "spy": return up ? "Tends to move with the market" : "Tends to move against the market"
        case "tnx": return up ? "Rises when Treasury yields rise" : "Falls when Treasury yields rise"
        case "dxy": return up ? "Rises when the dollar strengthens" : "Falls when the dollar strengthens"
        case "wti": return up ? "Rises when crude oil rises" : "Falls when crude oil rises"
        case "vix": return up ? "Rises when volatility spikes" : "Falls when volatility spikes"
        default: return up ? "Moves in the same direction" : "Moves in the opposite direction"
        }
    }

    var strength: String {
        switch abs(beta) {
        case 1.5...: return "High"
        case 0.7..<1.5: return "Moderate"
        case 0.2..<0.7: return "Low"
        default: return "Minimal"
        }
    }

    /// 0…1 fill for the magnitude bar (caps at |beta| = 2.5).
    var magnitude: CGFloat { min(1, CGFloat(abs(beta) / 2.5)) }
    var isPositive: Bool { beta >= 0 }
}

private struct MacroFactorRow: View {
    let row: MacroFactor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.name)
                    .font(ClavisTypography.inter(14, weight: .semibold))
                    .foregroundColor(.clavixInk)
                Spacer(minLength: 8)
                Text(row.strength.uppercased())
                    .font(ClavisTypography.clavixMono(8, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(strengthInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(strengthFill)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(row.phrase)
                .font(ClavisTypography.footnote)
                .foregroundColor(.clavixInk3)
            // Signed magnitude bar: fills right of center when positive, left when negative.
            GeometryReader { geo in
                let half = geo.size.width / 2
                ZStack(alignment: .center) {
                    Rectangle().fill(Color.clavixRule2).frame(height: 4)
                    Rectangle().fill(Color.clavixRule).frame(width: 1, height: 10)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if !row.isPositive {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.clavixInk3)
                                .frame(width: row.magnitude * half, height: 6)
                        }
                    }
                    .frame(width: half)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 0) {
                        if row.isPositive {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.clavixAccent)
                                .frame(width: row.magnitude * half, height: 6)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: half)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(height: 12)
        }
        .padding(.vertical, 2)
    }

    private var strengthInk: Color {
        switch row.strength {
        case "High": return .clavixWarnInk
        case "Moderate": return .clavixAccentInk
        default: return .clavixInk3
        }
    }
    private var strengthFill: Color {
        switch row.strength {
        case "High": return .clavixWarnSoft
        case "Moderate": return .clavixAccentSoft
        default: return .clavixPaper2
        }
    }
}
