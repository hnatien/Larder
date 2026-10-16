import Foundation
import LarderCore
import Observation

/// Which level of Larder the user has.
public nonisolated enum Tier: Hashable, Sendable {
    case free
    case plus
}

/// Why a store action failed.
public nonisolated enum EntitlementError: Error, Hashable, Sendable {
    case productsUnavailable
    case purchaseFailed
    /// The App Store returned a transaction whose signature did not verify.
    case verificationFailed
    case restoreFailed
}

/// How a purchase started from the paywall ended.
public nonisolated enum PurchaseResult: Hashable, Sendable {
    case purchased
    case pending
    case cancelled
    case failed
}

/// The user's Plus status from StoreKit, kept current for the app's lifetime.
@Observable @MainActor
public final class EntitlementStore {
    /// The Plus product identifiers, monthly first.
    public nonisolated static let plusProductIDs = ["com.larder.plus.monthly", "com.larder.plus.annual"]
    /// The "Larder Plus" subscription group in `Larder.storekit` and App Store Connect.
    public nonisolated static let subscriptionGroupID = "21580001"

    public private(set) var tier: Tier = .free
    public private(set) var products: [StoreProduct] = []
    public private(set) var isLoading = false
    public private(set) var error: EntitlementError?
    /// The record that grants Plus, if any.
    public private(set) var activeRecord: EntitlementRecord?
    /// True after a purchase that waits for approval, until a verified Plus record arrives.
    public private(set) var isAwaitingApproval = false

    private let storeFront: any StoreFront
    private let dates: any DateProvider
    private var records: [EntitlementRecord] = []
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    /// Creates a store over `storeFront`; `dates` decides whether a subscription has expired.
    public init(storeFront: any StoreFront, dates: any DateProvider) {
        self.storeFront = storeFront
        self.dates = dates
    }

    isolated deinit {
        updatesTask?.cancel()
    }

    /// Whether the user has Plus right now; safe to hand to other modules.
    public nonisolated var isPlus: @Sendable () async -> Bool {
        { [weak self] in
            await self?.currentTier() == .plus
        }
    }

    /// Starts listening for transaction updates, then loads products and current entitlements. Later calls do nothing.
    public func start() async {
        guard updatesTask == nil else { return }
        let updates = storeFront.updates
        updatesTask = Task { [weak self] in
            for await record in updates {
                self?.apply(record)
            }
        }
        isLoading = true
        defer { isLoading = false }
        await loadProducts()
        records = await storeFront.currentEntitlements()
        derive()
    }

    /// Loads the Plus products, in `plusProductIDs` order.
    public func loadProducts() async {
        do {
            let loaded = try await storeFront.products(for: Self.plusProductIDs)
            products = loaded.sorted { lhs, rhs in
                (Self.plusProductIDs.firstIndex(of: lhs.id) ?? .max) < (Self.plusProductIDs.firstIndex(of: rhs.id) ?? .max)
            }
            if error == .productsUnavailable { error = nil }
        } catch {
            self.error = .productsUnavailable
        }
    }

    /// Buys `product` and reports how it ended; failures also set `error`.
    @discardableResult
    public func purchase(_ product: StoreProduct) async -> PurchaseResult {
        isLoading = true
        defer { isLoading = false }
        let outcome: Result<PurchaseOutcome, any Error>
        do {
            outcome = .success(try await storeFront.purchase(product))
        } catch {
            outcome = .failure(error)
        }
        return complete(outcome)
    }

    /// Applies a purchase's outcome, including one made through the system subscription view.
    @discardableResult
    public func complete(_ outcome: Result<PurchaseOutcome, any Error>) -> PurchaseResult {
        switch outcome {
        case .failure:
            error = .purchaseFailed
            return .failed
        case .success(.success(let record)):
            guard record.isVerified else {
                error = .verificationFailed
                return .failed
            }
            error = nil
            apply(record)
            return .purchased
        case .success(.pending):
            isAwaitingApproval = true
            return .pending
        case .success(.userCancelled):
            return .cancelled
        }
    }

    /// Asks the App Store for the user's transactions again and re-reads entitlements.
    public func restore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await storeFront.restore()
            error = nil
        } catch {
            self.error = .restoreFailed
            return
        }
        await refresh()
    }

    /// Re-reads current entitlements, such as after a purchase made through the system subscription view.
    public func refresh() async {
        records = await storeFront.currentEntitlements()
        derive()
    }

    /// The signed transaction of the active Plus record, for the assistant's entitlement header.
    public func entitlementJWS() async -> String? {
        derive()
        return activeRecord?.signedJWS
    }

    private func currentTier() -> Tier {
        derive()
        return tier
    }

    private func apply(_ record: EntitlementRecord) {
        guard record.isVerified, Self.plusProductIDs.contains(record.productID) else { return }
        records.removeAll { $0.productID == record.productID }
        records.append(record)
        derive()
    }

    /// The active record is the verified Plus record that lasts longest; a record without an expiry outlasts all.
    private func derive() {
        let now = dates.now
        let active = records
            .filter { Self.plusProductIDs.contains($0.productID) && $0.isActive(at: now) }
            .max { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
        if activeRecord != active { activeRecord = active }
        let newTier: Tier = active == nil ? .free : .plus
        if tier != newTier { tier = newTier }
        if active != nil, isAwaitingApproval { isAwaitingApproval = false }
    }
}
