import CoreGraphics
import Foundation
import ImageIO
import LarderCore
import Synchronization
import UniformTypeIdentifiers
@testable import FeatureRecipes

enum Fixture {
    static func html(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    enum FixtureError: Error { case missing(String) }
}

struct StoreFailure: Error {}

actor FakeStore: RecipeRepository, RecipePhotoStore, FoodRepository, ProfileRepository {
    var recipes: [Recipe]
    var ingredientsByRecipe: [RecipeID: [Ingredient]]
    var foodList: [Food]
    var profileValue: UserProfile?
    var constraintList: [DietaryConstraint]
    var failReads = false
    var failSave = false
    var failDelete = false
    var failPhotoSave = false
    private(set) var photos: [String: Data] = [:]
    private(set) var deletedPhotos: [String] = []
    private(set) var foodSearches: [String] = []
    private(set) var saved: [(Recipe, [Ingredient])] = []

    init(
        recipes: [Recipe] = [],
        ingredients: [RecipeID: [Ingredient]] = [:],
        foods: [Food] = [],
        profile: UserProfile? = nil,
        constraints: [DietaryConstraint] = []
    ) {
        self.recipes = recipes
        self.ingredientsByRecipe = ingredients
        self.foodList = foods
        self.profileValue = profile
        self.constraintList = constraints
    }

    func setFailReads(_ value: Bool) { failReads = value }
    func setFailSave(_ value: Bool) { failSave = value }
    func setFailDelete(_ value: Bool) { failDelete = value }
    func setFailPhotoSave(_ value: Bool) { failPhotoSave = value }
    func setProfile(_ value: UserProfile?) { profileValue = value }

    func all() throws -> [Recipe] {
        if failReads { throw StoreFailure() }
        return recipes
    }

    func search(text: String, limit: Int) throws -> [Recipe] {
        if failReads { throw StoreFailure() }
        return Array(recipes.filter { $0.title.localizedCaseInsensitiveContains(text) }.prefix(limit))
    }

    func recipe(by id: RecipeID) -> Recipe? { recipes.first { $0.id == id } }

    func save(_ recipe: Recipe, ingredients: [Ingredient]) throws {
        if failSave { throw StoreFailure() }
        recipes.removeAll { $0.id == recipe.id }
        recipes.append(recipe)
        ingredientsByRecipe[recipe.id] = ingredients
        saved.append((recipe, ingredients))
    }

    func delete(_ id: RecipeID) throws {
        if failDelete { throw StoreFailure() }
        recipes.removeAll { $0.id == id }
    }

    func save(_ jpeg: Data, for recipeID: RecipeID) throws -> String {
        if failPhotoSave { throw StoreFailure() }
        let fileName = recipeID.rawValue.uuidString + ".jpg"
        photos[fileName] = jpeg
        return fileName
    }

    func delete(_ fileName: String) {
        photos[fileName] = nil
        deletedPhotos.append(fileName)
    }

    func ingredients(for recipeID: RecipeID) throws -> [Ingredient] {
        if failReads { throw StoreFailure() }
        return ingredientsByRecipe[recipeID] ?? []
    }

    func search(text: String, limit: Int) -> [Food] {
        foodSearches.append(text)
        return Array(foodList.filter { $0.name.localizedCaseInsensitiveContains(text) }.prefix(limit))
    }

    func food(by id: FoodID) -> Food? { foodList.first { $0.id == id } }
    func foods(byIDs ids: [FoodID]) -> [Food] { foodList.filter { ids.contains($0.id) } }
    func food(byGTIN gtin: String) -> Food? { nil }
    func upsert(_ foods: [Food]) {}

    func profile() throws -> UserProfile? {
        if failReads { throw StoreFailure() }
        return profileValue
    }

    func save(_ profile: UserProfile) {}
    func constraints() throws -> [DietaryConstraint] {
        if failReads { throw StoreFailure() }
        return constraintList
    }
    func saveConstraints(_ constraints: [DietaryConstraint]) {}
    func targets() -> [NutrientTarget] { [] }
    func saveTargets(_ targets: [NutrientTarget]) {}
}

actor FakeAssistant: AssistantBackend {
    var result: Result<ParsedRecipe, any Error>
    private(set) var parseCalls: [(text: String, imageData: Data?)] = []

    init(result: Result<ParsedRecipe, any Error> = .failure(LarderError.assistantUnavailable)) {
        self.result = result
    }

    func explain(plan: PlanExplainRequest) async throws -> PlanExplanation { throw LarderError.assistantUnavailable }
    func parsePantry(text: String) async throws -> [ParsedPantryLine] { throw LarderError.assistantUnavailable }
    func adjust(request: AdjustRequest) async throws -> ConstraintEdit { throw LarderError.assistantUnavailable }

    func parseRecipe(text: String, imageData: Data?) async throws -> ParsedRecipe {
        parseCalls.append((text, imageData))
        return try result.get()
    }
}

enum Sample {
    static func profile(showsNumbers: Bool = false, aiProcessing: Bool = false) -> UserProfile {
        UserProfile(
            birthYear: 1990, heightCm: 170, activityLevel: .moderate, goal: .eatBetter, householdSize: 2,
            currencyCode: "USD", maxCookMinutes: 45, showsNumbers: showsNumbers,
            consents: Consents(aiProcessing: aiProcessing)
        )
    }

    static func recipe(
        _ title: String,
        origin: RecipeOrigin = .generated,
        prep: Int = 10,
        cook: Int = 20,
        servings: Int = 4,
        cuisine: String? = nil,
        meals: Set<MealType> = [.dinner],
        diets: Set<DietPattern> = []
    ) -> Recipe {
        Recipe(
            title: title, origin: origin, servings: servings, prepMinutes: prep, cookMinutes: cook,
            tags: RecipeTags(cuisine: cuisine, mealTypes: meals, dietFlags: diets)
        )
    }

    static func ingredient(_ recipe: Recipe, _ text: String, quantity: Double, unit: UnitOfMeasure, food: Food? = nil) -> Ingredient {
        Ingredient(recipeID: recipe.id, rawText: text, quantity: quantity, unit: unit, foodID: food?.id, matchConfidence: food == nil ? 0 : 1)
    }

    @MainActor static func model(
        store: FakeStore,
        assistant: FakeAssistant = FakeAssistant(),
        isPlus: @escaping @Sendable () async -> Bool = { false }
    ) -> RecipesModel {
        RecipesModel(recipes: store, photos: store, foods: store, profile: store, assistant: assistant, isPlus: isPlus)
    }

    static func html(recipeJSON: String) -> String {
        "<html><head><script type=\"application/ld+json\">\(recipeJSON)</script></head><body></body></html>"
    }
}

/// Records the timer notifications a cooking session schedules and cancels.
@MainActor
final class FakeTimerNotifications: TimerNotifying {
    struct Scheduled: Equatable {
        var id: String
        var title: String
        var body: String
        var seconds: Int
        var playsSound: Bool
    }

    var currentPermission: TimerNotificationPermission
    var grantsPermission: Bool
    private(set) var requestCount = 0
    private(set) var scheduled: [Scheduled] = []
    private(set) var cancelled: [String] = []

    init(permission: TimerNotificationPermission = .allowed, grantsPermission: Bool = true) {
        currentPermission = permission
        self.grantsPermission = grantsPermission
    }

    func permission() async -> TimerNotificationPermission { currentPermission }

    func requestPermission() async -> Bool {
        requestCount += 1
        currentPermission = grantsPermission ? .allowed : .denied
        return grantsPermission
    }

    func schedule(id: String, title: String, body: String, after seconds: Int, playsSound: Bool) {
        scheduled.append(Scheduled(id: id, title: title, body: body, seconds: seconds, playsSound: playsSound))
    }

    func cancel(id: String) {
        cancelled.append(id)
    }
}

/// Image bytes made on the spot, so photo tests need no fixture files.
enum TestImage {
    /// A PNG of a flat colour, `width` by `height` pixels.
    static func png(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.7, green: 0.3, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    /// The pixel size of encoded image `data`, or `nil` when it is not an image.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    /// The uniform type of encoded image `data`.
    static func type(of data: Data) -> String? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap(CGImageSourceGetType) as String?
    }
}

/// A clock that only moves when a test advances it.
final class ManualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var nextID = 0
        var sleepers: [Sleeper] = []
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }

    /// How many tasks are waiting on this clock.
    var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = state.withLock { state -> Int in
            defer { state.nextID += 1 }
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let outcome: Result<Void, any Error>? = state.withLock { state in
                    if Task.isCancelled { return .failure(CancellationError()) }
                    if deadline <= state.now { return .success(()) }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return nil
                }
                if let outcome { continuation.resume(with: outcome) }
            }
        } onCancel: {
            let cancelled = state.withLock { state -> Sleeper? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return state.sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and wakes every sleeper whose deadline has passed.
    func advance(by duration: Duration) {
        let due = state.withLock { state -> [Sleeper] in
            state.now = state.now.advanced(by: duration)
            let due = state.sleepers.filter { $0.deadline <= state.now }
            state.sleepers.removeAll { $0.deadline <= state.now }
            return due
        }
        due.forEach { $0.continuation.resume() }
    }
}

/// Gives main-actor tasks a chance to run.
@MainActor func settle() async {
    for _ in 0..<40 { await Task.yield() }
}
