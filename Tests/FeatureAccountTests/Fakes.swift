import Foundation
import LarderCore
import Synchronization
@testable import FeatureAccount

enum FakeError: Error {
    case failed
}

/// 2026-10-16 12:00 UTC.
let referenceNow = Date(timeIntervalSince1970: 1_792_152_000)
let monthlyID = EntitlementStore.plusProductIDs[0]
let annualID = EntitlementStore.plusProductIDs[1]

struct FixedDates: DateProvider {
    var now: Date = referenceNow
}

final class MutableDates: DateProvider {
    private let value = Mutex(referenceNow)

    var now: Date { value.withLock { $0 } }

    func advance(by seconds: TimeInterval) {
        value.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

final class InMemoryKeyValueStore: KeyValueStore {
    private let values = Mutex<[String: Bool]>([:])

    func bool(forKey key: String) -> Bool? { values.withLock { $0[key] } }
    func set(_ value: Bool, forKey key: String) { values.withLock { $0[key] = value } }
}

final class CallCounter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    func increment() { count.withLock { $0 += 1 } }
}

func record(
    _ productID: String = annualID,
    expires: Date? = referenceNow.addingTimeInterval(86_400),
    revoked: Date? = nil,
    upgraded: Bool = false,
    verified: Bool = true,
    jws: String? = nil
) -> EntitlementRecord {
    EntitlementRecord(
        productID: productID,
        expirationDate: expires,
        revocationDate: revoked,
        isUpgraded: upgraded,
        isVerified: verified,
        signedJWS: jws ?? "jws.\(productID)"
    )
}

let monthlyProduct = StoreProduct(
    id: monthlyID, displayName: "Larder Plus Monthly", displayPrice: "$7.99", price: 7.99,
    period: BillingPeriod(value: 1, unit: .month)
)
let annualProduct = StoreProduct(
    id: annualID, displayName: "Larder Plus Annual", displayPrice: "$49.99", price: 49.99,
    period: BillingPeriod(value: 1, unit: .year), freeTrial: BillingPeriod(value: 7, unit: .day)
)

/// A scripted App Store: products, entitlements, purchase and restore results, and a hand-fed update stream.
final class FakeStoreFront: StoreFront {
    struct Script: Sendable {
        var products: [StoreProduct] = [annualProduct, monthlyProduct]
        var failsProducts = false
        var entitlements: [EntitlementRecord] = []
        var purchaseOutcome: PurchaseOutcome = .userCancelled
        var failsPurchase = false
        var failsRestore = false
        /// Entitlements that appear once restore succeeds.
        var restoredEntitlements: [EntitlementRecord]?
        var purchased: [String] = []
        var restoreCount = 0
    }

    let updates: AsyncStream<EntitlementRecord>
    private let continuation: AsyncStream<EntitlementRecord>.Continuation
    private let script: Mutex<Script>

    init(_ script: Script = Script()) {
        self.script = Mutex(script)
        (updates, continuation) = AsyncStream.makeStream(of: EntitlementRecord.self)
    }

    var state: Script { script.withLock { $0 } }

    func update(_ change: (inout Script) -> Void) {
        script.withLock { change(&$0) }
    }

    func send(_ record: EntitlementRecord) {
        continuation.yield(record)
    }

    func products(for ids: [String]) async throws -> [StoreProduct] {
        let script = state
        if script.failsProducts { throw FakeError.failed }
        return script.products.filter { ids.contains($0.id) }
    }

    func purchase(_ product: StoreProduct) async throws -> PurchaseOutcome {
        try script.withLock { script in
            if script.failsPurchase { throw FakeError.failed }
            script.purchased.append(product.id)
            return script.purchaseOutcome
        }
    }

    func currentEntitlements() async -> [EntitlementRecord] {
        state.entitlements
    }

    func restore() async throws {
        try script.withLock { script in
            script.restoreCount += 1
            if script.failsRestore { throw FakeError.failed }
            if let restored = script.restoredEntitlements { script.entitlements = restored }
        }
    }
}

actor FakeProfileRepository: ProfileRepository {
    var storedProfile: UserProfile?
    var storedConstraints: [DietaryConstraint]
    var storedTargets: [NutrientTarget]
    var failsSaves = false
    var failsReads = false

    init(profile: UserProfile? = nil, constraints: [DietaryConstraint] = [], targets: [NutrientTarget] = []) {
        storedProfile = profile
        storedConstraints = constraints
        storedTargets = targets
    }

    func setFailsSaves(_ fails: Bool) { failsSaves = fails }
    func setFailsReads(_ fails: Bool) { failsReads = fails }

    func profile() throws -> UserProfile? {
        if failsReads { throw FakeError.failed }
        return storedProfile
    }

    func save(_ profile: UserProfile) throws {
        if failsSaves { throw FakeError.failed }
        storedProfile = profile
    }

    func constraints() throws -> [DietaryConstraint] {
        if failsReads { throw FakeError.failed }
        return storedConstraints
    }

    func saveConstraints(_ constraints: [DietaryConstraint]) throws {
        if failsSaves { throw FakeError.failed }
        storedConstraints = constraints
    }

    func targets() throws -> [NutrientTarget] {
        if failsReads { throw FakeError.failed }
        return storedTargets
    }

    func saveTargets(_ targets: [NutrientTarget]) throws {
        if failsSaves { throw FakeError.failed }
        storedTargets = targets
    }
}

/// Recipes, shelves and plans in memory.
actor FakeLibrary: RecipeRepository, PantryRepository, PlanRepository {
    var recipes: [Recipe] = []
    var ingredientsByRecipe: [RecipeID: [Ingredient]] = [:]
    var pantryItems: [PantryItem] = []
    var mealPlans: [MealPlan] = []
    var mealsByPlan: [MealPlanID: [PlannedMeal]] = [:]
    var failsReads = false

    func setFailsReads(_ fails: Bool) { failsReads = fails }

    func all() throws -> [Recipe] {
        if failsReads { throw FakeError.failed }
        return recipes
    }

    func search(text: String, limit: Int) -> [Recipe] { [] }
    func recipe(by id: RecipeID) -> Recipe? { recipes.first { $0.id == id } }

    func save(_ recipe: Recipe, ingredients: [Ingredient]) {
        recipes.append(recipe)
        ingredientsByRecipe[recipe.id] = ingredients
    }

    func delete(_ id: RecipeID) { recipes.removeAll { $0.id == id } }
    func ingredients(for recipeID: RecipeID) -> [Ingredient] { ingredientsByRecipe[recipeID] ?? [] }

    func items() -> [PantryItem] { pantryItems }
    func upsert(_ item: PantryItem) { pantryItems.append(item) }
    func remove(_ id: PantryItemID) { pantryItems.removeAll { $0.id == id } }
    func consume(foodID: FoodID, grams: Double) {}

    func currentPlan() -> MealPlan? { mealPlans.first }
    func plans() -> [MealPlan] { mealPlans }

    func save(_ plan: MealPlan, meals: [PlannedMeal]) {
        mealPlans.append(plan)
        mealsByPlan[plan.id] = meals
    }

    func meals(for planID: MealPlanID) -> [PlannedMeal] { mealsByPlan[planID] ?? [] }
    func updateMeal(_ meal: PlannedMeal) {}
}

/// Polls `condition` on the main actor until it holds or about a second passes.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

let sampleProfile = UserProfile(
    birthYear: 1985, heightCm: 170, activityLevel: .light, goal: .lessWaste,
    householdSize: 3, weeklyBudget: 85.5, currencyCode: "USD", maxCookMinutes: 35, equipment: [.oven, .stovetop]
)
