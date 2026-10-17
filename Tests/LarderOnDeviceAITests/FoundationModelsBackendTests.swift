import Foundation
import FoundationModels
import Testing
import LarderAssistant
import LarderCore
@testable import LarderOnDeviceAI

struct UnusedDateProvider: DateProvider {
    var now: Date { Date(timeIntervalSince1970: 0) }
}

struct FoundationModelsBackendTests {
    private static let liveModelIsAvailable = SystemLanguageModel.default.availability == .available

    private func backend(available: Bool) -> FoundationModelsBackend {
        FoundationModelsBackend(model: .default, dates: UnusedDateProvider(), modelIsAvailable: { available })
    }

    @Test func availabilityFollowsTheModel() {
        #expect(backend(available: true).isAvailable)
        #expect(!backend(available: false).isAvailable)
    }

    @Test func onlyParsingRoutesAreSupported() {
        #expect(backend(available: true).supportedRoutes == [.parsePantry, .parseRecipe])
    }

    @Test func unavailableModelThrowsAssistantUnavailableForEveryRouteItClaims() async {
        let backend = backend(available: false)
        await backend.prepare()
        await #expect(throws: LarderError.assistantUnavailable) { try await backend.parsePantry(text: "2 onions") }
        await #expect(throws: LarderError.assistantUnavailable) { try await backend.parseRecipe(text: "Dal", imageData: nil) }
    }

    @Test func explainAndAdjustAreLeftToTheProxy() async {
        let backend = backend(available: true)
        let plan = PlanExplainRequest(meals: [])
        let request = AdjustRequest(message: "quicker", maxCookMinutes: 30, dietPatterns: [], goal: .maintain)
        await #expect(throws: LarderError.assistantUnavailable) { try await backend.explain(plan: plan) }
        await #expect(throws: LarderError.assistantUnavailable) { try await backend.adjust(request: request) }
    }

    @Test func blankPantryTextGivesNoLinesWithoutCallingTheModel() async throws {
        #expect(try await backend(available: true).parsePantry(text: " \n ").isEmpty)
    }

    @Test func blankRecipeTextIsInvalidWithoutCallingTheModel() async {
        await #expect(throws: LarderError.invalidResponse) {
            try await backend(available: true).parseRecipe(text: "  ", imageData: nil)
        }
    }

    @Test func unreadableRecipePhotoIsInvalidWithoutCallingTheModel() async {
        await #expect(throws: LarderError.invalidResponse) {
            try await backend(available: true).parseRecipe(text: "Dal", imageData: Data([0x00, 0x01, 0x02]))
        }
    }

    @Test func routerSkipsTheBackendWhileTheModelIsUnavailable() async throws {
        let configuration = ProxyConfiguration(
            baseURL: try #require(URL(string: "https://proxy.invalid")),
            clientSecretProvider: { nil },
            entitlementProvider: { nil }
        )
        let proxy = ProxyAssistantBackend(
            client: ProxyClient(configuration: configuration, urlSession: .shared, dateProvider: UnusedDateProvider()),
            dateProvider: UnusedDateProvider(),
            explainContext: { throw LarderError.notFound }
        )
        let router = AssistantRouter(onDevice: backend(available: false), proxy: proxy, consent: { Consents(aiProcessing: false) })
        let lines = try await router.parsePantry(text: "2 onions")
        #expect(lines == [ParsedPantryLine(rawText: "2 onions", name: "onions", quantity: 2)])
    }

    @Test(.enabled(if: liveModelIsAvailable, "Needs Apple Intelligence enabled on this Mac"))
    func liveModelParsesAShortPantryList() async throws {
        let lines = try await FoundationModelsBackend(dates: UnusedDateProvider()).parsePantry(text: "2 onions, a bag of rice")
        #expect(!lines.isEmpty)
    }
}
