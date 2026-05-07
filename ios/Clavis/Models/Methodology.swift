import Foundation

struct MethodologyResponse: Codable {
    let ticker: String
    let dimensions: MethodologyDimensions
    let composite: MethodologyComposite

    enum CodingKeys: String, CodingKey {
        case ticker
        case dimensions
        case composite
    }
}

struct MethodologyDimensions: Codable {
    let financialHealth: MethodologyDimension
    let newsSentiment: MethodologyDimension
    let macroExposure: MethodologyDimension
    let sectorExposure: MethodologyDimension
    let volatility: MethodologyDimension

    enum CodingKeys: String, CodingKey {
        case financialHealth = "financial_health"
        case newsSentiment = "news_sentiment"
        case macroExposure = "macro_exposure"
        case sectorExposure = "sector_exposure"
        case volatility = "volatility"
    }
}

struct MethodologyDimension: Codable, Identifiable {
    let score: Double?
    let label: String
    let inputs: [String: AnyCodable]?
    let regression: MacroRegressionData?
    let articles: [MethodologyArticle]?
    let articleCount: Int?
    let sources: [String]
    let betaProxy: Double?
    let macroSensitivity: String?

    var id: String { label }

    enum CodingKeys: String, CodingKey {
        case score
        case label
        case inputs
        case regression
        case articles
        case articleCount = "article_count"
        case sources
        case betaProxy = "beta_proxy"
        case macroSensitivity = "macro_sensitivity"
    }
}

struct MethodologyArticle: Codable, Identifiable {
    let id: String?
    let title: String?
    let source: String?
    let sentimentScore: Double?
    let sentimentReason: String?
    let sourceTier: Int?
    let recencyWeight: Double?
    let sourceWeight: Double?
    let impactTag: String?
    let tldr: String?
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case source
        case sentimentScore = "sentiment_score"
        case sentimentReason = "sentiment_reason"
        case sourceTier = "source_tier"
        case recencyWeight = "recency_weight"
        case sourceWeight = "source_weight"
        case impactTag = "impact_tag"
        case tldr
        case publishedAt = "published_at"
    }
}

struct MacroRegressionData: Codable, Hashable {
    let coefficients: [String: Double]?
    let rSquared: Double?
    let asOfDate: String?
    let tradingDaysUsed: Int?
    let limitedData: Bool?

    enum CodingKeys: String, CodingKey {
        case coefficients
        case rSquared = "r_squared"
        case asOfDate = "as_of_date"
        case tradingDaysUsed = "trading_days_used"
        case limitedData = "limited_data"
    }
}

struct MethodologyComposite: Codable {
    let grade: String?
    let score: Double?
    let methodologyVersion: String?

    enum CodingKeys: String, CodingKey {
        case grade
        case score
        case methodologyVersion = "methodology_version"
    }
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else if let stringVal = value as? String {
            try container.encode(stringVal)
        } else if let boolVal = value as? Bool {
            try container.encode(boolVal)
        } else {
            try container.encodeNil()
        }
    }
}
