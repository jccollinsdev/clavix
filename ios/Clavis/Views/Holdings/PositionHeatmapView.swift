import SwiftUI

struct PositionHeatmapView: View {
    let positions: [Position]

    private let columns = [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)]
    private let cellHeight: CGFloat = 72

    static func height(for count: Int) -> CGFloat {
        let rows = max(1, Int(ceil(Double(count) / 2.0)))
        return CGFloat(rows) * 72 + CGFloat(rows - 1)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(positions) { position in
                cell(position)
            }
        }
        .background(Color.clavixRule)
    }

    private func cell(_ position: Position) -> some View {
        let grade = position.resolvedRiskGrade ?? "—"
        let bg = gradeBackground(grade)
        let fg = gradeForeground(grade)

        return VStack(alignment: .leading, spacing: 4) {
            Text(position.ticker)
                .font(ClavisTypography.clavixMono(13, weight: .bold))
                .foregroundColor(fg)
            Spacer()
            HStack(alignment: .bottom) {
                Text(grade)
                    .font(ClavisTypography.clavixMono(20, weight: .bold))
                    .foregroundColor(fg)
                Spacer()
                if let score = position.totalScore {
                    Text("\(Int(score.rounded()))")
                        .font(ClavisTypography.clavixMono(10, weight: .regular))
                        .foregroundColor(fg.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: cellHeight, alignment: .topLeading)
        .background(bg)
    }

    private func gradeBackground(_ grade: String) -> Color {
        switch grade {
        case "AAA": return Color(hex: "#D4EFE3")
        case "AA":  return Color(hex: "#DCF5E6")
        case "A":   return Color(hex: "#E1F5EE")
        case "BBB": return Color(hex: "#DFF0EF")
        case "BB":  return Color(hex: "#FCF2E2")
        case "B":   return Color(hex: "#FDE8CC")
        case "CCC": return Color(hex: "#FAE0CC")
        case "CC":  return Color(hex: "#F9D5CC")
        case "C":   return Color(hex: "#F5CACA")
        case "F":   return Color(hex: "#F0BCBC")
        default:    return Color.clavixPaper
        }
    }

    private func gradeForeground(_ grade: String) -> Color {
        switch grade {
        case "AAA", "AA": return Color(hex: "#085041")
        case "A":         return Color(hex: "#126B5C")
        case "BBB":       return Color(hex: "#10555A")
        case "BB":        return Color(hex: "#7A5C00")
        case "B":         return Color(hex: "#7A3A00")
        case "CCC":       return Color(hex: "#7A3000")
        case "CC", "C":   return Color(hex: "#7A1A1A")
        case "F":         return Color(hex: "#601010")
        default:          return .clavixInk3
        }
    }
}
