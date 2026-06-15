import Foundation

enum AnalyticsEventName {
    static let trialStarted = "trial_started"
    static let paywallViewed = "paywall_viewed"
    static let purchaseTapped = "purchase_tapped"
    static let purchaseSuccess = "purchase_success"
    static let restoreTapped = "restore_tapped"
}

enum AnalyticsService {
    static func track(_ name: String, properties: [String: String] = [:]) {
        Task {
            await APIService.shared.recordAnalyticsEvent(name: name, properties: properties)
        }
    }
}
