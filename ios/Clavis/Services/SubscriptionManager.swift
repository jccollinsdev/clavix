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
    private let cachedIsProKey = "clavix.subscription.cachedIsPro"

    private init() {
        // Restore last known Pro state immediately so the UI doesn't flash the
        // paywall on launch if the entitlement check is slow or offline.
        isPro = UserDefaults.standard.bool(forKey: cachedIsProKey)
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
            guard
                let userID = await SupabaseAuthService.shared.getUserId(),
                let appAccountToken = UUID(uuidString: userID)
            else {
                purchaseError = "Please sign in again before starting your subscription."
                isLoading = false
                return
            }
            await APIService.shared.recordAnalyticsEvent(
                name: AnalyticsEventName.purchaseTapped,
                properties: ["product_id": product.id]
            )
            let result = try await product.purchase(
                options: [.appAccountToken(appAccountToken)]
            )
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateStatus(for: transaction)
                if await syncTierToBackend(
                    signedTransaction: verification.jwsRepresentation
                ) {
                    await transaction.finish()
                    await APIService.shared.recordAnalyticsEvent(
                        name: AnalyticsEventName.purchaseSuccess,
                        properties: ["product_id": transaction.productID]
                    )
                } else {
                    purchaseError = "Your trial started, but account access is still syncing. Reopen the app in a moment."
                }
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
            await syncCurrentStoreKitEntitlementToBackend()
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
                _ = await syncTierToBackend(
                    signedTransaction: result.jwsRepresentation
                )
                return
            }
        }
        // Server fallback covers an admin override or a recently verified
        // StoreKit entitlement while the App Store is temporarily unavailable.
        let (serverTier, subscriptionExpiresAt) = await fetchServerPrefs()
        switch serverTier {
        case "pro", "admin":
            status = .active(expiresAt: subscriptionExpiresAt ?? .distantFuture)
            isPro = true
        case "trial":
            let expiry = subscriptionExpiresAt ?? Date()
            status = .trial(expiresAt: expiry)
            isPro = true
            trackTrialStartedIfNeeded(expiresAt: expiry)
        case "unknown":
            status = .unknown
            // Do not overwrite isPro here — keep cached value until we get a definitive answer
            return
        default:
            status = .notSubscribed
            isPro = false
        }
        persistIsProCache()
    }

    private func updateStatus(for transaction: Transaction) async {
        guard ClavixProduct.all.contains(transaction.productID) else { return }
        switch transaction.productType {
        case .autoRenewable:
            if let expirationDate = transaction.expirationDate {
                if expirationDate > Date() {
                    if transaction.offerType == .introductory {
                        status = .trial(expiresAt: expirationDate)
                        trackTrialStartedIfNeeded(expiresAt: expirationDate)
                    } else {
                        status = .active(expiresAt: expirationDate)
                    }
                    isPro = true
                } else {
                    status = .expired
                    isPro = false
                }
                persistIsProCache()
            }
        default:
            break
        }
    }

    private func persistIsProCache() {
        UserDefaults.standard.set(isPro, forKey: cachedIsProKey)
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? self.checkVerified(result) else { continue }
                await self.updateStatus(for: transaction)
                if await self.syncTierToBackend(
                    signedTransaction: result.jwsRepresentation
                ) {
                    await transaction.finish()
                }
            }
        }
    }

    private func syncCurrentStoreKitEntitlementToBackend() async {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard ClavixProduct.all.contains(transaction.productID) else { continue }
            _ = await syncTierToBackend(
                signedTransaction: result.jwsRepresentation
            )
            return
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

    private func fetchServerPrefs() async -> (tier: String, expiresAt: Date?) {
        guard let prefs = try? await APIService.shared.fetchPreferences() else {
            return ("unknown", nil)
        }
        let tier = (prefs.effectiveTier ?? prefs.subscriptionTier ?? "free").lowercased()
        var expiresAt: Date? = nil
        if let raw = prefs.subscriptionExpiresAt {
            expiresAt = FlexibleDateDecoder.decode(raw)
        }
        return (tier, expiresAt)
    }

    private func trackTrialStartedIfNeeded(expiresAt: Date) {
        guard !UserDefaults.standard.bool(forKey: trialStartedTrackedKey) else { return }
        UserDefaults.standard.set(true, forKey: trialStartedTrackedKey)
        AnalyticsService.track(
            AnalyticsEventName.trialStarted,
            properties: ["expires_at": ISO8601DateFormatter().string(from: expiresAt)]
        )
    }

    private func syncTierToBackend(signedTransaction: String) async -> Bool {
        do {
            try await APIService.shared.syncSubscription(
                signedTransaction: signedTransaction
            )
            return true
        } catch {
            return false
        }
    }
}
