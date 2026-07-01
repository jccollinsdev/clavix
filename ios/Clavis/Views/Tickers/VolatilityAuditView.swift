import SwiftUI

struct VolatilityAuditView: View {
    @Environment(\.dismiss) private var dismiss
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

                    AuditSectionCard(title: "Price stability") {
                        Text(volatilitySummary)
                            .font(ClavisTypography.footnote)
                            .foregroundColor(.clavixInk3)
                            .fixedSize(horizontal: false, vertical: true)
                        AuditValueRow(label: "Swings, last month", value: percent(dimension?.realizedVol30d), status: "Annualized", caption: "How much the price moved")
                        AuditValueRow(label: "Swings, last quarter", value: percent(dimension?.realizedVol90d), status: "Annualized", caption: "Longer-run baseline")
                        AuditValueRow(label: "Trend", value: trendValue, status: (dimension?.volRatio ?? 1) > 1.05 ? "Rising" : (dimension?.volRatio ?? 1) < 0.95 ? "Falling" : "Steady", caption: "Recent swings vs baseline")
                        AuditValueRow(label: "Worst drop, past year", value: percent(dimension?.maxDrawdown252d), status: "From Peak", caption: "Largest fall from a high")
                        AuditValueRow(label: "Market sensitivity", value: format(dimension?.betaToSpy), status: "Beta", caption: "Move per 1% market move")
                        if dimension?.ivSource?.lowercased() == "polygon" {
                            AuditValueRow(label: "Options-implied vol", value: percent(dimension?.impliedVolatility), status: "Live", caption: "What options pricing expects")
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
        .safeAreaInset(edge: .top, spacing: 0) {
            ClavixReportBar(onBack: { dismiss() })
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var trendValue: String {
        guard let ratio = dimension?.volRatio else { return "—" }
        if ratio > 1.05 { return "Getting choppier" }
        if ratio < 0.95 { return "Calming down" }
        return "Holding steady"
    }

    private var volatilitySummary: String {
        guard let score = dimension?.score else {
            return "How much this stock's price swings, and whether the swings are picking up or settling down."
        }
        if score >= 67 {
            return "Price has been relatively calm and steady — smaller swings than the typical stock."
        }
        if score >= 34 {
            return "Price swings are middle-of-the-road — neither unusually calm nor especially wild."
        }
        return "Price has been swinging hard — expect a bumpier ride than the typical stock."
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
