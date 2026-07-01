import SwiftUI

struct SectorExposureAuditView: View {
    @Environment(\.dismiss) private var dismiss
    let ticker: String
    let methodology: MethodologyResponse?
    var isETF: Bool = false

    private var dimension: MethodologySectorExposure? { methodology?.dimensions.sectorExposure }
    private var isReferenceMode: Bool { methodology == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                if isReferenceMode {
                    AuditReferenceContextView(
                        dimensionName: isETF ? "Concentration" : "Sector Exposure",
                        message: isETF
                            ? "Open a fund to inspect top-holding concentration from its latest constituent file."
                            : "Open a ticker from Search, Holdings, Alerts, or the Morning Report to inspect live sector beta, momentum, breadth, and narrative context for that stock."
                    )
                } else {
                    AuditHeaderCard(
                        title: isETF ? "Concentration" : "Sector Exposure",
                        ticker: ticker,
                        score: dimension?.score,
                        subtitle: isETF
                            ? "\(dimension?.holdingsCount ?? 0) reported holdings"
                            : "\(dimension?.sector ?? "Sector unavailable") · \(dimension?.sectorEtf ?? "ETF unavailable")"
                    )

                    AuditSectionCard(title: isETF ? "Concentration" : "Sector health") {
                        if isETF {
                            Text("How much of the fund rides on its largest positions. The more the top names dominate, the more the fund's fate is tied to a handful of stocks.")
                                .font(ClavisTypography.footnote)
                                .foregroundColor(.clavixInk3)
                                .fixedSize(horizontal: false, vertical: true)
                            AuditValueRow(label: "Largest holding", value: plainPercent(dimension?.topHoldingWeightPct), status: "Weight", caption: "Share in the single biggest name")
                            AuditValueRow(label: "Top 10 holdings", value: plainPercent(dimension?.top10WeightPct), status: "Weight", caption: "Share in the 10 biggest names")
                        } else {
                            Text(sectorSummary)
                                .font(ClavisTypography.footnote)
                                .foregroundColor(.clavixInk3)
                                .fixedSize(horizontal: false, vertical: true)
                            AuditValueRow(label: "Sector sensitivity", value: format(dimension?.sectorBeta), status: "Beta", caption: "How much it tracks its sector")
                            AuditValueRow(label: "Sector momentum", value: percent(dimension?.sectorMomentum30d), status: momentumStatus(dimension?.sectorMomentum30d), caption: "Sector's 30-day trend vs the market")
                            AuditValueRow(label: "Sector breadth", value: percent(dimension?.sectorBreadth), status: "Participation", caption: "How broadly the sector is advancing")
                        }
                    }

                    if !isETF {
                    AuditSectionCard(title: "Narrative") {
                        Text(dimension?.narrative ?? "Sector narrative unavailable.")
                            .font(ClavisTypography.body)
                            .foregroundColor(.clavixInk3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    }
                }

                AuditSectionCard(title: "Methodology") {
                    Text(isETF
                         ? "Concentration measures how much of the fund is controlled by its largest reported holdings. Lower concentration generally improves diversification resilience."
                         : "Sector Exposure measures how vulnerable a ticker is to its sector's current state. It considers sector beta, sector momentum versus the S&P 500, sector breadth, and sector-specific news.")
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

    private var sectorSummary: String {
        let sector = dimension?.sector ?? "its sector"
        guard let score = dimension?.score else {
            return "How \(sector) is doing right now, and how tightly this stock is tied to it."
        }
        if score >= 67 {
            return "\(sector) is in good shape and broadly supportive right now, a tailwind for names in the group."
        }
        if score >= 34 {
            return "\(sector) is sending mixed signals — neither a clear tailwind nor a strong headwind."
        }
        return "\(sector) is under pressure right now, a headwind this stock has to fight against."
    }

    /// Neutral, unambiguous labels (the shared verdict colors are risk-framed, where
    /// "rising" reads as caution — wrong for sector momentum, so we stay neutral).
    private func momentumStatus(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value > 0.005 { return "Tailwind" }
        if value < -0.005 { return "Headwind" }
        return "Flat"
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value * 100)
    }

    private func plainPercent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }
}
