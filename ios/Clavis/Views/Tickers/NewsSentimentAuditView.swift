import SwiftUI

struct NewsSentimentAuditView: View {
    @Environment(\.dismiss) private var dismiss
    let ticker: String
    let methodology: MethodologyResponse?
    @State private var selectedArticle: MethodologyArticle?

    private var dimension: MethodologyNewsSentiment? { methodology?.dimensions.newsSentiment }
    private var isReferenceMode: Bool { methodology == nil }

    private var articles: [MethodologyArticle] {
        (dimension?.articles ?? []).filter { $0.sentimentScore != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClavisTheme.sectionSpacing) {
                if isReferenceMode {
                    AuditReferenceContextView(
                        dimensionName: "News Sentiment",
                        message: "Open a ticker from Search, Holdings, Alerts, or the Morning Report to see how recent coverage nets out for that stock."
                    )
                } else if articles.count < 3 {
                    AuditHeaderCard(
                        title: "News Sentiment",
                        ticker: ticker,
                        score: dimension?.score,
                        subtitle: subtitle
                    )
                    AuditLimitedDataView(
                        message: "Not enough clearly scorable coverage in the recent window to net out a signal. We only count articles with a real, company-specific implication, so thin weeks read as limited rather than a manufactured neutral."
                    )
                } else {
                    AuditHeaderCard(
                        title: "News Sentiment",
                        ticker: ticker,
                        score: dimension?.score,
                        subtitle: subtitle
                    )

                    sentimentMixCard
                    scoreDistributionCard
                    articlesCard

                    AuditSectionCard(title: "How to read this") {
                        Text("News Sentiment nets recent, company-specific coverage into a single 0–100 read. Higher means the balance of coverage is supportive; lower means it leans negative. More recent and more credible sources carry more weight. Articles without a clear company implication are left out rather than counted as neutral.")
                            .font(ClavisTypography.body)
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
        .sheet(item: $selectedArticle) { article in
            ArticleDetailSheet(article: article, ticker: ticker)
        }
    }

    private var subtitle: String {
        let n = articles.count
        let unit = n == 1 ? "article" : "articles"
        return "\(n) scored \(unit) · last 7 days"
    }

    // MARK: - Sentiment mix (donut, "like the holdings screen")

    private var counts: (bullish: Int, neutral: Int, bearish: Int) {
        var b = 0, n = 0, r = 0
        for a in articles {
            guard let s = a.sentimentScore else { continue }
            if s >= 60 { b += 1 } else if s <= 40 { r += 1 } else { n += 1 }
        }
        return (b, n, r)
    }

    private var sentimentMixCard: some View {
        let c = counts
        let total = max(c.bullish + c.neutral + c.bearish, 1)
        let slices: [SentimentSlice] = [
            SentimentSlice(id: "bullish", label: "Bullish", value: Double(c.bullish), color: .clavixGood, pct: c.bullish * 100 / total),
            SentimentSlice(id: "neutral", label: "Neutral", value: Double(c.neutral), color: .clavixInk4, pct: c.neutral * 100 / total),
            SentimentSlice(id: "bearish", label: "Bearish", value: Double(c.bearish), color: .clavixBad, pct: c.bearish * 100 / total),
        ]
        return AuditSectionCard(title: "Sentiment mix") {
            HStack(alignment: .center, spacing: 18) {
                SentimentDonut(
                    slices: slices,
                    centerPrimary: "\(articles.count)",
                    centerDetail: "articles"
                )
                .frame(width: 128, height: 128)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(slices) { slice in
                        HStack(spacing: 8) {
                            Circle().fill(slice.color).frame(width: 8, height: 8)
                            Text(slice.label)
                                .font(ClavisTypography.inter(13, weight: .medium))
                                .foregroundColor(.clavixInk)
                            Spacer(minLength: 8)
                            Text("\(Int(slice.value))")
                                .font(ClavisTypography.clavixMono(13, weight: .semibold))
                                .foregroundColor(.clavixInk)
                            Text("\(slice.pct)%")
                                .font(ClavisTypography.clavixMono(11, weight: .regular))
                                .foregroundColor(.clavixInk3)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(mixSummary)
                .font(ClavisTypography.footnote)
                .foregroundColor(.clavixInk3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private var mixSummary: String {
        let c = counts
        if c.bullish > c.bearish && c.bullish >= c.neutral {
            return "Coverage leans positive over the last week."
        }
        if c.bearish > c.bullish && c.bearish >= c.neutral {
            return "Coverage leans negative over the last week."
        }
        return "Coverage is mixed, with no clear directional lean."
    }

    // MARK: - Score distribution (histogram)

    private var scoreBuckets: [ScoreBucket] {
        let ranges: [(String, ClosedRange<Double>, Color)] = [
            ("0–20", 0...20, .clavixBad),
            ("20–40", 20...40, .clavixBad),
            ("40–60", 40...60, .clavixInk4),
            ("60–80", 60...80, .clavixGood),
            ("80–100", 80...100, .clavixGood),
        ]
        return ranges.enumerated().map { idx, r in
            let count = articles.filter { a in
                guard let s = a.sentimentScore else { return false }
                // Upper-inclusive only for the last bucket so 60 lands in 60–80, etc.
                if idx == ranges.count - 1 { return s >= r.1.lowerBound && s <= r.1.upperBound }
                return s >= r.1.lowerBound && s < r.1.upperBound
            }.count
            return ScoreBucket(label: r.0, count: count, color: r.2)
        }
    }

    private var scoreDistributionCard: some View {
        let buckets = scoreBuckets
        let maxCount = max(buckets.map(\.count).max() ?? 1, 1)
        return AuditSectionCard(title: "Score distribution") {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(buckets) { bucket in
                    VStack(spacing: 6) {
                        Text(bucket.count > 0 ? "\(bucket.count)" : " ")
                            .font(ClavisTypography.clavixMono(10, weight: .semibold))
                            .foregroundColor(.clavixInk3)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(bucket.count > 0 ? bucket.color : Color.clavixRule2)
                            .frame(height: max(4, CGFloat(bucket.count) / CGFloat(maxCount) * 78))
                        Text(bucket.label)
                            .font(ClavisTypography.clavixMono(8, weight: .regular))
                            .foregroundColor(.clavixInk4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 118, alignment: .bottom)
            HStack {
                Text("Bearish")
                    .font(ClavisTypography.clavixMono(9, weight: .bold))
                    .foregroundColor(.clavixBad)
                Spacer()
                Text("Bullish")
                    .font(ClavisTypography.clavixMono(9, weight: .bold))
                    .foregroundColor(.clavixGood)
            }
        }
    }

    // MARK: - Articles

    private var articlesCard: some View {
        AuditSectionCard(title: "Recent coverage") {
            VStack(spacing: 0) {
                ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                    Button(action: { selectedArticle = article }) {
                        articleRow(article)
                    }
                    .buttonStyle(.plain)
                    if index < articles.count - 1 {
                        Rectangle().fill(Color.clavixRule2).frame(height: 1)
                            .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private func articleRow(_ article: MethodologyArticle) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(article.title?.sanitizedDisplayText ?? "Untitled article")
                    .font(ClavisTypography.inter(14, weight: .semibold))
                    .foregroundColor(.clavixInk)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                Text("\(article.source ?? "Unknown") · \(NewsSentimentFormat.relative(article.publishedAt))")
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .foregroundColor(.clavixInk3)
                Text(cleanTldr(article.tldr))
                    .font(ClavisTypography.footnote)
                    .foregroundColor(.clavixInk3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            sentimentChip(article.sentimentScore)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func sentimentChip(_ score: Double?) -> some View {
        let label = NewsSentimentFormat.label(score)
        let color = NewsSentimentFormat.color(score)
        return VStack(spacing: 3) {
            Text(score.map { "\(Int($0.rounded()))" } ?? "—")
                .font(ClavisTypography.clavixMono(16, weight: .semibold))
                .foregroundColor(color)
            Text(label)
                .font(ClavisTypography.clavixMono(8, weight: .bold))
                .tracking(0.3)
                .foregroundColor(color)
        }
        .frame(width: 54)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func cleanTldr(_ tldr: String?) -> String {
        guard let text = tldr?.sanitizedDisplayText, !text.isEmpty else { return "Brief unavailable" }
        let lower = text.lowercased()
        let isJunk = lower.contains("navigation elements")
            || lower.contains("website navigation")
            || (lower.contains("article body") && lower.contains("navigation"))
            || lower.contains("making analysis impossible")
            || lower.contains("no substantive")
        return isJunk ? "Brief unavailable" : text
    }
}

// MARK: - Sentiment donut (matches the holdings composition ring)

private struct SentimentSlice: Identifiable {
    let id: String
    let label: String
    let value: Double
    let color: Color
    let pct: Int
}

private struct SentimentDonut: View {
    let slices: [SentimentSlice]
    let centerPrimary: String
    let centerDetail: String

    private var total: Double { max(slices.reduce(0) { $0 + $1.value }, 0.0001) }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let outer = side / 2
            let ring = max(13, outer * 0.34)
            let centerline = outer - ring / 2
            let gap: Double = slices.filter { $0.value > 0 }.count > 1 ? 1.6 : 0

            ZStack {
                Circle()
                    .stroke(Color.clavixRule2, lineWidth: ring)
                    .padding(ring / 2)

                let segments = cumulative()
                ForEach(segments, id: \.id) { seg in
                    NewsDonutArc(
                        startDeg: -90 + seg.start * 360 + gap,
                        endDeg: -90 + seg.end * 360 - gap,
                        centerlineRadius: centerline
                    )
                    .stroke(seg.color, style: StrokeStyle(lineWidth: ring, lineCap: .butt))
                }

                VStack(spacing: 1) {
                    Text(centerPrimary)
                        .font(ClavisTypography.clavixMono(20, weight: .bold))
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

private struct NewsDonutArc: Shape {
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

private struct ScoreBucket: Identifiable {
    let label: String
    let count: Int
    let color: Color
    var id: String { label }
}

// MARK: - Formatting helpers

enum NewsSentimentFormat {
    static func label(_ score: Double?) -> String {
        guard let s = score else { return "—" }
        if s >= 60 { return "BULLISH" }
        if s <= 40 { return "BEARISH" }
        return "NEUTRAL"
    }

    static func color(_ score: Double?) -> Color {
        guard let s = score else { return .clavixInk3 }
        if s >= 60 { return .clavixGood }
        if s <= 40 { return .clavixBad }
        return .clavixInk3
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// "2h ago" within three days, "Jun 26" beyond — never a raw ISO timestamp.
    static func relative(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "recently" }
        guard let date = isoFractional.date(from: raw) ?? iso.date(from: raw) else {
            return String(raw.prefix(10))
        }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 * 60 * 24 * 3 {
            return relative.localizedString(for: date, relativeTo: Date())
        }
        return shortDate.string(from: date)
    }
}
