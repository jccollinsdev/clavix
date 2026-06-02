import SwiftUI

struct SectorHeatmapItem: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let weight: Double       // 0.0 – 1.0 portfolio weight
    let changePct: Double?   // day change %, nil if unavailable
}

struct SectorHeatmapView: View {
    let items: [SectorHeatmapItem]

    private let columns = [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)]
    private let cellHeight: CGFloat = 68

    static func height(for count: Int) -> CGFloat {
        let rows = max(1, Int(ceil(Double(count) / 2.0)))
        return CGFloat(rows) * 68 + CGFloat(rows - 1)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(items) { item in
                cell(item)
            }
        }
        .background(Color.clavixRule)
    }

    private func cell(_ item: SectorHeatmapItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.symbol)
                    .font(ClavisTypography.clavixMono(12, weight: .bold))
                    .foregroundColor(cellForeground(item.changePct))
                Spacer()
                if let pct = item.changePct {
                    Text(formatPct(pct))
                        .font(ClavisTypography.clavixMono(10, weight: .semibold))
                        .foregroundColor(cellForeground(item.changePct).opacity(0.85))
                }
            }
            Text(item.name)
                .font(ClavisTypography.inter(10, weight: .regular))
                .foregroundColor(cellForeground(item.changePct).opacity(0.7))
                .lineLimit(1)
            Spacer()
            Text(formatWeight(item.weight))
                .font(ClavisTypography.clavixMono(10, weight: .regular))
                .foregroundColor(cellForeground(item.changePct).opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: cellHeight, alignment: .topLeading)
        .background(cellBackground(item.changePct))
    }

    private func cellBackground(_ changePct: Double?) -> Color {
        guard let pct = changePct else { return Color.clavixPaper }
        if pct >= 1.0 { return Color(hex: "#D4EFE3") }
        if pct >= 0.25 { return Color(hex: "#E8F5EE") }
        if pct <= -1.0 { return Color(hex: "#F5DADA") }
        if pct <= -0.25 { return Color(hex: "#FAE8E8") }
        return Color.clavixPaper
    }

    private func cellForeground(_ changePct: Double?) -> Color {
        guard let pct = changePct else { return .clavixInk }
        if pct >= 0.25 { return Color(hex: "#085041") }
        if pct <= -0.25 { return Color(hex: "#7A1A1A") }
        return .clavixInk
    }

    private func formatPct(_ pct: Double) -> String {
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", pct))%"
    }

    private func formatWeight(_ w: Double) -> String {
        "\(String(format: "%.1f", w * 100))% of portfolio"
    }
}
