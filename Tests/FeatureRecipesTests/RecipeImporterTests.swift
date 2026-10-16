import Foundation
import LarderCore
import Synchronization
import Testing
@testable import FeatureRecipes

/// Records which URLs a test fetched and answers with a canned page.
final class FetchRecorder: Sendable {
    private let urls = Mutex<[URL]>([])
    private let body: Data
    private let contentType: String
    private let failure: (any Error)?
    /// Answers for particular addresses, such as a page's photo; any other address gets the canned page.
    private let routes: [URL: Result<(Data, String), StoreFailure>]

    init(
        html: String,
        contentType: String = "text/html; charset=utf-8",
        failure: (any Error)? = nil,
        routes: [URL: Result<(Data, String), StoreFailure>] = [:]
    ) {
        body = Data(html.utf8)
        self.contentType = contentType
        self.failure = failure
        self.routes = routes
    }

    init(data: Data, contentType: String) {
        body = data
        self.contentType = contentType
        failure = nil
        routes = [:]
    }

    var fetchedURLs: [URL] { urls.withLock { $0 } }

    var fetch: @Sendable (URL) async throws -> (Data, String) {
        { [self] url in
            urls.withLock { $0.append(url) }
            if let route = routes[url] { return try route.get() }
            if let failure { throw failure }
            return (body, contentType)
        }
    }
}

struct RecipeImporterTests {
    private let pageURL = URL(string: "https://example.com/chana-masala")!

    private func importer(
        store: FakeStore,
        assistant: FakeAssistant = FakeAssistant(),
        isPlus: @escaping @Sendable () async -> Bool = { false }
    ) -> RecipeImporter {
        RecipeImporter(foods: store, profile: store, assistant: assistant, isPlus: isPlus)
    }

    private static let assistantRecipe = ParsedRecipe(
        title: "Grandma's stew", servings: 6, prepMinutes: 10, cookMinutes: 40,
        ingredients: [
            ParsedIngredient(rawText: "2 carrots", name: "carrots", quantity: 2, unit: nil),
            ParsedIngredient(rawText: "1 onion (optional)", name: "onion", quantity: 1, unit: nil),
        ],
        steps: [RecipeStep(text: "Simmer for 40 minutes.")]
    )

    // MARK: Structured data

    @Test func importsJSONLDRecipeAsUserImport() async throws {
        let recorder = FetchRecorder(html: try Fixture.html("object"))
        let result = try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        #expect(result.source == .structuredData)
        #expect(result.recipe.origin == .userImport)
        #expect(result.recipe.sourceURL == pageURL)
        #expect(result.recipe.license == nil)
        #expect(result.recipe.title == "Weeknight chana masala & rice")
        #expect(result.recipe.servings == 4)
        #expect(result.recipe.prepMinutes == 10)
        #expect(result.recipe.cookMinutes == 25)
        #expect(result.recipe.tags.cuisine == "Indian")
        #expect(result.recipe.steps[1].timerSeconds == 600)
        #expect(result.ingredients.count == 5)
        #expect(result.ingredients.allSatisfy { $0.recipeID == result.recipe.id })
    }

    // MARK: Photos

    private let photoURL = URL(string: "https://example.com/photo.jpg")!

    @Test func fetchesThePagePhotoAndKeepsASmallJPEG() async throws {
        let recorder = FetchRecorder(
            html: try Fixture.html("object"),
            routes: [photoURL: .success((TestImage.png(width: 2400, height: 1600), "image/png"))]
        )
        let result = try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        #expect(recorder.fetchedURLs == [pageURL, photoURL])
        let photo = try #require(result.photo)
        #expect(TestImage.type(of: photo) == "public.jpeg")
        let size = try #require(TestImage.pixelSize(of: photo))
        #expect(size.width == PhotoDownsampler.maximumPixelSize)
        #expect(size.height == 800)
        #expect(result.recipe.photoFileName == nil)
    }

    @Test func resolvesARelativePhotoAddressAgainstThePage() async throws {
        let html = Sample.html(recipeJSON: #"{"@type":"Recipe","name":"Toast","image":{"@type":"ImageObject","url":"/img/toast.png"},"recipeIngredient":["1 slice bread"]}"#)
        let resolved = URL(string: "https://example.com/img/toast.png")!
        let recorder = FetchRecorder(html: html, routes: [resolved: .success((TestImage.png(width: 40, height: 30), "image/png"))])
        let result = try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        #expect(recorder.fetchedURLs == [pageURL, resolved])
        #expect(result.photo.flatMap(TestImage.pixelSize)?.width == 40)
    }

    @Test func aPhotoThatFailsToDownloadLeavesTheRecipeWithoutOne() async throws {
        let recorder = FetchRecorder(html: try Fixture.html("object"), routes: [photoURL: .failure(StoreFailure())])
        let result = try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        #expect(result.recipe.title == "Weeknight chana masala & rice")
        #expect(result.photo == nil)
    }

    @Test func aPhotoAddressThatIsNotAnImageIsIgnored() async throws {
        let recorder = FetchRecorder(html: try Fixture.html("object"))
        let result = try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        #expect(recorder.fetchedURLs == [pageURL, photoURL])
        #expect(result.photo == nil)
    }

    @Test func bytesLabelledAsAnImageThatDoNotDecodeAreIgnored() async throws {
        let recorder = FetchRecorder(
            html: try Fixture.html("object"),
            routes: [photoURL: .success((Data("not an image".utf8), "image/jpeg"))]
        )
        let result = try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        #expect(result.photo == nil)
    }

    @Test func onlyHTTPPhotoAddressesAreFetched() async throws {
        let html = Sample.html(recipeJSON: #"{"@type":"Recipe","name":"Toast","image":"file:///etc/passwd","recipeIngredient":["1 slice bread"]}"#)
        let recorder = FetchRecorder(html: html)
        let result = try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        #expect(recorder.fetchedURLs == [pageURL])
        #expect(result.photo == nil)
    }

    @Test func pagesWithoutAPhotoFetchOnlyThePage() async throws {
        let recorder = FetchRecorder(html: try Fixture.html("array"))
        let result = try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        #expect(recorder.fetchedURLs == [pageURL])
        #expect(result.photo == nil)
    }

    @Test func unquantifiedLinesBecomeZeroPieces() async throws {
        let recorder = FetchRecorder(html: try Fixture.html("object"))
        let result = try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        let salt = result.ingredients[4]
        #expect(salt.rawText == "salt to taste")
        #expect(salt.quantity == 0)
        #expect(salt.unit == .piece)
    }

    @Test func matchesFoodsWhenTheFirstWordAgrees() async throws {
        let chickpeas = Food(name: "Chickpeas, canned", source: .seedApproximate, foodGroup: .legumes)
        let oil = Food(name: "Olive oil", source: .seedApproximate, foodGroup: .fats)
        let store = FakeStore(foods: [chickpeas, oil])
        let recorder = FetchRecorder(html: try Fixture.html("object"))
        let result = try await importer(store: store).import(from: pageURL, fetch: recorder.fetch)
        #expect(result.ingredients[0].foodID == oil.id)
        #expect(result.ingredients[0].matchConfidence == RecipeImporter.firstWordMatchConfidence)
        #expect(result.ingredients[3].foodID == chickpeas.id)
        #expect(result.ingredients[1].foodID == nil)
        #expect(result.ingredients[1].matchConfidence == 0)
    }

    @Test func doesNotMatchWhenTheTopHitStartsWithAnotherWord() async throws {
        let peanutButter = Food(name: "Peanut butter", source: .seedApproximate, foodGroup: .fats)
        let store = FakeStore(foods: [peanutButter])
        let html = Sample.html(recipeJSON: #"{"@type":"Recipe","name":"Toast","recipeIngredient":["2 tbsp butter"]}"#)
        let result = try await importer(store: store).import(from: pageURL, fetch: FetchRecorder(html: html).fetch)
        #expect(result.ingredients[0].foodID == nil)
        #expect(result.ingredients[0].matchConfidence == 0)
    }

    @Test func matchesPluralsAgainstSingularFoodNames() async throws {
        let egg = Food(name: "Egg, whole", source: .seedApproximate, foodGroup: .protein)
        let store = FakeStore(foods: [egg])
        let html = Sample.html(recipeJSON: #"{"@type":"Recipe","name":"Eggs","recipeIngredient":["3 eggs"]}"#)
        let result = try await importer(store: store).import(from: pageURL, fetch: FetchRecorder(html: html).fetch)
        #expect(result.ingredients[0].foodID == egg.id)
    }

    @Test func missingYieldFallsBackToTheDefault() async throws {
        let recorder = FetchRecorder(html: try Fixture.html("minimal"))
        let result = try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        #expect(result.recipe.servings == RecipeImporter.defaultServings)
        #expect(result.recipe.prepMinutes == 0)
        #expect(result.recipe.cookMinutes == 0)
    }

    @Test func marksOptionalIngredients() async throws {
        let recorder = FetchRecorder(html: try Fixture.html("graph"))
        let result = try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        #expect(result.ingredients.map(\.isOptional) == [false, false, true])
    }

    @Test func decodesLatin1Pages() async throws {
        let html = Sample.html(recipeJSON: #"{"@type":"Recipe","name":"Café au lait","recipeIngredient":["1 cup milk"]}"#)
        let latin1 = try #require(html.data(using: .isoLatin1))
        let recorder = FetchRecorder(data: latin1, contentType: "text/html; charset=ISO-8859-1")
        let result = try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        #expect(result.recipe.title == "Caf\u{E9} au lait")
    }

    // MARK: Input errors

    @Test(arguments: ["ftp://example.com/recipe", "file:///etc/passwd", "mailto:a@example.com"])
    func rejectsNonWebAddresses(address: String) async throws {
        let recorder = FetchRecorder(html: "")
        let url = try #require(URL(string: address))
        await #expect(throws: ImportError.invalidURL) {
            try await importer(store: FakeStore()).import(from: url, fetch: recorder.fetch)
        }
        #expect(recorder.fetchedURLs.isEmpty)
    }

    @Test func networkFailureBecomesFetchFailed() async {
        let recorder = FetchRecorder(html: "", failure: URLError(.notConnectedToInternet))
        await #expect(throws: ImportError.fetchFailed) {
            try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        }
    }

    @Test func nonHTMLContentIsRefused() async {
        let recorder = FetchRecorder(html: "%PDF-1.7", contentType: "application/pdf")
        await #expect(throws: ImportError.notAWebPage) {
            try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        }
    }

    @Test func oversizedPagesAreRefused() async {
        let recorder = FetchRecorder(data: Data(count: 5_000_001), contentType: "text/html")
        await #expect(throws: ImportError.notAWebPage) {
            try await importer(store: FakeStore()).import(from: pageURL, fetch: recorder.fetch)
        }
    }

    // MARK: Assistant fallback

    @Test func freeUserWithoutStructuredDataGetsGuidanceAndNoAssistantCall() async throws {
        let assistant = FakeAssistant(result: .success(Self.assistantRecipe))
        let store = FakeStore(profile: Sample.profile(aiProcessing: true))
        let recorder = FetchRecorder(html: try Fixture.html("plain-page"))
        await #expect(throws: ImportError.noStructuredRecipe) {
            try await importer(store: store, assistant: assistant, isPlus: { false }).import(from: pageURL, fetch: recorder.fetch)
        }
        #expect(await assistant.parseCalls.isEmpty)
    }

    @Test func plusUserWithoutConsentGetsGuidanceAndNoAssistantCall() async throws {
        let assistant = FakeAssistant(result: .success(Self.assistantRecipe))
        let store = FakeStore(profile: Sample.profile(aiProcessing: false))
        let recorder = FetchRecorder(html: try Fixture.html("plain-page"))
        await #expect(throws: ImportError.noStructuredRecipe) {
            try await importer(store: store, assistant: assistant, isPlus: { true }).import(from: pageURL, fetch: recorder.fetch)
        }
        #expect(await assistant.parseCalls.isEmpty)
    }

    @Test func plusUserWithNoProfileIsNotConsented() async throws {
        let assistant = FakeAssistant(result: .success(Self.assistantRecipe))
        let recorder = FetchRecorder(html: try Fixture.html("plain-page"))
        await #expect(throws: ImportError.noStructuredRecipe) {
            try await importer(store: FakeStore(), assistant: assistant, isPlus: { true }).import(from: pageURL, fetch: recorder.fetch)
        }
        #expect(await assistant.parseCalls.isEmpty)
    }

    @Test func unreadableProfileCountsAsNoConsent() async throws {
        let assistant = FakeAssistant(result: .success(Self.assistantRecipe))
        let store = FakeStore(profile: Sample.profile(aiProcessing: true))
        await store.setFailReads(true)
        let recorder = FetchRecorder(html: try Fixture.html("plain-page"))
        await #expect(throws: ImportError.noStructuredRecipe) {
            try await importer(store: store, assistant: assistant, isPlus: { true }).import(from: pageURL, fetch: recorder.fetch)
        }
        #expect(await assistant.parseCalls.isEmpty)
    }

    @Test func plusUserWithConsentFallsBackToTheAssistant() async throws {
        let assistant = FakeAssistant(result: .success(Self.assistantRecipe))
        let store = FakeStore(profile: Sample.profile(aiProcessing: true))
        let recorder = FetchRecorder(html: try Fixture.html("plain-page"))
        let result = try await importer(store: store, assistant: assistant, isPlus: { true }).import(from: pageURL, fetch: recorder.fetch)

        let calls = await assistant.parseCalls
        #expect(calls.count == 1)
        #expect(calls[0].imageData == nil)
        #expect(calls[0].text.contains("2 carrots"))
        #expect(!calls[0].text.contains("tracking"))
        #expect(result.source == .assistant)
        #expect(result.recipe.origin == .userImport)
        #expect(result.recipe.sourceURL == pageURL)
        #expect(result.recipe.title == "Grandma's stew")
        #expect(result.recipe.servings == 6)
        #expect(result.ingredients.map(\.isOptional) == [false, true])
        #expect(result.recipe.steps[0].timerSeconds == 2400)
    }

    @Test func assistantTextIsCappedAtTwentyThousandCharacters() async throws {
        let assistant = FakeAssistant(result: .success(Self.assistantRecipe))
        let store = FakeStore(profile: Sample.profile(aiProcessing: true))
        let html = "<html><body><p>" + String(repeating: "pinch of salt ", count: 5_000) + "</p></body></html>"
        _ = try await importer(store: store, assistant: assistant, isPlus: { true }).import(from: pageURL, fetch: FetchRecorder(html: html).fetch)
        let calls = await assistant.parseCalls
        #expect(calls[0].text.count == RecipeImporter.assistantTextLimit)
    }

    @Test func structuredDataWinsOverTheAssistant() async throws {
        let assistant = FakeAssistant(result: .success(Self.assistantRecipe))
        let store = FakeStore(profile: Sample.profile(aiProcessing: true))
        let recorder = FetchRecorder(html: try Fixture.html("object"))
        let result = try await importer(store: store, assistant: assistant, isPlus: { true }).import(from: pageURL, fetch: recorder.fetch)
        #expect(result.source == .structuredData)
        #expect(await assistant.parseCalls.isEmpty)
    }

    @Test func assistantErrorsArePassedOn() async throws {
        let store = FakeStore(profile: Sample.profile(aiProcessing: true))
        let recorder = FetchRecorder(html: try Fixture.html("plain-page"))
        for error: LarderError in [.plusRequired, .consentRequired, .declined(category: "x"), .quotaExceeded] {
            let assistant = FakeAssistant(result: .failure(error))
            await #expect(throws: ImportError.assistantFailed(error)) {
                try await importer(store: store, assistant: assistant, isPlus: { true }).import(from: pageURL, fetch: recorder.fetch)
            }
        }
    }

    @Test func unknownAssistantErrorsBecomeUnavailable() async throws {
        let store = FakeStore(profile: Sample.profile(aiProcessing: true))
        let assistant = FakeAssistant(result: .failure(URLError(.timedOut)))
        let recorder = FetchRecorder(html: try Fixture.html("plain-page"))
        await #expect(throws: ImportError.assistantFailed(.assistantUnavailable)) {
            try await importer(store: store, assistant: assistant, isPlus: { true }).import(from: pageURL, fetch: recorder.fetch)
        }
    }

    @Test func emptyAssistantAnswerIsNotARecipe() async throws {
        let empty = ParsedRecipe(title: "  ", ingredients: [], steps: [])
        let store = FakeStore(profile: Sample.profile(aiProcessing: true))
        let assistant = FakeAssistant(result: .success(empty))
        let recorder = FetchRecorder(html: try Fixture.html("plain-page"))
        await #expect(throws: ImportError.noStructuredRecipe) {
            try await importer(store: store, assistant: assistant, isPlus: { true }).import(from: pageURL, fetch: recorder.fetch)
        }
    }

    @Test func pageWithNoVisibleTextNeverReachesTheAssistant() async throws {
        let store = FakeStore(profile: Sample.profile(aiProcessing: true))
        let assistant = FakeAssistant(result: .success(Self.assistantRecipe))
        let recorder = FetchRecorder(html: "<html><head><script>x()</script></head><body></body></html>")
        await #expect(throws: ImportError.noStructuredRecipe) {
            try await importer(store: store, assistant: assistant, isPlus: { true }).import(from: pageURL, fetch: recorder.fetch)
        }
        #expect(await assistant.parseCalls.isEmpty)
    }

    @Test func importErrorCopyIsPresentForEveryCase() {
        let errors: [ImportError] = [
            .invalidURL, .fetchFailed, .notAWebPage, .noStructuredRecipe, .saveFailed,
            .assistantFailed(.plusRequired), .assistantFailed(.consentRequired),
            .assistantFailed(.declined(category: nil)), .assistantFailed(.assistantUnavailable),
        ]
        for error in errors {
            let message = RecipesCopy.message(for: error)
            #expect(!message.isEmpty)
            #expect(!message.contains("!"))
            #expect(!message.contains("\u{2014}"))
        }
        // There is no paste-the-text path, so the message must not offer one.
        #expect(!RecipesCopy.message(for: .noStructuredRecipe).contains("paste"))
        #expect(RecipesCopy.message(for: .noStructuredRecipe).contains("Plus"))
    }
}

@MainActor
struct ImportModelTests {
    private func model(
        html: String,
        store: FakeStore = FakeStore(),
        save: @escaping (ImportResult) async throws -> Void = { _ in }
    ) -> (ImportModel, FetchRecorder) {
        let recorder = FetchRecorder(html: html)
        let importer = RecipeImporter(foods: store, profile: store, assistant: FakeAssistant(), isPlus: { false })
        return (ImportModel(importer: importer, fetch: recorder.fetch, save: save), recorder)
    }

    @Test func badAddressFailsWithoutFetching() async {
        let (model, recorder) = model(html: "")
        model.addressText = "not a url"
        await model.fetchPreview()
        #expect(model.phase == .failed(.invalidURL))
        #expect(recorder.fetchedURLs.isEmpty)
    }

    @Test func emptyAddressFails() async {
        let (model, _) = model(html: "")
        await model.fetchPreview()
        #expect(model.phase == .failed(.invalidURL))
    }

    @Test func addressWithoutSchemeGetsHTTPS() async throws {
        let (model, recorder) = model(html: try Fixture.html("object"))
        model.addressText = "  example.com/chana  "
        await model.fetchPreview()
        // The page comes first; the second fetch is the photo its structured data names.
        #expect(recorder.fetchedURLs == [URL(string: "https://example.com/chana")!, URL(string: "https://example.com/photo.jpg")!])
        #expect(model.preview?.recipe.title == "Weeknight chana masala & rice")
    }

    @Test func pageWithoutRecipeFailsWithGuidance() async throws {
        let (model, _) = model(html: try Fixture.html("plain-page"))
        model.addressText = "https://example.com/stew"
        await model.fetchPreview()
        #expect(model.phase == .failed(.noStructuredRecipe))
        #expect(model.preview == nil)
    }

    @Test func servingsCanBeChangedBeforeSaving() async throws {
        let (model, _) = model(html: try Fixture.html("minimal"))
        model.addressText = "https://example.com/toast"
        await model.fetchPreview()
        model.setServings(2)
        #expect(model.preview?.recipe.servings == 2)
        model.setServings(0)
        #expect(model.preview?.recipe.servings == 2)
    }

    @Test func saveHandsTheEditedResultOn() async throws {
        let saved = Mutex<[ImportResult]>([])
        let (model, _) = model(html: try Fixture.html("minimal")) { result in saved.withLock { $0.append(result) } }
        model.addressText = "https://example.com/toast"
        await model.fetchPreview()
        model.setServings(3)
        let didSave = await model.save()
        #expect(didSave)
        #expect(model.phase == .saved)
        #expect(saved.withLock { $0 }.map(\.recipe.servings) == [3])
    }

    @Test func saveFailureReportsAndKeepsNothing() async throws {
        let (model, _) = model(html: try Fixture.html("minimal")) { _ in throw RecipesError.saveFailed }
        model.addressText = "https://example.com/toast"
        await model.fetchPreview()
        let didSave = await model.save()
        #expect(!didSave)
        #expect(model.phase == .failed(.saveFailed))
    }

    @Test func saveWithoutPreviewDoesNothing() async {
        let (model, _) = model(html: "")
        let didSave = await model.save()
        #expect(!didSave)
        #expect(model.phase == .idle)
    }

    @Test func resetReturnsToIdleKeepingTheAddress() async throws {
        let (model, _) = model(html: try Fixture.html("minimal"))
        model.addressText = "https://example.com/toast"
        await model.fetchPreview()
        model.reset()
        #expect(model.phase == .idle)
        #expect(model.addressText == "https://example.com/toast")
    }

    @Test func libraryModelImportSavesIntoTheRepository() async throws {
        let store = FakeStore()
        let library = Sample.model(store: store)
        await library.load()
        let importModel = library.makeImportModel()
        let result = ImportResult(recipe: Sample.recipe("Imported", origin: .userImport), ingredients: [], source: .structuredData)
        try await library.save(result)
        #expect(library.results.map(\.title) == ["Imported"])
        #expect(importModel.phase == .idle)
    }
}
