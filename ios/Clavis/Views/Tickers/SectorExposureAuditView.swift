import SwiftUI

struct SectorExposureAuditView: View {
    let ticker: String
    let methodology: MethodologyResponse?
    let isETF: Bool

    private var dimension: MethodologySectorExposure? { methodology?.dimensions.sectorExposure }
    private var isReferenceMode: Bool { methodology == nil }
    private var screenTitle: String { isETF ? "Concentration" : "Sector Exposure" }
    private var referenceMessage: String {
        if isETF {
            return "Open an ETF from Search, Holdings, Alerts, or the Morning Report to inspect how concentrated the fund is across sectors, top holdings, and correlated narratives."
        }
        return "Open a ticker from Search, Holdings, Alerts, or the Morning Report to inspect live sector beta, momentum, breadth, and narrative context for that stock."
    }
    private var methodologyDescription: String {
        if isETF {
            return "Concentration measures how exposed an ETF is to narrow pockets of risk. Clavix looks at the sector ETF mapping, concentration signals, and narrative pressure around the fund's main exposures."
        }
        return "Sector Exposure measures how vulnerable a ticker is to its sector's current state. It considers sector beta, sector momentum versus the S&P 500, sector breadth, and sector-specific news."
    }

    init(ticker: String, methodology: MethodologyResponse?, isETF: Bool = false) {
        self.ticker = ticker
        self.methodology = methodology
        self.isETF = isETF
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                if isReferenceMode {
                    AuditReferenceContextView(
                        dimensionName: screenTitle,
                        message: referenceMessage
                    )
                } else {
                    AuditHeaderCard(
                        title: screenTitle,
                        ticker: ticker,
                        score: dimension?.score,
                        subtitle: "\(dimension?.sector ?? "Sector unavailable") · \(dimension?.sectorEtf ?? "ETF unavailable")"
                    )

                    AuditSectionCard(title: "Metrics") {
                        AuditValueRow(label: "Sector Beta", value: format(dimension?.sectorBeta), status: "Metric")
                        AuditValueRow(label: "Sector Momentum (30d)", value: percent(dimension?.sectorMomentum30d), status: "Metric")
                        AuditValueRow(label: "Sector Breadth", value: percent(dimension?.sectorBreadth), status: "Metric")
                        // TODO: backend expose sector metric sparklines for the full audit screen.
                        Text("Sparklines will appear once historical sector metric series are returned.")
                            .font(ClavisTypography.footnote)
                            .foregroundColor(.clavixInk3)
                    }

                    AuditSectionCard(title: "Narrative") {
                        Text(dimension?.narrative ?? "Sector narrative unavailable.")
                            .font(ClavisTypography.body)
                            .foregroundColor(.clavixInk3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                AuditSectionCard(title: "Methodology") {
                    Text(methodologyDescription)
                        .font(ClavisTypography.body)
                        .foregroundColor(.clavixInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, ClavisTheme.screenPadding)
            .padding(.vertical, ClavisTheme.sectionSpacing)
        }
        .background(Color.clavixPage.ignoresSafeArea())
        .navigationTitle(screenTitle)
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
}
