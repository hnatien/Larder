import Foundation
import Testing
import LarderCore
@testable import LarderAssistant

struct ErrorMappingTests {
    @Test(arguments: [
        (ProxyError.http(status: 400, code: "invalid_request"), LarderError.invalidResponse),
        (.http(status: 401, code: "unauthorized"), .assistantUnavailable),
        (.http(status: 402, code: "plus_required"), .plusRequired),
        (.http(status: 403, code: "dev_attestation_disabled"), .assistantUnavailable),
        (.http(status: 404, code: "not_found"), .invalidResponse),
        (.http(status: 422, code: "declined", category: "cyber"), .declined(category: "cyber")),
        (.http(status: 422, code: "declined"), .declined(category: nil)),
        (.http(status: 422, code: "protected_constraint"), .invalidResponse),
        (.http(status: 429, code: "quota_exceeded"), .quotaExceeded),
        (.http(status: 429, code: "upstream_rate_limited"), .assistantUnavailable),
        (.http(status: 500, code: nil), .assistantUnavailable),
        (.http(status: 502, code: "truncated"), .assistantUnavailable),
        (.http(status: 502, code: "unparseable"), .assistantUnavailable),
        (.http(status: 503, code: "unavailable"), .assistantUnavailable),
        (.decoding, .invalidResponse),
        (.transport(URLError(.timedOut)), .assistantUnavailable),
        (.noSession, .assistantUnavailable),
    ])
    func proxyErrorMapsToLarderError(proxyError: ProxyError, expected: LarderError) {
        #expect(proxyError.toLarderError() == expected)
    }

    @Test func plusRequiredReachesTheCaller() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.adjustPath, .json(402, #"{"error":"plus_required"}"#))
        await #expect(throws: LarderError.plusRequired) {
            try await Fixtures.backend(stub).adjust(request: AdjustRequest(message: "less meat", maxCookMinutes: 30, dietPatterns: [], goal: .maintain))
        }
    }

    @Test func declinedCarriesTheRefusalCategory() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.recipePath, .json(422, #"{"error":"declined","category":"cyber"}"#))
        await #expect(throws: LarderError.declined(category: "cyber")) {
            try await Fixtures.backend(stub).parseRecipe(text: "Toast", imageData: nil)
        }
    }

    @Test func declinedWithNullCategoryMapsToNil() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.recipePath, .json(422, #"{"error":"declined","category":null}"#))
        await #expect(throws: LarderError.declined(category: nil)) {
            try await Fixtures.backend(stub).parseRecipe(text: "Toast", imageData: nil)
        }
    }

    @Test func quotaExceededReachesTheCaller() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.explainPath, .json(429, #"{"error":"quota_exceeded","resetsAt":"2026-10-17T00:00:00.000Z"}"#))
        await #expect(throws: LarderError.quotaExceeded) {
            try await Fixtures.backend(stub).explain(plan: Fixtures.plan)
        }
    }

    @Test func serverErrorsMapToAssistantUnavailable() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.explainPath, .json(502, #"{"error":"truncated"}"#))
        await #expect(throws: LarderError.assistantUnavailable) {
            try await Fixtures.backend(stub).explain(plan: Fixtures.plan)
        }
    }

    @Test func validationErrorMapsToInvalidResponse() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.explainPath, .json(400, #"{"error":"invalid_request","issues":[]}"#))
        await #expect(throws: LarderError.invalidResponse) {
            try await Fixtures.backend(stub).explain(plan: Fixtures.plan)
        }
    }

    @Test func undecodableSuccessBodyMapsToInvalidResponse() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.pantryPath, .json(200, #"{"lines":"nope"}"#))
        await #expect(throws: LarderError.invalidResponse) {
            try await Fixtures.backend(stub).parsePantry(text: "2 onions")
        }
    }

    @Test func nonJSONErrorBodyKeepsTheStatus() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, .json(500, "<html>oops</html>"))
        await #expect(throws: ProxyError.http(status: 500, code: nil)) { try await Fixtures.client(stub).session() }
    }
}
