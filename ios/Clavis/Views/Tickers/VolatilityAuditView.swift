import SwiftUI

struct VolatilityAuditView: View {
    let ticker: String
    let methodology: MethodologyResponse?
    let scoreHistory: [ScoreSnapshot]

    private var dimension: MethodologyVolatility? { methodology?.dimensions.volatility }
    private var isReferenceMode: Bool { methodology == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                if isReferenceMode {
                    AuditReferenceContextView(
                        dimensionName: "Volatility",
                        message: "Open a ticker from Search, Holdings, Alerts, or the Morning Report to inspect live realized volatility, drawdown, beta, and implied-vol inputs for that stock."
                    )
                } else {
                    AuditHeaderCard(
                        title: "Volatility",
                        ticker: ticker,
                        score: dimension?.score,
                        subtitle: "Updated \(AuditSupport.formattedAsOfDate(dimension?.asOfDate))"
                    )

                    AuditSectionCard(title: "Metrics") {
                        AuditValueRow(label: "Realized Vol 30d", value: percent(dimension?.realizedVol30d), status: "Annualized")
                        AuditValueRow(label: "Realized Vol 90d", value: percent(dimension?.realizedVol90d), status: "Annualized")
                        AuditValueRow(label: "Vol Ratio (30d/90d)", value: format(dimension?.volRatio), status: (dimension?.volRatio ?? 1) > 1 ? "Rising" : "Falling")
                        AuditValueRow(label: "Max Drawdown 252d", value: percent(dimension?.maxDrawdown252d), status: "From Peak")
                        AuditValueRow(label: "Beta to SPY", value: format(dimension?.betaToSpy), status: "Correlation")
                        if dimension?.ivSource?.lowercased() == "polygon" {
                            AuditValueRow(label: "Options IV 30d", value: percent(dimension?.impliedVolatility), status: "Live")
                            AuditValueRow(label: "IV Rank", value: dimension?.ivRank.map { String(format: "%.1f", $0) } ?? "—", status: "Percentile")
                        } else {
                            AuditValueRow(label: "Vol Regime Proxy", value: dimension?.ivRank.map { String(format: "%.1f", $0) } ?? "—", status: "Estimated")
                        }
                    }

                    AuditSectionCard(title: "Vol Trend") {
                        // TODO: backend expose volatility-specific history for the full audit screen.
                        ScoreHistoryChart(snapshots: scoreHistory, showAllDimensions: false, toggledDimensions: .constant([]))
                    }
                }

                AuditSectionCard(title: "Methodology") {
                    Text("Volatility measures price instability and whether it is rising or falling. Inputs include 30-day realized volatility, 90-day realized volatility, the 30-day/90-day volatility ratio, maximum drawdown from the trailing 252-day high, and beta to the S&P 500.")
                        .font(ClavisTypography.body)
                        .foregroundColor(.clavixInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, ClavisTheme.screenPadding)
            .padding(.vertical, ClavisTheme.sectionSpacing)
        }
        .background(Color.clavixPage.ignoresSafeArea())
        .navigationTitle("Volatility")
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
