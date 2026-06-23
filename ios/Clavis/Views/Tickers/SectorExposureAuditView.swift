import SwiftUI

struct SectorExposureAuditView: View {
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

                    AuditSectionCard(title: "Metrics") {
                        if isETF {
                            AuditValueRow(label: "Top holding", value: plainPercent(dimension?.topHoldingWeightPct), status: "Weight")
                            AuditValueRow(label: "Top 10 holdings", value: plainPercent(dimension?.top10WeightPct), status: "Weight")
                            AuditValueRow(label: "Concentration score", value: format(dimension?.concentrationScore), status: "Score")
                        } else {
                        AuditValueRow(label: "Sector Beta", value: format(dimension?.sectorBeta), status: "Metric")
                        AuditValueRow(label: "Sector Momentum (30d)", value: percent(dimension?.sectorMomentum30d), status: "Metric")
                        AuditValueRow(label: "Sector Breadth", value: percent(dimension?.sectorBreadth), status: "Metric")
                        // TODO: backend expose sector metric sparklines for the full audit screen.
                        Text("Sparklines will appear once historical sector metric series are returned.")
                            .font(ClavisTypography.footnote)
                            .foregroundColor(.clavixInk3)
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
        .navigationTitle(isETF ? "Concentration" : "Sector Exposure")
        .navigationBarTitleDisplayMode(.inline)
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
