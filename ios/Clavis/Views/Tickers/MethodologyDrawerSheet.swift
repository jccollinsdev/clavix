import SwiftUI

struct MethodologyDrawerSheet: View {
    let ticker: String
    let methodology: MethodologyResponse
    let tappedDimension: String

    @Environment(\.dismiss) private var dismiss
    @State private var expandedDimension: String
    @State private var selectedArticle: MethodologyArticle?

    init(ticker: String, methodology: MethodologyResponse, tappedDimension: String) {
        self.ticker = ticker
        self.methodology = methodology
        self.tappedDimension = tappedDimension
        _expandedDimension = State(initialValue: tappedDimension)
    }

    private var allDimensions: [(String, MethodologyDimension)] {
        [
            ("financial_health", methodology.dimensions.financialHealth),
            ("news_sentiment", methodology.dimensions.newsSentiment),
            ("macro_exposure", methodology.dimensions.macroExposure),
            ("sector_exposure", methodology.dimensions.sectorExposure),
            ("volatility", methodology.dimensions.volatility),
        ]
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    Divider().background(Color.border).padding(.vertical, 12)

                    ForEach(allDimensions, id: \.0) { key, dim in
                        MethodologyAccordionRow(
                            dimension: dim,
                            dimKey: key,
                            isExpanded: expandedDimension == key,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedDimension = (expandedDimension == key) ? "" : key
                                }
                            },
                            onArticleTap: { article in
                                selectedArticle = article
                            }
                        )
                        Divider().background(Color.border)
                    }

                    compositeFooter
                }
                .padding(.horizontal, ClavisTheme.screenPadding)
                .padding(.vertical, ClavisTheme.sectionSpacing)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("\(ticker) Methodology")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.informational)
                }
            }
        }
        .sheet(item: $selectedArticle) { article in
            ArticleDetailSheet(article: article, ticker: ticker)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let grade = methodology.composite.grade {
                HStack(spacing: 10) {
                    GradeBadge(grade: grade, size: .large)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Composite Grade")
                            .font(ClavisTypography.label)
                            .foregroundColor(.textSecondary)
                        if let score = methodology.composite.score {
                            Text("Score: \(Int(score.rounded()))")
                                .font(ClavisTypography.bodyEmphasis)
                                .foregroundColor(.textPrimary)
                        }
                    }
                }
            }

            if let version = methodology.composite.methodologyVersion {
                Text("Methodology v\(version)")
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private var compositeFooter: some View {
        VStack(spacing: 12) {
            Text("All five dimensions are weighted equally (20% each) in the composite score.")
                .font(ClavisTypography.footnote)
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            Text("Scores reflect model output based on available data. They do not constitute financial advice.")
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }
}

// MARK: - Accordion Row

private struct MethodologyAccordionRow: View {
    let dimension: MethodologyDimension
    let dimKey: String
    let isExpanded: Bool
    let onTap: () -> Void
    let onArticleTap: (MethodologyArticle) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    if let score = dimension.score {
                        Text("\(Int(score.rounded()))")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(ClavisGradeStyle.riskColor(for: scoreToGrade(score)))
                            .frame(width: 32)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(dimension.label)
                            .font(ClavisTypography.bodyEmphasis)
                            .foregroundColor(.textPrimary)
                        if dimension.score == nil {
                            Text("Limited Data")
                                .font(ClavisTypography.footnote)
                                .foregroundColor(.textTertiary)
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                dimensionDetailView
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func scoreToGrade(_ score: Double) -> String {
        switch score {
        case 90...100: return "AAA"
        case 80..<90:  return "AA"
        case 70..<80:  return "A"
        case 60..<70:  return "BBB"
        case 50..<60:  return "BB"
        case 40..<50:  return "B"
        case 30..<40:  return "CCC"
        case 20..<30:  return "CC"
        case 10..<20:  return "C"
        default:       return "F"
        }
    }

    @ViewBuilder
    private var dimensionDetailView: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch dimKey {
            case "financial_health":
                financialHealthDetail
            case "news_sentiment":
                newsSentimentDetail
            case "macro_exposure":
                macroExposureDetail
            case "sector_exposure":
                sectorExposureDetail
            case "volatility":
                volatilityDetail
            default:
                EmptyView()
            }

            Text("Sources: \(dimension.sources.joined(separator: ", "))")
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
                .padding(.top, 4)
        }
        .padding(.leading, 42)
    }

    // MARK: - Financial Health

    private var financialHealthDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let inputs = dimension.inputs {
                ForEach(["debt_to_equity", "fcf_margin", "interest_coverage", "current_ratio"], id: \.self) { key in
                    if let val = inputs[key] {
                        let status = ratioStatus(key: key, value: val)
                        HStack {
                            Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(ClavisTypography.footnote)
                                .foregroundColor(.textSecondary)
                            Spacer()
                            Text(val)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(statusColor(status))
                        }
                    }
                }

                if let profile = inputs["profitability_profile"] {
                    LabeledRow("Profitability", profile, .textSecondary)
                }
                if let leverage = inputs["leverage_profile"] {
                    LabeledRow("Leverage", leverage, .textSecondary)
                }
            } else {
                limitedDataLabel
            }
        }
    }

    private func ratioStatus(key: String, value: String) -> String {
        guard let num = Double(value) else { return "neutral" }
        switch key {
        case "debt_to_equity":
            return num > 3 ? "stressed" : (num > 1.5 ? "watch" : "healthy")
        case "interest_coverage":
            return num < 1.5 ? "stressed" : (num < 3 ? "watch" : "healthy")
        case "current_ratio":
            return num < 1 ? "stressed" : (num < 1.5 ? "watch" : "healthy")
        case "fcf_margin":
            return num < 0 ? "stressed" : (num < 0.05 ? "watch" : "healthy")
        default:
            return "neutral"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "healthy": return .gradeCAA
        case "watch":   return .gradeCBB
        case "stressed": return .gradeCF
        default:        return .textSecondary
        }
    }

    // MARK: - News Sentiment

    private var newsSentimentDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let count = dimension.articleCount {
                HStack {
                    Text("\(count) articles, last 7 days")
                        .font(ClavisTypography.footnote)
                        .foregroundColor(.textSecondary)
                    if count > 20 {
                        Text("HIGH VOLUME")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gradeCF)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gradeCF.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
            }

            if let articles = dimension.articles, !articles.isEmpty {
                ForEach(articles.prefix(10)) { article in
                    Button(action: { onArticleTap(article) }) {
                        articleRow(article)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                limitedDataLabel
            }
        }
    }

    private func articleRow(_ article: MethodologyArticle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(article.title ?? "")
                .font(ClavisTypography.footnoteEmphasis)
                .foregroundColor(.textPrimary)
                .lineLimit(2)

            HStack(spacing: 6) {
                if let source = article.source {
                    Text(source)
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                if let date = article.publishedAt {
                    Text("·")
                        .foregroundColor(.textTertiary)
                    Text(date.prefix(10))
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }

                if let score = article.sentimentScore {
                    sentimentPill(score)
                }

                if let tier = article.sourceTier {
                    tierBadge(tier)
                }

                if let rw = article.recencyWeight {
                    recencyBadge(rw)
                }
            }

            if let tldr = article.tldr, !tldr.isEmpty {
                Text(tldr)
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .lineLimit(3)
                    .padding(.top, 2)
            }
        }
        .padding(8)
        .background(Color.surfaceElevated.opacity(0.6))
        .cornerRadius(6)
    }

    private func sentimentPill(_ score: Double) -> some View {
        Text("\(Int(score.rounded()))")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(sentimentColor(score))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(sentimentColor(score).opacity(0.15))
            .cornerRadius(4)
    }

    private func sentimentColor(_ score: Double) -> Color {
        if score >= 70 { return .gradeCAA }
        if score >= 50 { return .gradeCBB }
        return .gradeCF
    }

    private func tierBadge(_ tier: Int) -> some View {
        Text("T\(tier)")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.gradeCAA)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.gradeCAA.opacity(0.12))
            .cornerRadius(3)
    }

    private func recencyBadge(_ weight: Double) -> some View {
        Text("\(Int(weight.rounded()))x")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.gradeCBBB)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.gradeCBBB.opacity(0.12))
            .cornerRadius(3)
    }

    // MARK: - Macro Exposure

    private var macroExposureDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reg = dimension.regression, let coefs = reg.coefficients {
                if let r2 = reg.rSquared {
                    Text("R\u{00B2} = \(String(format: "%.3f", r2))")
                        .font(ClavisTypography.footnote)
                        .foregroundColor(.textSecondary)
                }
                if let days = reg.tradingDaysUsed {
                    Text("\(days) trading days used")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                if let date = reg.asOfDate {
                    Text("As of \(date)")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }

                VStack(spacing: 4) {
                    ForEach(["tnx", "dxy", "wti", "vix", "spy"], id: \.self) { factor in
                        if let val = coefs[factor] {
                            HStack {
                                Text(factor.uppercased())
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Text(String(format: "%.4f", val))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(val >= 0 ? .gradeCAA : .gradeCF)
                                Image(systemName: val >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(val >= 0 ? .gradeCAA : .gradeCF)
                            }
                        }
                    }
                }
                .padding(.top, 4)

                if reg.limitedData == true {
                    limitedDataLabel
                }
            } else if let beta = dimension.betaProxy {
                Text("Beta proxy: \(String(format: "%.2f", beta))")
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.textSecondary)
                if let sens = dimension.macroSensitivity {
                    Text("Sensitivity: \(sens)")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
            } else {
                limitedDataLabel
            }
        }
    }

    // MARK: - Sector Exposure

    private var sectorExposureDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let inputs = dimension.inputs {
                if let sectorVal = inputs["sector"] {
                    LabeledRow("Sector", sectorVal, .textPrimary)
                }
                if let industryVal = inputs["industry"] {
                    LabeledRow("Industry", industryVal, .textSecondary)
                }
                if let mcVal = inputs["market_cap"] {
                    LabeledRow("Market Cap", formatMarketCapString(mcVal), .textSecondary)
                }
                if let betaVal = inputs["beta"] {
                    LabeledRow("Beta to SPY", betaVal, .textSecondary)
                }
            } else {
                limitedDataLabel
            }
        }
    }

    private var volatilityDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let inputs = dimension.inputs {
                if let betaVal = inputs["beta"] {
                    LabeledRow("Beta (252d)", betaVal, .textSecondary)
                }
                if let sensVal = inputs["macro_sensitivity"] {
                    LabeledRow("Macro Sensitivity", sensVal, .textSecondary)
                }
            } else {
                limitedDataLabel
            }
        }
    }

    private func formatMarketCapString(_ value: String) -> String {
        guard let num = Double(value) else { return value }
        if num >= 1e12 { return String(format: "$%.2fT", num / 1e12) }
        if num >= 1e9  { return String(format: "$%.2fB", num / 1e9) }
        return String(format: "$%.0fM", num / 1e6)
    }

    private var limitedDataLabel: some View {
        Text("Limited Data")
            .font(ClavisTypography.footnote)
            .foregroundColor(.gradeCBB)
            .padding(.vertical, 4)
    }
}
                if let industryVal = inputs["industry"], let anyI = industryVal as? AnyCodable {
                    LabeledRow("Industry", String(describing: anyI.value), .textSecondary)
                }
                if let mcVal = inputs["market_cap"], let anyM = mcVal as? AnyCodable {
                    let formatted = formatMarketCap(anyM.value)
                    LabeledRow("Market Cap", formatted, .textSecondary)
                }
                if let betaVal = inputs["beta"], let anyB = betaVal as? AnyCodable {
                    let beta = formatAny(anyB.value)
                    LabeledRow("Beta to SPY", beta, .textSecondary)
                }
            } else {
                limitedDataLabel
            }
        }
    }

    // MARK: - Volatility

    private var volatilityDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let inputs = dimension.inputs {
                if let betaVal = inputs["beta"], let anyB = betaVal as? AnyCodable {
                    let beta = formatAny(anyB.value)
                    LabeledRow("Beta (252d)", beta, .textSecondary)
                }
                if let sensVal = inputs["macro_sensitivity"], let anyS = sensVal as? AnyCodable {
                    LabeledRow("Macro Sensitivity", String(describing: anyS.value), .textSecondary)
                }
            } else {
                limitedDataLabel
            }
        }
    }

    // MARK: - Helpers

    private var limitedDataLabel: some View {
        Text("Limited Data")
            .font(ClavisTypography.footnote)
            .foregroundColor(.gradeCBB)
            .padding(.vertical, 4)
    }

    private func formatAny(_ value: Any) -> String {
        if let d = value as? Double {
            return String(format: "%.2f", d)
        }
        if let i = value as? Int {
            return String(i)
        }
        return String(describing: value)
    }

    private func formatMarketCap(_ value: Any) -> String {
        guard let num = value as? Double else { return String(describing: value) }
        if num >= 1e12 { return String(format: "$%.2fT", num / 1e12) }
        if num >= 1e9  { return String(format: "$%.2fB", num / 1e9) }
        return String(format: "$%.0fM", num / 1e6)
    }
}

// MARK: - Labeled Row

private struct LabeledRow: View {
    let label: String
    let value: String
    let color: Color

    init(_ label: String, _ value: String, _ color: Color) {
        self.label = label
        self.value = value
        self.color = color
    }

    var body: some View {
        HStack {
            Text(label)
                .font(ClavisTypography.footnote)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
    }
}
