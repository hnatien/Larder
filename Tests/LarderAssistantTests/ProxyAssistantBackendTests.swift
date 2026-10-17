import Foundation
import Testing
import LarderCore
@testable import LarderAssistant

struct ProxyAssistantBackendTests {
    private static let forbiddenFragments = [
        "\"birthYear\"", "1987", "\"sex\"", "\"female\"", "\"heightCm\"", "168.5", "\"weightKg\"", "71.3",
        "\"weeklyBudget\"", "\"currencyCode\"", "EUR", "\"activityLevel\"", "\"equipment\"", "\"consents\"",
        "medical", "religious", "coeliacDisease", "halal", "peanut", "allergen",
    ]

    private func stubbed(_ path: String, _ reply: Stub.Reply) -> Stub {
        let stub = Stub()
        stub.on(Fixtures.sessionPath, Fixtures.sessionReply())
        stub.on(path, reply)
        return stub
    }

    @Test func explainBodyMatchesTheProxyContract() async throws {
        let stub = stubbed(Fixtures.explainPath, Fixtures.explainReply)
        _ = try await Fixtures.backend(stub).explain(plan: Fixtures.plan)
        let body = try #require(stub.requests(to: Fixtures.explainPath).first).json()

        #expect(Set(body.keys) == ["plan", "shelfBalance", "profileSummary"])
        let days = try #require((body["plan"] as? [String: Any])?["days"] as? [[String: Any]])
        #expect(days.map { $0["date"] as? String } == ["2026-10-16", "2026-10-17"])
        let firstMeal = try #require((days[0]["meals"] as? [[String: Any]])?.first)
        #expect(Set(firstMeal.keys) == ["slot", "recipeTitle", "minutes", "reasonCodes"])
        #expect(firstMeal["slot"] as? String == "dinner")
        #expect(firstMeal["minutes"] as? Int == 35)
        let reasons = try #require(firstMeal["reasonCodes"] as? [[String: Any]])
        #expect(reasons.map { $0["code"] as? String } == ["usesExpiring", "pantryOverlap"])
        let params = try #require(reasons[0]["params"] as? [String: Any])
        #expect(params["food"] as? String == "spinach")
        #expect(params["bestBy"] as? String == "2026-10-18")
        #expect((days[1]["meals"] as? [Any])?.count == 2)

        let shelf = try #require(body["shelfBalance"] as? [String: Any])
        #expect(shelf["groupsLight"] as? [String] == ["legumes"])
        #expect(shelf["groupsHeavy"] as? [String] == ["grains"])
    }

    @Test func explainBodyNeverCarriesSensitiveProfileFieldsOrConstraints() async throws {
        let stub = stubbed(Fixtures.explainPath, Fixtures.explainReply)
        _ = try await Fixtures.backend(stub).explain(plan: Fixtures.plan)
        let request = try #require(stub.requests(to: Fixtures.explainPath).first)

        let summary = try #require(request.json()["profileSummary"] as? [String: Any])
        #expect(Set(summary.keys) == ["goal", "householdSize", "maxCookMinutes", "showsNumbers"])
        for fragment in Self.forbiddenFragments {
            #expect(!request.bodyText.contains(fragment), "Body leaked \(fragment)")
        }
        #expect(!request.bodyText.contains(Fixtures.spinach.rawValue.uuidString))
    }

    @Test func explainUsesQuickReasonMinutesWhenTheLookupMisses() async throws {
        let stub = stubbed(Fixtures.explainPath, Fixtures.explainReply)
        _ = try await Fixtures.backend(stub, context: Fixtures.explainContext(recipeMinutes: [:])).explain(plan: Fixtures.plan)
        let days = try #require((stub.requests(to: Fixtures.explainPath).first?.json()["plan"] as? [String: Any])?["days"] as? [[String: Any]])
        let minutes = days.flatMap { ($0["meals"] as? [[String: Any]]) ?? [] }.map { $0["minutes"] as? Int }
        #expect(minutes == [0, 20, 25])
    }

    @Test func explainResponseMapsDatesAndSlotsToMealIndexes() async throws {
        let stub = stubbed(Fixtures.explainPath, Fixtures.explainReply)
        let explanation = try await Fixtures.backend(stub).explain(plan: Fixtures.plan)

        #expect(explanation.summary == "Spinach gets used before Sunday.")
        #expect(explanation.mealNotes == [
            .init(mealIndex: 0, text: "Soup uses the spinach."),
            .init(mealIndex: 1, text: "Two quick meals."),
            .init(mealIndex: 2, text: "Or Bean chilli. Uses the same beans."),
        ])
    }

    @Test func parsePantryBodyIsScrubbedAndTrimmed() async throws {
        let stub = stubbed(Fixtures.pantryPath, Fixtures.pantryReply)
        let text = "2 onions, mail me at cook@example.com or +44 20 7946 0958, " + String(repeating: "rice ", count: 200)
        _ = try await Fixtures.backend(stub).parsePantry(text: text)
        let body = try #require(stub.requests(to: Fixtures.pantryPath).first).json()

        #expect(Set(body.keys) == ["text"])
        let sent = try #require(body["text"] as? String)
        #expect(sent.hasPrefix("2 onions, mail me at [removed] or [removed], rice"))
        #expect(!sent.contains("cook@example.com"))
        #expect(!sent.contains("7946"))
        #expect(sent.utf16.count <= 500)
    }

    @Test func parsePantryMapsUnitsLocationsAndBestByHints() async throws {
        let stub = stubbed(Fixtures.pantryPath, Fixtures.pantryReply)
        let lines = try await Fixtures.backend(stub).parsePantry(text: "2 onions, 500 g chicken thighs in the freezer, stock")
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Fixtures.now))
        #expect(lines == [
            ParsedPantryLine(rawText: "onions", name: "onions", quantity: 2),
            ParsedPantryLine(rawText: "chicken thighs", name: "chicken thighs", quantity: 500, unit: .gram, location: .freezer, bestBy: nextWeek),
            ParsedPantryLine(rawText: "stock", name: "stock", quantity: 1, unit: nil, location: .pantry),
        ])
    }

    @Test func blankPantryTextSkipsTheNetwork() async throws {
        let stub = Stub()
        #expect(try await Fixtures.backend(stub).parsePantry(text: "   \n ").isEmpty)
        #expect(stub.requests.isEmpty)
    }

    @Test func parseRecipeSendsTheImageAsBase64WithItsMediaType() async throws {
        let stub = stubbed(Fixtures.recipePath, Fixtures.recipeReply)
        _ = try await Fixtures.backend(stub).parseRecipe(text: "  ", imageData: Fixtures.jpegBytes)
        let body = try #require(stub.requests(to: Fixtures.recipePath).first).json()

        #expect(Set(body.keys) == ["imageBase64", "imageMediaType"])
        #expect(body["imageMediaType"] as? String == "image/jpeg")
        #expect(body["imageBase64"] as? String == Fixtures.jpegBytes.base64EncodedString())
    }

    @Test(arguments: [(Fixtures.jpegBytes, "image/jpeg"), (Fixtures.pngBytes, "image/png"), (Fixtures.webpBytes, "image/webp")])
    func imageMediaTypeIsSniffedFromLeadingBytes(data: Data, mediaType: String) {
        #expect(ImageMediaType(sniffing: data)?.rawValue == mediaType)
    }

    @Test(arguments: [Fixtures.gifBytes, Data(), Data([0xFF]), Data(Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WAVE".utf8))])
    func unsupportedImagesAreRejectedBeforeTheNetwork(data: Data) async {
        let stub = Stub()
        await #expect(throws: LarderError.invalidResponse) {
            try await Fixtures.backend(stub).parseRecipe(text: "Dal", imageData: data)
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func recipeWithNothingToSendIsRejectedBeforeTheNetwork() async {
        let stub = Stub()
        await #expect(throws: LarderError.invalidResponse) {
            try await Fixtures.backend(stub).parseRecipe(text: " \n", imageData: nil)
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func parseRecipeScrubsTextAndMapsTheResponse() async throws {
        let stub = stubbed(Fixtures.recipePath, Fixtures.recipeReply)
        let recipe = try await Fixtures.backend(stub).parseRecipe(text: "Dal from https://blog.example.com/dal by ana@example.com", imageData: nil)
        let body = try #require(stub.requests(to: Fixtures.recipePath).first).json()

        #expect(body["text"] as? String == "Dal from [removed] by [removed]")
        #expect(body["imageBase64"] == nil)
        #expect(recipe == ParsedRecipe(
            title: "Dal",
            servings: 4,
            prepMinutes: 10,
            cookMinutes: 30,
            ingredients: [
                ParsedIngredient(rawText: "1 cup red lentils", name: "red lentils", quantity: 1, unit: .cup),
                ParsedIngredient(rawText: "salt", name: "salt"),
            ],
            steps: [RecipeStep(text: "Rinse the lentils."), RecipeStep(text: "Simmer.", timerSeconds: 1200)]
        ))
    }

    @Test func adjustBodyCarriesOnlyNonSensitiveConstraints() async throws {
        let stub = stubbed(Fixtures.adjustPath, .json(200, #"{"edits":[],"clarifyingQuestion":null}"#))
        let request = AdjustRequest(
            message: "Vegan on Tuesday, text me on +1 (555) 123-4567",
            maxCookMinutes: 25,
            dietPatterns: [.vegetarian, .mediterranean],
            goal: .saveMoney
        )
        _ = try await Fixtures.backend(stub).adjust(request: request)
        let recorded = try #require(stub.requests(to: Fixtures.adjustPath).first)
        let body = try recorded.json()

        #expect(Set(body.keys) == ["instruction", "currentConstraints", "planContext"])
        #expect(body["instruction"] as? String == "Vegan on Tuesday, text me on [removed]")
        let constraints = try #require(body["currentConstraints"] as? [[String: String]])
        #expect(constraints == [
            ["axis": "ethical", "kind": "diet:mediterranean", "strictness": "soft"],
            ["axis": "ethical", "kind": "diet:vegetarian", "strictness": "soft"],
            ["axis": "preference", "kind": "time:maxMinutes:25", "strictness": "soft"],
            ["axis": "goal", "kind": "goal:saveMoney", "strictness": "soft"],
        ])
        let days = try #require((body["planContext"] as? [String: Any])?["days"] as? [[String: Any]])
        #expect(days.count == 7)
        #expect(days.first?["date"] as? String == "2026-10-16")
        #expect(days.last?["date"] as? String == "2026-10-22")
        #expect(!recorded.bodyText.contains("medical"))
        #expect(!recorded.bodyText.contains("religious"))
        #expect(!recorded.bodyText.contains("555"))
    }

    @Test func adjustMapsEditsAndRecordsWhatItDrops() async throws {
        let reply = """
            {"edits":[\
            {"op":"add","constraint":{"axis":"ethical","kind":"diet:vegan","strictness":"soft"},"scope":{"dates":["2026-10-20"]}},\
            {"op":"replace","constraint":{"axis":"preference","kind":"time:maxMinutes:20","strictness":"soft"},"scope":{}},\
            {"op":"remove","constraint":{"axis":"ethical","kind":"diet:mediterranean","strictness":"soft"},"scope":{}},\
            {"op":"add","constraint":{"axis":"preference","kind":"dislike:coriander","strictness":"soft"},"scope":{}},\
            {"op":"add","constraint":{"axis":"preference","kind":"useUp:rice","strictness":"soft"},"scope":{}},\
            {"op":"add","constraint":{"axis":"medical","kind":"allergen:peanut","strictness":"hard"},"scope":{}},\
            {"op":"add","constraint":{"axis":"religious","kind":"religious:halal","strictness":"hard"},"scope":{}},\
            {"op":"add","constraint":{"axis":"ethical","kind":"diet:carnivore","strictness":"soft"},"scope":{}},\
            {"op":"add","constraint":{"axis":"ethical","kind":"diet:vegan","strictness":"soft"},"scope":{"slots":["dinner"]}},\
            {"op":"add","constraint":{"axis":"ethical","kind":"diet:vegan","strictness":"soft"},"scope":{"dates":["2031-01-01"]}},\
            {"op":"remove","constraint":{"axis":"ethical","kind":"diet:vegan","strictness":"soft"},"scope":{"dates":["2026-10-17"]}},\
            {"op":"merge","constraint":{"axis":"ethical","kind":"diet:vegan","strictness":"soft"},"scope":{}}],\
            "clarifyingQuestion":"Peanut allergies are changed in Settings."}
            """
        let stub = stubbed(Fixtures.adjustPath, .json(200, reply))
        let edit = try await Fixtures.backend(stub).adjust(
            request: AdjustRequest(message: "Vegan Tuesday, quick meals, use the rice", maxCookMinutes: 30, dietPatterns: [.mediterranean], goal: .lessWaste)
        )

        #expect(edit.changes == [
            .addDiet(.vegan, dayOffset: 4),
            .setMaxCookMinutes(20, dayOffset: nil),
            .removeDiet(.mediterranean),
            .addDislike("coriander"),
            .useUp("rice"),
        ])
        #expect(edit.clarifyingQuestion == "Peanut allergies are changed in Settings.")
        #expect(edit.droppedCount == 7)
        #expect(edit.summary.hasPrefix("Peanut allergies are changed in Settings. Not applied here: "))
        #expect(edit.summary.contains("allergen:peanut, religious:halal, diet:carnivore, diet:vegan, diet:vegan, diet:vegan, diet:vegan."))
    }

    @Test func adjustMapsAWholeWeekGoalAndDropsOthers() async throws {
        let reply = """
            {"edits":[\
            {"op":"add","constraint":{"axis":"goal","kind":"goal:moreProtein","strictness":"soft"},"scope":{}},\
            {"op":"replace","constraint":{"axis":"goal","kind":"goal:saveMoney","strictness":"soft"},"scope":{}},\
            {"op":"add","constraint":{"axis":"goal","kind":"goal:moreProtein","strictness":"soft"},"scope":{"dates":["2026-10-20"]}},\
            {"op":"add","constraint":{"axis":"goal","kind":"goal:bulkUp","strictness":"soft"},"scope":{}},\
            {"op":"remove","constraint":{"axis":"goal","kind":"goal:lessWaste","strictness":"soft"},"scope":{}}],\
            "clarifyingQuestion":null}
            """
        let stub = stubbed(Fixtures.adjustPath, .json(200, reply))
        let edit = try await Fixtures.backend(stub).adjust(
            request: AdjustRequest(message: "More protein", maxCookMinutes: 30, dietPatterns: [], goal: .lessWaste)
        )

        #expect(edit.changes == [.setGoal(.moreProtein), .setGoal(.saveMoney)])
        #expect(edit.droppedCount == 3)
    }

    @Test func blankClarifyingQuestionCountsAsNone() async throws {
        let stub = stubbed(Fixtures.adjustPath, .json(200, #"{"edits":[],"clarifyingQuestion":"  "}"#))
        let edit = try await Fixtures.backend(stub).adjust(
            request: AdjustRequest(message: "quick dinners", maxCookMinutes: 30, dietPatterns: [], goal: .maintain)
        )
        #expect(edit.clarifyingQuestion == nil)
        #expect(edit.droppedCount == 0)
        #expect(edit.summary.isEmpty)
    }

    @Test func emptyAdjustInstructionIsRejectedBeforeTheNetwork() async {
        let stub = Stub()
        await #expect(throws: LarderError.invalidResponse) {
            try await Fixtures.backend(stub).adjust(request: AdjustRequest(message: "  ", maxCookMinutes: 30, dietPatterns: [], goal: .maintain))
        }
        #expect(stub.requests.isEmpty)
    }
}
