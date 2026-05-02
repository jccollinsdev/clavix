import Foundation

enum DriverCardsState: String, Codable, CaseIterable {
    case ready
    case limited
    case empty
    case pending
}

enum DriverStrength: String, Codable, CaseIterable {
    case strong
    case moderate
    case limited

    var displayName: String {
        switch self {
        case .strong: return "Strong"
        case .moderate: return "Moderate"
        case .limited: return "Limited"
        }
    }
}

enum DriverDirection: String, Codable, CaseIterable {
    case positive
    case negative
    case neutral

    var displayName: String {
        switch self {
        case .positive: return "Positive"
        case .negative: return "Negative"
        case .neutral: return "Neutral"
        }
    }

    var iconName: String {
        switch self {
        case .positive: return "arrow.up.right"
        case .negative: return "arrow.down.right"
        case .neutral: return "minus"
        }
    }
}

enum DriverTheme: String, Codable, CaseIterable {
    case regulatoryRisk = "regulatory_risk"
    case earningsRisk = "earnings_risk"
    case guidanceRisk = "guidance_risk"
    case marginRisk = "margin_risk"
    case competitionRisk = "competition_risk"
    case demandRisk = "demand_risk"
    case macroRisk = "macro_risk"
    case leverageRisk = "leverage_risk"
    case liquidityRisk = "liquidity_risk"
    case volatilityRisk = "volatility_risk"
    case technicalRisk = "technical_risk"
    case executionRisk = "execution_risk"
    case concentrationRisk = "concentration_risk"
    case productRisk = "product_risk"
    case valuationRisk = "valuation_risk"

    var displayName: String {
        switch self {
        case .regulatoryRisk: return "Regulatory"
        case .earningsRisk: return "Earnings"
        case .guidanceRisk: return "Guidance"
        case .marginRisk: return "Margin"
        case .competitionRisk: return "Competition"
        case .demandRisk: return "Demand"
        case .macroRisk: return "Macro"
        case .leverageRisk: return "Leverage"
        case .liquidityRisk: return "Liquidity"
        case .volatilityRisk: return "Volatility"
        case .technicalRisk: return "Technical"
        case .executionRisk: return "Execution"
        case .concentrationRisk: return "Concentration"
        case .productRisk: return "Product"
        case .valuationRisk: return "Valuation"
        }
    }
}

enum SupportingEvidenceKind: String, Codable, CaseIterable {
    case eventAnalysis = "event_analysis"
    case newsItem = "news_item"
    case alert

    var displayName: String {
        switch self {
        case .eventAnalysis: return "Event"
        case .newsItem: return "News"
        case .alert: return "Alert"
        }
    }
}

struct SupportingEvidenceItem: Identifiable, Codable, Hashable {
    let id: String
    let kind: SupportingEvidenceKind
    let title: String
    let summary: String
    let source: String
    let url: String?
    let publishedAt: Date?
    let confidence: Double?
    let eventId: String?
    let newsId: String?
    let alertId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case summary
        case source
        case url
        case publishedAt = "published_at"
        case confidence
        case eventId = "event_id"
        case newsId = "news_id"
        case alertId = "alert_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind = try container.decodeIfPresent(SupportingEvidenceKind.self, forKey: .kind) ?? .newsItem
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        confidence = try container.decodeFlexibleDoubleIfPresent(forKey: .confidence)
        eventId = try container.decodeIfPresent(String.self, forKey: .eventId)
        newsId = try container.decodeIfPresent(String.self, forKey: .newsId)
        alertId = try container.decodeIfPresent(String.self, forKey: .alertId)
    }
}

struct DriverCard: Identifiable, Codable, Hashable {
    let id: String
    let rank: Int
    let title: String
    let summary: String
    let strength: DriverStrength
    let direction: DriverDirection
    let theme: DriverTheme
    let sourceChips: [String]
    let supportingEventIds: [String]
    let supportingNewsIds: [String]
    let supportingEvidence: [SupportingEvidenceItem]

    enum CodingKeys: String, CodingKey {
        case id
        case rank
        case title
        case summary
        case strength
        case direction
        case theme
        case sourceChips = "source_chips"
        case supportingEventIds = "supporting_event_ids"
        case supportingNewsIds = "supporting_news_ids"
        case supportingEvidence = "supporting_evidence"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        rank = try container.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        strength = try container.decodeIfPresent(DriverStrength.self, forKey: .strength) ?? .limited
        direction = try container.decodeIfPresent(DriverDirection.self, forKey: .direction) ?? .neutral
        theme = try container.decodeIfPresent(DriverTheme.self, forKey: .theme) ?? .macroRisk
        sourceChips = (try? container.decode([String].self, forKey: .sourceChips)) ?? []
        supportingEventIds = (try? container.decode([String].self, forKey: .supportingEventIds)) ?? []
        supportingNewsIds = (try? container.decode([String].self, forKey: .supportingNewsIds)) ?? []
        supportingEvidence = (try? container.decode([SupportingEvidenceItem].self, forKey: .supportingEvidence)) ?? []
    }
}
