import Foundation
import Synchronization
import Testing
import LarderCore
@testable import LarderAssistant

/// A scripted App Attest device: records every call and fails where told to.
final class FakeAttester: AppAttester {
    struct Calls {
        var generated: [String] = []
        var attested: [(keyID: String, hash: Data)] = []
        var asserted: [(keyID: String, hash: Data)] = []
    }

    let isSupported: Bool
    private let state: Mutex<(calls: Calls, assertionError: AppAttestError?, attestError: AppAttestError?, next: Int)>

    init(isSupported: Bool = true, assertionError: AppAttestError? = nil, attestError: AppAttestError? = nil) {
        self.isSupported = isSupported
        state = Mutex((Calls(), assertionError, attestError, 1))
    }

    var calls: Calls { state.withLock { $0.calls } }

    func generateKey() async throws(AppAttestError) -> String {
        state.withLock { state in
            let id = "key-\(state.next)"
            state.next += 1
            state.calls.generated.append(id)
            return id
        }
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws(AppAttestError) -> Data {
        let error = state.withLock { state in
            state.calls.attested.append((keyID, clientDataHash))
            return state.attestError
        }
        if let error { throw error }
        return Data("attestation-\(keyID)".utf8)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws(AppAttestError) -> Data {
        let error = state.withLock { state in
            state.calls.asserted.append((keyID, clientDataHash))
            return state.assertionError
        }
        if let error { throw error }
        return Data("assertion-\(keyID)".utf8)
    }
}

final class MemoryKeyStore: AttestedKeyStore {
    private let value: Mutex<String?>

    init(_ keyID: String? = nil) {
        value = Mutex(keyID)
    }

    func load() -> String? { value.withLock { $0 } }

    func save(_ keyID: String?) { value.withLock { $0 = keyID } }
}

struct AppAttestSessionTests {
    private func client(_ stub: Stub, attester: FakeAttester, store: MemoryKeyStore, secret: String? = nil) -> ProxyClient {
        Fixtures.client(stub, secret: secret, appAttest: AppAttestConfiguration(attester: attester, keyStore: store))
    }

    private func attestation(_ request: RecordedRequest) throws -> [String: Any] {
        try #require(try request.json()["attestation"] as? [String: Any])
    }

    @Test func clientDataHashIsSHA256OfTheChallengeText() {
        let hash = ProxyClient.clientDataHash("abc")
        #expect(hash.map { String(format: "%02x", $0) }.joined() == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func firstSessionAttestsANewKeyAndSavesItOnlyAfterTheProxyAccepts() async throws {
        let stub = Stub()
        stub.on(Fixtures.challengePath, Fixtures.challengeReply("ch-1"))
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        let attester = FakeAttester()
        let store = MemoryKeyStore()

        #expect(try await client(stub, attester: attester, store: store, secret: "dev-secret").session() == "token-1")

        #expect(attester.calls.generated == ["key-1"])
        #expect(attester.calls.attested.map(\.keyID) == ["key-1"])
        #expect(attester.calls.attested.first?.hash == ProxyClient.clientDataHash("ch-1"))
        #expect(attester.calls.asserted.isEmpty)
        let body = try attestation(try #require(stub.requests(to: Fixtures.sessionPath).first))
        #expect(body["kind"] as? String == "appAttest")
        #expect(body["keyId"] as? String == "key-1")
        #expect(body["challenge"] as? String == "ch-1")
        #expect(body["attestationObject"] as? String == Data("attestation-key-1".utf8).base64EncodedString())
        #expect(body["clientSecret"] == nil)
        #expect(body["assertion"] == nil)
        #expect(store.load() == "key-1")
    }

    @Test func laterSessionsAssertWithTheStoredKey() async throws {
        let stub = Stub()
        stub.on(Fixtures.challengePath, Fixtures.challengeReply("ch-2"))
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        let attester = FakeAttester()
        let store = MemoryKeyStore("key-7")

        #expect(try await client(stub, attester: attester, store: store).session() == "token-1")

        #expect(attester.calls.generated.isEmpty)
        #expect(attester.calls.asserted.map(\.keyID) == ["key-7"])
        #expect(attester.calls.asserted.first?.hash == ProxyClient.clientDataHash("ch-2"))
        let body = try attestation(try #require(stub.requests(to: Fixtures.sessionPath).first))
        #expect(body["kind"] as? String == "appAssert")
        #expect(body["keyId"] as? String == "key-7")
        #expect(body["assertion"] as? String == Data("assertion-key-7".utf8).base64EncodedString())
        #expect(body["challenge"] as? String == "ch-2")
        #expect(store.load() == "key-7")
    }

    @Test func unknownKeyAtTheProxyLeadsToAFreshAttestation() async throws {
        let stub = Stub()
        stub.on(Fixtures.challengePath, Fixtures.challengeReply("ch-a"), Fixtures.challengeReply("ch-b"))
        stub.on(Fixtures.sessionPath, .json(401, #"{"error":"unknown_key"}"#), Fixtures.sessionReply())
        let attester = FakeAttester()
        let store = MemoryKeyStore("stale")

        #expect(try await client(stub, attester: attester, store: store).session() == "token-1")

        #expect(attester.calls.asserted.map(\.keyID) == ["stale"])
        #expect(attester.calls.attested.map(\.keyID) == ["key-1"])
        #expect(attester.calls.attested.first?.hash == ProxyClient.clientDataHash("ch-b"))
        let kinds = try stub.requests(to: Fixtures.sessionPath).map { try attestation($0)["kind"] as? String }
        #expect(kinds == ["appAssert", "appAttest"])
        #expect(store.load() == "key-1")
    }

    @Test func invalidKeyOnTheDeviceLeadsToAFreshAttestation() async throws {
        let stub = Stub()
        stub.on(Fixtures.challengePath, Fixtures.challengeReply())
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        let attester = FakeAttester(assertionError: .invalidKey)
        let store = MemoryKeyStore("reinstalled")

        #expect(try await client(stub, attester: attester, store: store).session() == "token-1")

        #expect(attester.calls.generated == ["key-1"])
        #expect(try stub.requests(to: Fixtures.sessionPath).map { try attestation($0)["kind"] as? String } == ["appAttest"])
        #expect(store.load() == "key-1")
    }

    @Test func unavailableAttestationServiceKeepsTheKeyAndReportsUnavailable() async {
        let stub = Stub()
        stub.on(Fixtures.challengePath, Fixtures.challengeReply())
        let attester = FakeAttester(assertionError: .unavailable)
        let store = MemoryKeyStore("key-3")

        await #expect(throws: ProxyError.attestation(.unavailable)) {
            try await client(stub, attester: attester, store: store).session()
        }
        #expect(store.load() == "key-3")
        #expect(stub.requests(to: Fixtures.sessionPath).isEmpty)
        #expect(ProxyError.attestation(.unavailable).toLarderError() == .assistantUnavailable)
    }

    @Test func rejectedAttestationIsNotSavedAndSurfaces() async {
        let stub = Stub()
        stub.on(Fixtures.challengePath, Fixtures.challengeReply())
        stub.on(Fixtures.sessionPath, .json(401, #"{"error":"attestation_rejected"}"#))
        let store = MemoryKeyStore()

        await #expect(throws: ProxyError.http(status: 401, code: "attestation_rejected")) {
            try await client(stub, attester: FakeAttester(), store: store).session()
        }
        #expect(store.load() == nil)
    }

    @Test func aSecondRejectionAfterReattestingIsNotRetriedAgain() async {
        let stub = Stub()
        stub.on(Fixtures.challengePath, Fixtures.challengeReply())
        stub.on(Fixtures.sessionPath, .json(401, #"{"error":"unknown_key"}"#))
        let attester = FakeAttester()

        await #expect(throws: ProxyError.http(status: 401, code: "unknown_key")) {
            try await client(stub, attester: attester, store: MemoryKeyStore("stale")).session()
        }
        #expect(stub.requests(to: Fixtures.sessionPath).count == 2)
        #expect(attester.calls.generated.count == 1)
    }

    @Test func challengeFailureSurfacesWithoutTouchingTheDevice() async {
        let stub = Stub()
        stub.on(Fixtures.challengePath, .json(503, #"{"error":"unavailable"}"#))
        let attester = FakeAttester()

        await #expect(throws: ProxyError.http(status: 503, code: "unavailable")) {
            try await client(stub, attester: attester, store: MemoryKeyStore()).session()
        }
        #expect(attester.calls.generated.isEmpty)
        #expect(attester.calls.attested.isEmpty)
    }

    @Test func unsupportedDeviceFallsBackToTheDevelopmentSecret() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        let attester = FakeAttester(isSupported: false)

        #expect(try await client(stub, attester: attester, store: MemoryKeyStore(), secret: "dev-secret").session() == "token-1")
        #expect(stub.requests(to: Fixtures.challengePath).isEmpty)
        let body = try attestation(try #require(stub.requests(to: Fixtures.sessionPath).first))
        #expect(body["kind"] as? String == "dev")
        #expect(body["clientSecret"] as? String == "dev-secret")
    }

    @Test func unsupportedDeviceWithoutASecretHasNoSession() async {
        let stub = Stub()
        await #expect(throws: ProxyError.noSession) {
            try await client(stub, attester: FakeAttester(isSupported: false), store: MemoryKeyStore()).session()
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func userDefaultsStoreRoundTripsAndClears() throws {
        let suite = "larder.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = UserDefaultsAttestedKeyStore(suiteName: suite)
        #expect(store.load() == nil)
        store.save("key-9")
        #expect(UserDefaultsAttestedKeyStore(suiteName: suite).load() == "key-9")
        store.save(nil)
        #expect(store.load() == nil)
    }
}
