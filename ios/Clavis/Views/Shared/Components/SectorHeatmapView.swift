import SwiftUI

struct SectorHeatmapItem: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let weight: Double       // 0.0 – 1.0 portfolio weight
    let changePct: Double?   // sector ETF day change %, nil if unavailable
}

/// Sector weight map: each sector is a full-width band whose height is
/// proportional to its share of the portfolio (floored at 10% so small
/// sectors stay legible), tinted by its sector ETF's move on the day.
struct SectorHeatmapView: View {
    let items: [SectorHeatmapItem]

    /// Minimum share any sector occupies, regardless of true weight.
    private let weightFloor: Double = 0.10

    static func height(for count: Int) -> CGFloat {
        let c = max(1, count)
        return min(max(CGFloat(c) * 58, 150), 430)
    }

    var body: some View {
        GeometryReader { geo in
            let heights = proportionalHeights(total: geo.size.height, spacing: 1)
            VStack(spacing: 1) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    cell(item)
                        .frame(height: heights.indices.contains(idx) ? heights[idx] : nil)
                }
            }
        }
        .background(Color.clavixRule)
    }

    private func proportionalHeights(total: CGFloat, spacing: CGFloat) -> [CGFloat] {
        let n = items.count
        guard n > 0 else { return [] }
        let available = max(0, total - spacing * CGFloat(n - 1))
        let effective = items.map { max($0.weight, weightFloor) }
        let sum = effective.reduce(0, +)
        guard sum > 0 else {
            let even = available / CGFloat(n)
            return Array(repeating: even, count: n)
        }
        return effective.map { available * CGFloat($0 / sum) }
    }

    private func cell(_ item: SectorHeatmapItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.symbol)
                    .font(ClavisTypography.clavixMono(13, weight: .bold))
                    .foregroundColor(cellForeground(item.changePct))
                Text(item.name)
                    .font(ClavisTypography.inter(11, weight: .regular))
                    .foregroundColor(cellForeground(item.changePct).opacity(0.72))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                if let pct = item.changePct {
                    Text(formatPct(pct))
                        .font(ClavisTypography.clavixMono(11, weight: .semibold))
                        .foregroundColor(cellForeground(item.changePct))
                }
                Text(formatWeight(item.weight))
                    .font(ClavisTypography.clavixMono(9, weight: .regular))
                    .foregroundColor(cellForeground(item.changePct).opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cellBackground(item.changePct))
    }

    private func cellBackground(_ changePct: Double?) -> Color {
        guard let pct = changePct else { return Color.clavixPaper }
        if pct >= 1.5 { return Color(hex: "#C2E9D6") }
        if pct >= 0.5 { return Color(hex: "#D9F0E4") }
        if pct >= 0.1 { return Color(hex: "#E8F5EE") }
        if pct <= -1.5 { return Color(hex: "#F0CACA") }
        if pct <= -0.5 { return Color(hex: "#F5D9D9") }
        if pct <= -0.1 { return Color(hex: "#FAE8E8") }
        return Color.clavixPaper
    }

    private func cellForeground(_ changePct: Double?) -> Color {
        guard let pct = changePct else { return .clavixInk }
        if pct >= 0.1 { return Color(hex: "#085041") }
        if pct <= -0.1 { return Color(hex: "#7A1A1A") }
        return .clavixInk
    }

    private func formatPct(_ pct: Double) -> String {
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", pct))%"
    }

    private func formatWeight(_ w: Double) -> String {
        "\(String(format: "%.0f", w * 100))% of book"
    }
}
