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
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateStatus(for: transaction)
                await transaction.finish()
                await syncTierToBackend()
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
        // No active entitlement found
        // Check if the server-side trial is still valid (14-day trial management
        // is handled by the backend until StoreKit trial kicks in).
        // For now fall back to server-reported tier.
        let serverTier = await fetchServerTier()
        if serverTier == "pro" || serverTier == "admin" {
            status = .active(expiresAt: .distantFuture)
            isPro = true
        } else {
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
                await self.syncTierToBackend()
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

    private func fetchServerTier() async -> String {
        guard let prefs = try? await APIService.shared.fetchPreferences() else {
            return "free"
        }
        return prefs.subscriptionTier?.lowercased() ?? "free"
    }

    private func syncTierToBackend() async {
        // After a successful purchase or restore, tell the backend about the new tier.
        // The backend uses this for digest verbosity and advanced alerts gating.
        // In production this should use the StoreKit receipt for server-side verification.
        let newTier: String
        switch status {
        case .trial, .active:
            newTier = "pro"
        default:
            newTier = "free"
        }
        _ = try? await APIService.shared.updateSubscriptionTier(newTier)
    }
}
