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
    let inputs: [String: String]?
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
