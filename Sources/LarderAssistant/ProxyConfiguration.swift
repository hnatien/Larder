import Foundation

/// Where the Larder proxy lives and how this client proves who it is.
public struct ProxyConfiguration: Sendable {
    public var baseURL: URL
    /// Returns the development attestation secret, or `nil` when none is configured.
    public var clientSecretProvider: @Sendable () async -> String?
    /// Returns the StoreKit signed transaction (JWS) for an active Plus subscription, or `nil`.
    public var entitlementProvider: @Sendable () async -> String?

    /// Creates a proxy configuration.
    public init(
        baseURL: URL,
        clientSecretProvider: @escaping @Sendable () async -> String?,
        entitlementProvider: @escaping @Sendable () async -> String?
    ) {
        self.baseURL = baseURL
        self.clientSecretProvider = clientSecretProvider
        self.entitlementProvider = entitlementProvider
    }
}
