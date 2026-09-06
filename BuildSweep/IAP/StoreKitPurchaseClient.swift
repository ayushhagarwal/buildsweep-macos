import Foundation
import StoreKit

enum BuildSweepProducts {
    static let lifetimeProductID = "com.ayush.buildsweep.pro.lifetime"
    /// Numeric Mac App Store ID. Replace after App Store Connect creates the Mac app record.
    static let appStoreID = ""

    static var writeReviewURL: URL? {
        guard !appStoreID.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
}

enum PurchaseClientError: LocalizedError {
    case unavailable
    case unverified
    case failed

    var errorDescription: String? {
        switch self {
        case .unavailable: "BuildSweep Pro is temporarily unavailable from the App Store."
        case .unverified: "The App Store transaction could not be verified."
        case .failed: "The purchase could not be completed."
        }
    }
}

enum PurchaseStateEvent: Equatable {
    case verifiedPurchase
    case verifiedEntitlement
    case revoked
    case pending
    case cancelled
    case unverified
    case unavailable
    case restoreWithoutEntitlement
}

struct PurchaseStateReducer {
    struct State: Equatable {
        var entitlement: ProEntitlementState = .unknown
        var message: String?
        var isPending = false
    }

    static func reduce(_ state: State, event: PurchaseStateEvent) -> State {
        var next = state
        next.isPending = false
        switch event {
        case .verifiedPurchase, .verifiedEntitlement:
            next.entitlement = .pro
            next.message = nil
        case .revoked:
            next.entitlement = .revoked
            next.message = "The lifetime entitlement was revoked or refunded."
        case .pending:
            next.isPending = true
            next.message = "The purchase is pending approval."
        case .cancelled:
            next.message = nil
        case .unverified:
            next.message = PurchaseClientError.unverified.localizedDescription
        case .unavailable:
            next.message = PurchaseClientError.unavailable.localizedDescription
        case .restoreWithoutEntitlement:
            next.entitlement = .free
            next.message = "No active BuildSweep Pro purchase was found."
        }
        return next
    }
}

actor StoreKitPurchaseClient: PurchaseClient {
    private let defaults: UserDefaults
    private let cacheKey = "verifiedProEntitlement.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadLifetimeProduct() async throws -> PurchaseProduct {
        let products = try await Product.products(for: [BuildSweepProducts.lifetimeProductID])
        guard let product = products.first else { throw PurchaseClientError.unavailable }
        return PurchaseProduct(displayName: product.displayName, description: product.description, displayPrice: product.displayPrice)
    }

    func purchaseLifetime() async throws -> PurchaseOutcome {
        let products = try await Product.products(for: [BuildSweepProducts.lifetimeProductID])
        guard let product = products.first else { throw PurchaseClientError.unavailable }
        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try verified(verification)
            guard transaction.productID == BuildSweepProducts.lifetimeProductID else { throw PurchaseClientError.unverified }
            defaults.set(true, forKey: cacheKey)
            await transaction.finish()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            throw PurchaseClientError.failed
        }
    }

    func restore() async throws {
        try await AppStore.sync()
        _ = await currentEntitlement()
    }

    func currentEntitlement() async -> ProEntitlementState {
        var foundVerified = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == BuildSweepProducts.lifetimeProductID else { continue }
            if transaction.revocationDate != nil {
                defaults.set(false, forKey: cacheKey)
                return .revoked
            }
            foundVerified = true
        }
        if foundVerified {
            defaults.set(true, forKey: cacheKey)
            return .pro
        }
        if let latest = await Transaction.latest(for: BuildSweepProducts.lifetimeProductID) {
            switch latest {
            case .verified(let transaction):
                if transaction.revocationDate != nil {
                    defaults.set(false, forKey: cacheKey)
                    return .revoked
                }
                defaults.set(true, forKey: cacheKey)
                return .pro
            case .unverified:
                break
            }
        }
        return defaults.bool(forKey: cacheKey) ? .pro : .free
    }

    func observeTransactionUpdates(
        onChange: @escaping @Sendable (ProEntitlementState) async -> Void = { _ in }
    ) async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == BuildSweepProducts.lifetimeProductID else { continue }
            let state: ProEntitlementState = transaction.revocationDate == nil ? .pro : .revoked
            defaults.set(state == .pro, forKey: cacheKey)
            await transaction.finish()
            await onChange(state)
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): value
        case .unverified: throw PurchaseClientError.unverified
        }
    }
}
