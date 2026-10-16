import Foundation

/// The App Store as Larder sees it; `LiveStoreFront` wraps StoreKit 2, tests script a fake.
public nonisolated protocol StoreFront: Sendable {
    /// The products with the given identifiers that the store knows about.
    func products(for ids: [String]) async throws -> [StoreProduct]
    /// Buys `product`.
    func purchase(_ product: StoreProduct) async throws -> PurchaseOutcome
    /// The transactions that currently entitle the user to something.
    func currentEntitlements() async -> [EntitlementRecord]
    /// Transactions that arrive while the app runs: renewals, refunds, purchases made elsewhere.
    var updates: AsyncStream<EntitlementRecord> { get }
    /// Asks the App Store to resend the user's transactions.
    func restore() async throws
}

/// A product as shown on the paywall.
public nonisolated struct StoreProduct: Identifiable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    /// The localised price, such as "$7.99".
    public var displayPrice: String
    public var price: Decimal
    /// How often the subscription renews; `nil` for a product that does not renew.
    public var period: BillingPeriod?
    /// The length of the free introductory offer, if the product has one.
    public var freeTrial: BillingPeriod?

    /// Creates a product.
    public init(
        id: String,
        displayName: String,
        displayPrice: String,
        price: Decimal,
        period: BillingPeriod?,
        freeTrial: BillingPeriod? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.price = price
        self.period = period
        self.freeTrial = freeTrial
    }
}

/// A span of calendar time, such as one month or seven days.
public nonisolated struct BillingPeriod: Hashable, Sendable {
    /// The calendar unit of a period.
    public enum Unit: Hashable, Sendable {
        case day, week, month, year
    }

    public var value: Int
    public var unit: Unit

    /// Creates a period of `value` units.
    public init(value: Int, unit: Unit) {
        self.value = value
        self.unit = unit
    }
}

/// What a purchase attempt ended with.
public nonisolated enum PurchaseOutcome: Hashable, Sendable {
    /// The App Store charged the user; the record may still fail verification.
    case success(EntitlementRecord)
    /// The purchase waits for approval, such as Ask to Buy.
    case pending
    case userCancelled
}

/// One transaction that may entitle the user to Plus.
public nonisolated struct EntitlementRecord: Hashable, Sendable {
    public var productID: String
    public var expirationDate: Date?
    public var revocationDate: Date?
    /// True when the user moved to a higher-level subscription and this one no longer applies.
    public var isUpgraded: Bool
    /// False when StoreKit could not verify the transaction's signature; such records never grant anything.
    public var isVerified: Bool
    /// The signed transaction (JWS) the proxy verifies server-side; `nil` for unverified records.
    public var signedJWS: String?

    /// Creates a record.
    public init(
        productID: String,
        expirationDate: Date?,
        revocationDate: Date? = nil,
        isUpgraded: Bool = false,
        isVerified: Bool,
        signedJWS: String?
    ) {
        self.productID = productID
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.isUpgraded = isUpgraded
        self.isVerified = isVerified
        self.signedJWS = isVerified ? signedJWS : nil
    }

    /// Whether this record grants access at `date`.
    func isActive(at date: Date) -> Bool {
        guard isVerified, revocationDate == nil, !isUpgraded else { return false }
        guard let expirationDate else { return true }
        return expirationDate > date
    }
}

/// Failures from `LiveStoreFront`.
public nonisolated enum StoreFrontError: Error, Hashable, Sendable {
    /// The App Store does not offer the product any more.
    case productNotFound
    /// StoreKit returned a purchase result this version does not know.
    case unknownPurchaseResult
}
