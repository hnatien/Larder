import Foundation
import StoreKit

/// `StoreFront` over StoreKit 2. Unverified transactions are passed on flagged and never finished.
public nonisolated struct LiveStoreFront: StoreFront {
    /// Creates the live store front.
    public init() {}

    public func products(for ids: [String]) async throws -> [StoreProduct] {
        try await Product.products(for: ids).map(StoreProduct.init)
    }

    public func purchase(_ product: StoreProduct) async throws -> PurchaseOutcome {
        guard let storeKitProduct = try await Product.products(for: [product.id]).first else {
            throw StoreFrontError.productNotFound
        }
        return try await Self.outcome(for: try await storeKitProduct.purchase())
    }

    /// Maps a StoreKit purchase result, finishing a verified transaction; also used for the system subscription view.
    static func outcome(for result: Product.PurchaseResult) async throws -> PurchaseOutcome {
        switch result {
        case .success(let verification):
            .success(await record(finishing: verification))
        case .pending:
            .pending
        case .userCancelled:
            .userCancelled
        @unknown default:
            throw StoreFrontError.unknownPurchaseResult
        }
    }

    public func currentEntitlements() async -> [EntitlementRecord] {
        var records: [EntitlementRecord] = []
        for await verification in Transaction.currentEntitlements {
            records.append(EntitlementRecord(verification))
        }
        return records
    }

    public var updates: AsyncStream<EntitlementRecord> {
        AsyncStream { continuation in
            let task = Task {
                for await verification in Transaction.updates {
                    continuation.yield(await Self.record(finishing: verification))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func restore() async throws {
        try await AppStore.sync()
    }

    /// Finishes a verified transaction once its record exists; an unverified one stays unfinished.
    static func record(finishing verification: VerificationResult<Transaction>) async -> EntitlementRecord {
        let record = EntitlementRecord(verification)
        if case .verified(let transaction) = verification {
            await transaction.finish()
        }
        return record
    }
}

extension EntitlementRecord {
    nonisolated init(_ verification: VerificationResult<Transaction>) {
        let transaction = verification.unsafePayloadValue
        let isVerified = if case .verified = verification { true } else { false }
        self.init(
            productID: transaction.productID,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded,
            isVerified: isVerified,
            signedJWS: verification.jwsRepresentation
        )
    }
}

extension StoreProduct {
    nonisolated init(_ product: Product) {
        let introductoryOffer = product.subscription?.introductoryOffer
        self.init(
            id: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice,
            price: product.price,
            period: product.subscription.flatMap { BillingPeriod($0.subscriptionPeriod) },
            freeTrial: introductoryOffer.flatMap { $0.paymentMode == .freeTrial ? BillingPeriod($0.period) : nil }
        )
    }
}

extension BillingPeriod {
    nonisolated init?(_ period: Product.SubscriptionPeriod) {
        let unit: Unit
        switch period.unit {
        case .day: unit = .day
        case .week: unit = .week
        case .month: unit = .month
        case .year: unit = .year
        @unknown default: return nil
        }
        self.init(value: period.value, unit: unit)
    }
}
