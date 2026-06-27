import SwiftUI

struct SectorHeatmapItem: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let weight: Double       // 0.0 – 1.0 portfolio weight
    let changePct: Double?   // sector ETF day change %, nil if unavailable
}

/// Finviz-style sector treemap: each sector is a tile whose AREA is
/// proportional to its share of the portfolio, packed via a squarified
/// treemap, and tinted by its sector ETF's move on the day.
struct SectorHeatmapView: View {
    let items: [SectorHeatmapItem]

    /// Floor so a tiny sector still gets a visible, tappable tile.
    private let weightFloor: Double = 0.05

    static func height(for count: Int) -> CGFloat {
        // A roughly 4:3 canvas scaled to sector count.
        let c = max(1, count)
        return min(max(CGFloat(c) * 46, 220), 360)
    }

    var body: some View {
        GeometryReader { geo in
            let frames = layoutFrames(in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.clavixRule
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if frames.indices.contains(index) {
                        let f = frames[index].insetBy(dx: 0.5, dy: 0.5)
                        tile(item, size: f.size)
                            .frame(width: max(0, f.width), height: max(0, f.height))
                            .position(x: f.midX, y: f.midY)
                    }
                }
            }
        }
    }

    // MARK: - Tile

    private func tile(_ item: SectorHeatmapItem, size: CGSize) -> some View {
        let minSide = min(size.width, size.height)
        // Sector names are longer than 3-letter tickers, so cap the label size
        // lower and allow two lines to wrap inside the tile.
        let labelSize = max(9, min(minSide * 0.24, 16))
        let showChange = size.height > 36 && size.width > 46
        let showWeight = size.height > 58 && size.width > 60
        let ink = textColor(item.changePct)
        let label = item.name.isEmpty ? item.symbol : item.name

        return VStack(spacing: 2) {
            Text(label)
                .font(ClavisTypography.clavixMono(labelSize, weight: .bold))
                .foregroundColor(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
            if showChange, let pct = item.changePct {
                Text(formatPct(pct))
                    .font(ClavisTypography.clavixMono(max(8, labelSize * 0.6), weight: .semibold))
                    .foregroundColor(ink.opacity(0.95))
                    .lineLimit(1)
            }
            if showWeight {
                Text(formatWeight(item.weight))
                    .font(ClavisTypography.clavixMono(8, weight: .regular))
                    .foregroundColor(ink.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(fill(item.changePct))
        .clipped()
    }

    // MARK: - Squarified treemap layout

    private func layoutFrames(in size: CGSize) -> [CGRect] {
        let n = items.count
        guard n > 0, size.width > 0, size.height > 0 else {
            return Array(repeating: .zero, count: n)
        }
        // Lay out largest-first for good aspect ratios, then map back to order.
        let order = (0..<n).sorted { effectiveWeight(items[$0]) > effectiveWeight(items[$1]) }
        let sortedWeights = order.map { effectiveWeight(items[$0]) }
        let sortedFrames = Self.squarify(weights: sortedWeights, bounds: CGRect(origin: .zero, size: size))
        var result = Array(repeating: CGRect.zero, count: n)
        for (k, originalIndex) in order.enumerated() where k < sortedFrames.count {
            result[originalIndex] = sortedFrames[k]
        }
        return result
    }

    private func effectiveWeight(_ item: SectorHeatmapItem) -> CGFloat {
        CGFloat(max(item.weight, weightFloor))
    }

    /// Bruls et al. squarified treemap. `weights` must be descending for the
    /// best aspect ratios.
    private static func squarify(weights: [CGFloat], bounds: CGRect) -> [CGRect] {
        let total = weights.reduce(0, +)
        guard total > 0 else { return weights.map { _ in .zero } }
        let scale = (bounds.width * bounds.height) / total
        let areas = weights.map { $0 * scale }

        var frames = [CGRect](repeating: .zero, count: weights.count)
        var remaining = bounds
        var i = 0
        let n = areas.count

        while i < n {
            let shorter = min(remaining.width, remaining.height)
            guard shorter > 0 else { break }

            // Grow the row while the worst aspect ratio keeps improving.
            var end = i
            var rowSum = areas[i]
            var bestWorst = Self.worst(maxA: areas[i], minA: areas[i], sum: rowSum, side: shorter)
            var j = i + 1
            while j < n {
                let newSum = rowSum + areas[j]
                let newMax = max(areas[i...j].max() ?? areas[j], areas[j])
                let newMin = min(areas[i...j].min() ?? areas[j], areas[j])
                let w = Self.worst(maxA: newMax, minA: newMin, sum: newSum, side: shorter)
                if w <= bestWorst {
                    bestWorst = w
                    rowSum = newSum
                    end = j
                    j += 1
                } else {
                    break
                }
            }

            let thickness = rowSum / shorter
            if remaining.width >= remaining.height {
                // Column along the left edge; thickness measured in x.
                var y = remaining.minY
                for k in i...end {
                    let h = areas[k] / thickness
                    frames[k] = CGRect(x: remaining.minX, y: y, width: thickness, height: h)
                    y += h
                }
                remaining = CGRect(x: remaining.minX + thickness, y: remaining.minY,
                                   width: remaining.width - thickness, height: remaining.height)
            } else {
                // Row along the top edge; thickness measured in y.
                var x = remaining.minX
                for k in i...end {
                    let w = areas[k] / thickness
                    frames[k] = CGRect(x: x, y: remaining.minY, width: w, height: thickness)
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + thickness,
                                   width: remaining.width, height: remaining.height - thickness)
            }
            i = end + 1
        }
        return frames
    }

    private static func worst(maxA: CGFloat, minA: CGFloat, sum: CGFloat, side: CGFloat) -> CGFloat {
        guard sum > 0, side > 0, minA > 0 else { return .greatestFiniteMagnitude }
        let side2 = side * side
        let sum2 = sum * sum
        return max((side2 * maxA) / sum2, sum2 / (side2 * minA))
    }

    // MARK: - Color

    private func fill(_ changePct: Double?) -> Color {
        guard let pct = changePct else { return Color(hex: "#8C8A7E") }
        switch pct {
        case 2...:        return Color(hex: "#1B7A4B")
        case 1..<2:       return Color(hex: "#2E9D63")
        case 0.2..<1:     return Color(hex: "#57B485")
        case -0.2..<0.2:  return Color(hex: "#9AA08C")
        case -1 ..< -0.2: return Color(hex: "#D38B8B")
        case -2 ..< -1:   return Color(hex: "#C75D5D")
        default:          return Color(hex: "#B23A3A")
        }
    }

    private func textColor(_ changePct: Double?) -> Color {
        guard let pct = changePct else { return .white }
        // Light mid-tones read better with dark ink; saturated tiles with white.
        if pct >= 0.2 && pct < 1 { return Color(hex: "#0A3D28") }
        if pct < -0.2 && pct >= -1 { return Color(hex: "#5C1414") }
        if pct >= -0.2 && pct < 0.2 { return Color(hex: "#2B2A22") }
        return .white
    }

    private func formatPct(_ pct: Double) -> String {
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", pct))%"
    }

    private func formatWeight(_ w: Double) -> String {
        "\(String(format: "%.0f", w * 100))%"
    }
}
