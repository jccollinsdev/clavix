import Foundation

enum PortfolioMath {
    /// Value-weighted portfolio composite score per CLAVIX_TRUTH §9.
    /// Σ(market_value × score) / Σ(market_value), excluding holdings without a score or value.
    /// Returns nil when no scored, valued holdings exist.
    static func weightedScore(_ holdings: [Position]) -> Double? {
        let weightedPairs = holdings.compactMap { position -> (Double, Double)? in
            guard let value = position.currentValue, value > 0,
                  let score = position.resolvedTotalScore else { return nil }
            return (value, score)
        }
        let totalWeight = weightedPairs.reduce(0) { $0 + $1.0 }
        guard totalWeight > 0 else { return nil }
        return weightedPairs.reduce(0) { $0 + ($1.0 * $1.1) } / totalWeight
    }

    /// Grade derived from a 0-100 composite score using the academic ladder.
    /// SINGLE source of truth for score -> letter across the app. Higher score =
    /// lower risk. Letters best->worst: A+, A, A-, B+, B, B-, C+, C, C-, D+, D, D-, F.
    static func grade(forScore score: Double) -> String {
        switch score {
        case 90...:   return "A+"
        case 85..<90: return "A"
        case 80..<85: return "A-"
        case 75..<80: return "B+"
        case 70..<75: return "B"
        case 65..<70: return "B-"
        case 60..<65: return "C+"
        case 55..<60: return "C"
        case 50..<55: return "C-"
        case 45..<50: return "D+"
        case 40..<45: return "D"
        case 35..<40: return "D-"
        default:      return "F"
        }
    }

    /// Convenience: value-weighted grade. Returns "—" when score is unavailable.
    static func weightedGrade(_ holdings: [Position]) -> String {
        guard let score = weightedScore(holdings) else { return "—" }
        return grade(forScore: score)
    }
}
