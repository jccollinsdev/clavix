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
                Text(ClavisGradeStyle.displayGrade(grade))
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
        ClavisGradeStyle.riskColor(for: grade).opacity(0.18)
    }

    private func gradeForeground(_ grade: String) -> Color {
        grade == "—" ? .clavixInk3 : ClavisGradeStyle.riskColor(for: grade)
    }
}

struct RiskTreemap: View {
    let positions: [Position]

    private var ranked: [Position] {
        positions
            .filter { ($0.currentValue ?? 0) > 0 }
            .sorted { riskContribution($0) > riskContribution($1) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        GeometryReader { proxy in
            let rows = splitRows(ranked)
            VStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 2) {
                        let total = max(row.reduce(0) { $0 + layoutWeight($1) }, 1)
                        ForEach(row) { position in
                            cell(position)
                                .frame(
                                    width: (proxy.size.width - CGFloat(max(row.count - 1, 0)) * 2)
                                        * layoutWeight(position) / total
                                )
                        }
                    }
                }
            }
            // Round only the outer edge of the whole map; cells stay square inside.
            .clipShape(RoundedRectangle(cornerRadius: ClavixLayout.cardRadius, style: .continuous))
        }
    }

    private func splitRows(_ positions: [Position]) -> [[Position]] {
        guard positions.count > 2 else { return [positions] }
        let total = positions.reduce(0) { $0 + layoutWeight($1) }
        var first: [Position] = []
        var firstWeight = 0.0
        for position in positions {
            if firstWeight < total / 2 || first.isEmpty {
                first.append(position)
                firstWeight += layoutWeight(position)
            }
        }
        let firstIDs = Set(first.map(\.id))
        let second = positions.filter { !firstIDs.contains($0.id) }
        return second.isEmpty ? [first] : [first, second]
    }

    private func cell(_ position: Position) -> some View {
        let grade = position.resolvedRiskGrade ?? "—"
        return VStack(alignment: .leading, spacing: 4) {
            Text(position.ticker)
                .font(ClavisTypography.clavixMono(13, weight: .bold))
                .foregroundColor(.clavixInk)
            Spacer()
            Text(ClavisGradeStyle.displayGrade(grade))
                .font(ClavisTypography.clavixMono(17, weight: .bold))
                .foregroundColor(ClavisGradeStyle.riskColor(for: grade))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ClavisGradeStyle.riskColor(for: grade).opacity(0.20))
        .overlay(
            Rectangle()
                .stroke(ClavisGradeStyle.riskColor(for: grade).opacity(0.55), lineWidth: 1)
        )
    }

    private func positionValue(_ position: Position) -> Double {
        max(position.currentValue ?? 0, 1)
    }

    private func layoutWeight(_ position: Position) -> Double {
        sqrt(positionValue(position))
    }

    private func riskContribution(_ position: Position) -> Double {
        let risk = max(0, 100 - (position.totalScore ?? 50))
        return positionValue(position) * risk
    }
}
