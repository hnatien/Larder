import Foundation
import Synchronization
import Testing
import LarderCore
@testable import LarderAssistant

/// An on-device backend double that records which routes it served; with `failure` the parse routes throw it.
final class FakeOnDevice: AssistantBackend, OnDeviceAvailability {
    let isAvailable: Bool
    let supportedRoutes: Set<AssistantRoute>
    private let failure: (any Error & Sendable)?
    private let served = Mutex<[AssistantRoute]>([])

    init(isAvailable: Bool, supportedRoutes: Set<AssistantRoute> = Set(AssistantRoute.allCases), failure: (any Error & Sendable)? = nil) {
        self.isAvailable = isAvailable
        self.supportedRoutes = supportedRoutes
        self.failure = failure
    }

    var calls: [AssistantRoute] { served.withLock { $0 } }

    func explain(plan: PlanExplainRequest) async throws -> PlanExplanation {
        served.withLock { $0.append(.explain) }
        return PlanExplanation(summary: "on device", mealNotes: [])
    }

    func parsePantry(text: String) async throws -> [ParsedPantryLine] {
        served.withLock { $0.append(.parsePantry) }
        if let failure { throw failure }
        return [ParsedPantryLine(rawText: text, name: "on device")]
    }

    func parseRecipe(text: String, imageData: Data?) async throws -> ParsedRecipe {
        served.withLock { $0.append(.parseRecipe) }
        if let failure { throw failure }
        return ParsedRecipe(title: "on device", ingredients: [], steps: [])
    }

    func adjust(request: AdjustRequest) async throws -> ConstraintEdit {
        served.withLock { $0.append(.adjust) }
        return ConstraintEdit(changes: [], summary: "on device")
    }
}

struct AssistantRouterTests {
    private static let adjustRequest = AdjustRequest(message: "quicker dinners", maxCookMinutes: 30, dietPatterns: [], goal: .maintain)

    private func router(_ stub: Stub, onDevice: FakeOnDevice? = nil, aiProcessing: Bool) -> AssistantRouter {
        AssistantRouter(
            onDevice: onDevice,
            proxy: Fixtures.backend(stub),
            consent: { Consents(aiProcessing: aiProcessing) }
        )
    }

    @Test func noURLSessionRequestIsMadeWhenAIProcessingIsOff() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, .failure(URLError(.cancelled)))
        let router = router(stub, onDevice: FakeOnDevice(isAvailable: false), aiProcessing: false)

        let lines = try await router.parsePantry(text: "2 onions, cook@example.com")
        #expect(lines.first == ParsedPantryLine(rawText: "2 onions", name: "onions", quantity: 2))
        await #expect(throws: LarderError.consentRequired) { try await router.explain(plan: Fixtures.plan) }
        await #expect(throws: LarderError.assistantUnavailable) { try await router.parseRecipe(text: "Dal", imageData: nil) }
        await #expect(throws: LarderError.assistantUnavailable) { try await router.adjust(request: Self.adjustRequest) }

        #expect(stub.requests.isEmpty, "The network was used without consent")
    }

    @Test func availableOnDeviceServesEveryRouteWithoutTheNetwork() async throws {
        let stub = Stub()
        let onDevice = FakeOnDevice(isAvailable: true)
        let router = router(stub, onDevice: onDevice, aiProcessing: true)

        #expect(try await router.parsePantry(text: "2 onions").first?.name == "on device")
        #expect(try await router.explain(plan: Fixtures.plan).summary == "on device")
        #expect(try await router.parseRecipe(text: "Dal", imageData: nil).title == "on device")
        #expect(try await router.adjust(request: Self.adjustRequest).summary == "on device")
        #expect(onDevice.calls == [.parsePantry, .explain, .parseRecipe, .adjust])
        #expect(stub.requests.isEmpty)
    }

    @Test func onDeviceIsUsedWithoutConsentBecauseNothingLeavesTheDevice() async throws {
        let stub = Stub()
        let onDevice = FakeOnDevice(isAvailable: true)
        let router = router(stub, onDevice: onDevice, aiProcessing: false)
        #expect(try await router.explain(plan: Fixtures.plan).summary == "on device")
        #expect(stub.requests.isEmpty)
    }

    @Test func unsupportedOnDeviceRouteGoesToTheProxyWithConsent() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.explainPath, Fixtures.explainReply)
        let onDevice = FakeOnDevice(isAvailable: true, supportedRoutes: [.parsePantry])
        let explanation = try await router(stub, onDevice: onDevice, aiProcessing: true).explain(plan: Fixtures.plan)

        #expect(explanation.summary == "Spinach gets used before Sunday.")
        #expect(onDevice.calls.isEmpty)
        #expect(stub.requests(to: Fixtures.explainPath).count == 1)
    }

    @Test func unsupportedOnDeviceRouteWithoutConsentFailsWithoutTheNetwork() async {
        let stub = Stub()
        let onDevice = FakeOnDevice(isAvailable: true, supportedRoutes: [.parsePantry])
        let router = router(stub, onDevice: onDevice, aiProcessing: false)
        await #expect(throws: LarderError.consentRequired) { try await router.explain(plan: Fixtures.plan) }
        await #expect(throws: LarderError.assistantUnavailable) { try await router.adjust(request: Self.adjustRequest) }
        #expect(stub.requests.isEmpty)
    }

    @Test func unavailableOnDeviceSendsPantryTextToTheProxyWithConsent() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.pantryPath, Fixtures.pantryReply)
        let onDevice = FakeOnDevice(isAvailable: false)
        let lines = try await router(stub, onDevice: onDevice, aiProcessing: true).parsePantry(text: "2 onions")
        #expect(lines.count == 3)
        #expect(onDevice.calls.isEmpty)
    }

    @Test func pantryFallsBackToTheDeterministicParserWhenTheProxyIsUnavailable() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.pantryPath, .json(503, #"{"error":"upstream_unavailable"}"#))
        let lines = try await router(stub, aiProcessing: true).parsePantry(text: "2 onions; a lemon")
        #expect(lines.map(\.name) == ["onions", "lemon"])
        #expect(stub.requests(to: Fixtures.pantryPath).count == 1)
    }

    @Test func pantryFallsBackWhenOffline() async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, .failure(URLError(.notConnectedToInternet)))
        let lines = try await router(stub, aiProcessing: true).parsePantry(text: "3 apples")
        #expect(lines == [ParsedPantryLine(rawText: "3 apples", name: "apples", quantity: 3)])
    }

    @Test func pantryDoesNotHideErrorsTheUserCanActOn() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.pantryPath, .json(429, #"{"error":"quota_exceeded","resetsAt":"2026-10-17T00:00:00.000Z"}"#))
        await #expect(throws: LarderError.quotaExceeded) {
            try await router(stub, aiProcessing: true).parsePantry(text: "2 onions")
        }
    }

    @Test func proxyFailuresOnOtherRoutesAreNotMasked() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.recipePath, .json(503, #"{"error":"upstream_unavailable"}"#))
        await #expect(throws: LarderError.assistantUnavailable) {
            try await router(stub, aiProcessing: true).parseRecipe(text: "Dal", imageData: nil)
        }
    }

    @Test(arguments: [LarderError.invalidResponse, .assistantUnavailable])
    func onDeviceLimitFallsThroughToTheProxyOnceWithConsent(error: LarderError) async throws {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.pantryPath, Fixtures.pantryReply)
        stub.on(Fixtures.recipePath, Fixtures.recipeReply)
        let onDevice = FakeOnDevice(isAvailable: true, failure: error)
        let router = router(stub, onDevice: onDevice, aiProcessing: true)

        let lines = try await router.parsePantry(text: "2 onions")
        _ = try await router.parseRecipe(text: "Dal", imageData: nil)

        #expect(lines.count == 3)
        #expect(onDevice.calls == [.parsePantry, .parseRecipe])
        #expect(stub.requests(to: Fixtures.pantryPath).count == 1)
        #expect(stub.requests(to: Fixtures.recipePath).count == 1)
    }

    @Test(arguments: [LarderError.invalidResponse, .assistantUnavailable])
    func onDeviceLimitWithoutConsentParsesPantryDeterministically(error: LarderError) async throws {
        let stub = Stub()
        let onDevice = FakeOnDevice(isAvailable: true, failure: error)

        let lines = try await router(stub, onDevice: onDevice, aiProcessing: false).parsePantry(text: "3 apples")

        #expect(lines == [ParsedPantryLine(rawText: "3 apples", name: "apples", quantity: 3)])
        #expect(onDevice.calls == [.parsePantry])
        #expect(stub.requests.isEmpty)
    }

    @Test(arguments: [LarderError.invalidResponse, .assistantUnavailable])
    func onDeviceLimitWithoutConsentLeavesRecipeUnavailable(error: LarderError) async {
        let stub = Stub()
        let onDevice = FakeOnDevice(isAvailable: true, failure: error)

        await #expect(throws: LarderError.assistantUnavailable) {
            try await router(stub, onDevice: onDevice, aiProcessing: false).parseRecipe(text: "Dal", imageData: nil)
        }
        #expect(onDevice.calls == [.parseRecipe])
        #expect(stub.requests.isEmpty)
    }

    @Test func declinedIsNeverRetriedOnTheProxy() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.pantryPath, Fixtures.pantryReply)
        stub.on(Fixtures.recipePath, Fixtures.recipeReply)
        let declined = LarderError.declined(category: "cyber")
        let onDevice = FakeOnDevice(isAvailable: true, failure: declined)
        let router = router(stub, onDevice: onDevice, aiProcessing: true)

        await #expect(throws: declined) { try await router.parsePantry(text: "2 onions") }
        await #expect(throws: declined) { try await router.parseRecipe(text: "Dal", imageData: nil) }

        #expect(onDevice.calls == [.parsePantry, .parseRecipe])
        #expect(stub.requests.isEmpty, "A decline was retried on the proxy")
    }

    @Test func cancellationIsNeverRetriedOnTheProxy() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.pantryPath, Fixtures.pantryReply)
        stub.on(Fixtures.recipePath, Fixtures.recipeReply)
        let router = router(stub, onDevice: FakeOnDevice(isAvailable: true, failure: CancellationError()), aiProcessing: true)

        await #expect(throws: CancellationError.self) { try await router.parsePantry(text: "2 onions") }
        await #expect(throws: CancellationError.self) { try await router.parseRecipe(text: "Dal", imageData: nil) }

        #expect(stub.requests.isEmpty)
    }

    @Test func otherOnDeviceErrorsAreNotRetriedOnTheProxy() async {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(Fixtures.pantryPath, Fixtures.pantryReply)
        let router = router(stub, onDevice: FakeOnDevice(isAvailable: true, failure: LarderError.quotaExceeded), aiProcessing: true)

        await #expect(throws: LarderError.quotaExceeded) { try await router.parsePantry(text: "2 onions") }

        #expect(stub.requests.isEmpty)
    }
}
