import Foundation
import Testing
import LarderCore
@testable import LarderAssistant

struct ProxyClientTests {
    @Test func sessionPostsDevAttestationAndCachesToken() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        let client = Fixtures.client(stub)

        #expect(try await client.session() == "token-1")
        #expect(try await client.session() == "token-1")

        let requests = stub.requests(to: Fixtures.sessionPath)
        #expect(requests.count == 1)
        let body = try requests[0].json()
        let attestation = try #require(body["attestation"] as? [String: Any])
        #expect(attestation["kind"] as? String == "dev")
        #expect(attestation["clientSecret"] as? String == "dev-secret")
        #expect(requests[0].method == "POST")
        #expect(requests[0].headers["Authorization"] == nil)
    }

    @Test func sessionIsReusedUntilSixtySecondsBeforeExpiry() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply(token: "first"), Fixtures.sessionReply(token: "second", expiresAt: "2026-10-16T11:00:00Z"))
        let clock = TestClock()
        let client = Fixtures.client(stub, clock: clock)

        #expect(try await client.session() == "first")
        clock.advance(by: 3600 - 61)
        #expect(try await client.session() == "first")
        clock.advance(by: 2)
        #expect(try await client.session() == "second")
        #expect(stub.requests(to: Fixtures.sessionPath).count == 2)
    }

    @Test func sessionAcceptsTimestampsWithoutFractionalSeconds() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply(expiresAt: "2026-10-16T10:00:00Z"))
        let client = Fixtures.client(stub)
        #expect(try await client.session() == "token-1")
    }

    @Test func missingClientSecretThrowsNoSessionWithoutNetwork() async {
        let stub = Stub()
        let client = Fixtures.client(stub, secret: nil)
        await #expect(throws: ProxyError.noSession) { try await client.session() }
        #expect(stub.requests.isEmpty)
    }

    @Test func rejectedAttestationSurfacesHTTPError() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, .json(401, #"{"error":"attestation_rejected"}"#))
        let client = Fixtures.client(stub)
        await #expect(throws: ProxyError.http(status: 401, code: "attestation_rejected")) { try await client.session() }
    }

    @Test func malformedSessionResponseThrowsDecoding() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, .json(200, #"{"token":"t","expiresAt":"tomorrow"}"#))
        let client = Fixtures.client(stub)
        await #expect(throws: ProxyError.decoding) { try await client.session() }
    }

    @Test func failedSessionIsNotCached() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, .json(503, #"{"error":"unavailable"}"#), Fixtures.sessionReply())
        let client = Fixtures.client(stub)
        await #expect(throws: ProxyError.http(status: 503, code: "unavailable")) { try await client.session() }
        #expect(try await client.session() == "token-1")
    }

    @Test func concurrentCallersShareOneSessionRequest() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        let client = Fixtures.client(stub)
        async let first = client.session()
        async let second = client.session()
        async let third = client.session()
        let tokens = try await [first, second, third]
        #expect(tokens == ["token-1", "token-1", "token-1"])
        #expect(stub.requests(to: Fixtures.sessionPath).count == 1)
    }

    @Test func assistRetriesOnceOn401WithAFreshSession() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply(token: "stale"), Fixtures.sessionReply(token: "fresh"))
        stub.on(Fixtures.pantryPath, .json(401, #"{"error":"unauthorized"}"#), Fixtures.pantryReply)
        let lines = try await Fixtures.backend(stub).parsePantry(text: "2 onions")

        #expect(lines.count == 3)
        let assists = stub.requests(to: Fixtures.pantryPath)
        #expect(assists.map { $0.headers["Authorization"] } == ["Bearer stale", "Bearer fresh"])
        #expect(stub.requests(to: Fixtures.sessionPath).count == 2)
    }

    @Test func assistGivesUpAfterASecond401() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.pantryPath, .json(401, #"{"error":"unauthorized"}"#))
        await #expect(throws: LarderError.assistantUnavailable) {
            try await Fixtures.backend(stub).parsePantry(text: "2 onions")
        }
        #expect(stub.requests(to: Fixtures.pantryPath).count == 2)
    }

    @Test func assistSendsBearerEntitlementAndRouteTimeouts() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.pantryPath, Fixtures.pantryReply)
        stub.on(Fixtures.explainPath, Fixtures.explainReply)
        let backend = Fixtures.backend(stub, entitlement: "signed.jws.value")
        _ = try await backend.parsePantry(text: "2 onions")
        _ = try await backend.explain(plan: Fixtures.plan)

        let pantry = try #require(stub.requests(to: Fixtures.pantryPath).first)
        #expect(pantry.headers["Authorization"] == "Bearer token-1")
        #expect(pantry.headers["x-larder-entitlement"] == "signed.jws.value")
        #expect(pantry.headers["Content-Type"] == "application/json")
        #expect(pantry.timeout == 20)
        let explain = try #require(stub.requests(to: Fixtures.explainPath).first)
        #expect(explain.timeout == 45)
    }

    @Test func entitlementHeaderIsOmittedWithoutASubscription() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.pantryPath, Fixtures.pantryReply)
        _ = try await Fixtures.backend(stub).parsePantry(text: "2 onions")
        let pantry = try #require(stub.requests(to: Fixtures.pantryPath).first)
        #expect(pantry.headers["x-larder-entitlement"] == nil)
    }

    @Test func requestBodiesUseSortedKeys() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.explainPath, Fixtures.explainReply)
        _ = try await Fixtures.backend(stub).explain(plan: Fixtures.plan)
        let text = try #require(stub.requests(to: Fixtures.explainPath).first).bodyText
        let keys = ["\"plan\"", "\"profileSummary\"", "\"shelfBalance\""].compactMap { text.range(of: $0)?.lowerBound }
        #expect(keys.count == 3)
        #expect(keys == keys.sorted())
        #expect(text.contains(#"{"goal":"lessWaste","householdSize":3,"maxCookMinutes":30,"showsNumbers":false}"#))
    }

    @Test func transportFailureMapsToAssistantUnavailable() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, .failure(URLError(.notConnectedToInternet)))
        let client = Fixtures.client(stub)
        let error = await #expect(throws: ProxyError.self) { try await client.session() }
        guard case .transport(let urlError) = error else {
            Issue.record("Expected a transport error, got \(String(describing: error))")
            return
        }
        #expect(urlError.code == .notConnectedToInternet)
        await #expect(throws: LarderError.assistantUnavailable) {
            try await Fixtures.backend(stub).parsePantry(text: "2 onions")
        }
    }
}
