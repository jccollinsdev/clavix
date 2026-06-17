import Foundation
import StoreKit

// MARK: - Product IDs
// These must match exactly what is created in App Store Connect →
// In-App Purchases → Subscription Group "Clavix Pro".
enum ClavixProduct {
    static let proMonthly = "clavix_pro_monthly"
    static let all: [String] = [proMonthly]
}

// MARK: - Subscription state
enum SubscriptionStatus: Equatable {
    case unknown
    case notSubscribed
    case trial(expiresAt: Date)
    case active(expiresAt: Date)
    case expired
}

// MARK: - SubscriptionManager
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published var status: SubscriptionStatus = .unknown
    @Published var isPro: Bool = false
    @Published var isLoading: Bool = false
    @Published var purchaseError: String?

    private var products: [Product] = []
    private var transactionListenerTask: Task<Void, Never>?
    private let trialStartedTrackedKey = "clavix.analytics.trialStartedTracked"

    private init() {
        transactionListenerTask = listenForTransactions()
        Task { await refresh() }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Public API

    var proProduct: Product? {
        products.first { $0.id == ClavixProduct.proMonthly }
    }

    var proDisplayPrice: String {
        proProduct?.displayPrice ?? "$19.99"
    }

    func purchase() async {
        guard let product = proProduct else {
            purchaseError = "Subscription product not available right now. Please try again."
            return
        }
        isLoading = true
        purchaseError = nil
        do {
            await APIService.shared.recordAnalyticsEvent(
                name: AnalyticsEventName.purchaseTapped,
                properties: ["product_id": product.id]
            )
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateStatus(for: transaction)
                await transaction.finish()
                await APIService.shared.recordAnalyticsEvent(
                    name: AnalyticsEventName.purchaseSuccess,
                    properties: ["product_id": transaction.productID]
                )
                await syncTierToBackend(transactionID: String(transaction.id))
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval. Check back soon."
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed. Please try again."
        }
        isLoading = false
    }

    func restorePurchases() async {
        isLoading = true
        purchaseError = nil
        do {
            await APIService.shared.recordAnalyticsEvent(name: AnalyticsEventName.restoreTapped)
            try await AppStore.sync()
            await refresh()
        } catch {
            purchaseError = "Restore failed. Please try again."
        }
        isLoading = false
    }

    func refresh() async {
        await loadProducts()
        await checkCurrentEntitlement()
    }

    // MARK: - Private

    private func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            products = try await Product.products(for: ClavixProduct.all)
        } catch {
            // Product load failure is non-fatal — price display degrades gracefully
        }
    }

    private func checkCurrentEntitlement() async {
        // Walk current entitlements to determine active subscription
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if ClavixProduct.all.contains(transaction.productID) {
                await updateStatus(for: transaction)
                return
            }
        }
        // No active StoreKit entitlement — fall back to server-reported tier.
        // The backend resolves "trial" when trial_ends_at > now, so this
        // correctly grants Pro access during the 14-day window.
        let (serverTier, trialEndsAt) = await fetchServerPrefs()
        switch serverTier {
        case "pro", "admin":
            status = .active(expiresAt: .distantFuture)
            isPro = true
        case "trial":
            let expiry = trialEndsAt ?? Date().addingTimeInterval(14 * 86400)
            status = .trial(expiresAt: expiry)
            isPro = true
            trackTrialStartedIfNeeded(expiresAt: expiry)
        case "unknown":
            status = .unknown
            isPro = false
        default:
            status = .notSubscribed
            isPro = false
        }
    }

    private func updateStatus(for transaction: Transaction) async {
        guard ClavixProduct.all.contains(transaction.productID) else { return }
        switch transaction.productType {
        case .autoRenewable:
            if let expirationDate = transaction.expirationDate {
                if expirationDate > Date() {
                    status = .active(expiresAt: expirationDate)
                    isPro = true
                } else {
                    status = .expired
                    isPro = false
                }
            }
        default:
            break
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? self.checkVerified(result) else { continue }
                await self.updateStatus(for: transaction)
                await transaction.finish()
                await self.syncTierToBackend(transactionID: String(transaction.id))
            }
        }
    }

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    private func fetchServerPrefs() async -> (tier: String, trialEndsAt: Date?) {
        guard let prefs = try? await APIService.shared.fetchPreferences() else {
            return ("unknown", nil)
        }
        let tier = (prefs.effectiveTier ?? prefs.subscriptionTier ?? "free").lowercased()
        var trialEnds: Date? = nil
        if let raw = prefs.trialEndsAt {
            let iso = raw.replacingOccurrences(of: "Z", with: "+00:00")
            trialEnds = ISO8601DateFormatter().date(from: iso)
        }
        return (tier, trialEnds)
    }

    private func trackTrialStartedIfNeeded(expiresAt: Date) {
        guard !UserDefaults.standard.bool(forKey: trialStartedTrackedKey) else { return }
        UserDefaults.standard.set(true, forKey: trialStartedTrackedKey)
        AnalyticsService.track(
            AnalyticsEventName.trialStarted,
            properties: ["expires_at": ISO8601DateFormatter().string(from: expiresAt)]
        )
    }

    private func syncTierToBackend(transactionID: String) async {
        // Only sync on a verified StoreKit active purchase — not on server-granted trial.
        // The server manages the trial tier itself via trial_ends_at; syncing "pro" here
        // would collide with that and allow client-side tier escalation.
        guard case .active = status else { return }
        _ = try? await APIService.shared.updateSubscriptionTier("pro", transactionID: transactionID)
    }
}
