import Foundation

/// A failure from the device's App Attest service, reduced to what the client acts on.
public enum AppAttestError: Error, Hashable, Sendable {
    /// The key is gone or unusable (for example after a reinstall); generate and attest a new one.
    case invalidKey
    /// Apple's attestation service or the Secure Enclave could not answer; try again later.
    case unavailable
}

/// The device side of App Attest. `LiveAppAttester` wraps `DCAppAttestService`; tests use a fake.
public protocol AppAttester: Sendable {
    /// False on the Simulator and on devices without a Secure Enclave.
    var isSupported: Bool { get }
    /// Creates a Secure Enclave key and returns its key id (base64).
    func generateKey() async throws(AppAttestError) -> String
    /// Asks Apple to attest the key for `clientDataHash`; returns the CBOR attestation object.
    func attestKey(_ keyID: String, clientDataHash: Data) async throws(AppAttestError) -> Data
    /// Signs `clientDataHash` with the attested key; returns the CBOR assertion.
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws(AppAttestError) -> Data
}

/// Remembers the attested key id between launches. The id is public; the private key never leaves the Secure Enclave.
public protocol AttestedKeyStore: Sendable {
    func load() -> String?
    func save(_ keyID: String?)
}

/// App Attest for the proxy session: the device attester plus where its attested key id is kept.
public struct AppAttestConfiguration: Sendable {
    public var attester: any AppAttester
    public var keyStore: any AttestedKeyStore

    /// Creates an App Attest configuration.
    public init(attester: any AppAttester, keyStore: any AttestedKeyStore) {
        self.attester = attester
        self.keyStore = keyStore
    }
}

/// Keeps the attested key id in `UserDefaults`.
public struct UserDefaultsAttestedKeyStore: AttestedKeyStore {
    private let suiteName: String?
    private let key: String

    /// Uses the standard defaults unless `suiteName` names another suite.
    public init(suiteName: String? = nil, key: String = "larder.appAttest.keyID") {
        self.suiteName = suiteName
        self.key = key
    }

    public func load() -> String? {
        defaults.string(forKey: key)
    }

    public func save(_ keyID: String?) {
        defaults.set(keyID, forKey: key)
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}

#if canImport(DeviceCheck)
import DeviceCheck

/// `DCAppAttestService`, with its errors mapped to `AppAttestError`.
public struct LiveAppAttester: AppAttester {
    /// Creates the live attester.
    public init() {}

    public var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    public func generateKey() async throws(AppAttestError) -> String {
        do {
            return try await DCAppAttestService.shared.generateKey()
        } catch {
            throw Self.map(error)
        }
    }

    public func attestKey(_ keyID: String, clientDataHash: Data) async throws(AppAttestError) -> Data {
        do {
            return try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
        } catch {
            throw Self.map(error)
        }
    }

    public func generateAssertion(_ keyID: String, clientDataHash: Data) async throws(AppAttestError) -> Data {
        do {
            return try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
        } catch {
            throw Self.map(error)
        }
    }

    static func map(_ error: any Error) -> AppAttestError {
        guard let error = error as? DCError else { return .unavailable }
        switch error.code {
        case .invalidKey, .invalidInput: return .invalidKey
        default: return .unavailable
        }
    }
}
#endif
