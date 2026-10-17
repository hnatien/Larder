import Foundation
import LarderCore
@testable import FeatureLedger

struct FixedDates: DateProvider {
    var now: Date = Fixtures.now
}

/// Plans and meals in memory; saving a plan replaces its meals and takes over meals with the same identifiers.
actor FakePlanRepository: PlanRepository {
    private(set) var storedPlans: [MealPlan] = []
    private(set) var storedMeals: [PlannedMeal] = []
    private(set) var saveCount = 0
    private var failWrites = false

    func seed(_ plan: MealPlan, meals: [PlannedMeal]) {
        storedPlans.append(plan)
        storedMeals += meals
    }

    func setFailWrites(_ value: Bool) { failWrites = value }

    func plan(_ id: MealPlanID) -> MealPlan? { storedPlans.first { $0.id == id } }

    func currentPlan() -> MealPlan? { storedPlans.first { $0.status == .active } }

    func plans() -> [MealPlan] { storedPlans.sorted { $0.startDate > $1.startDate } }

    func save(_ plan: MealPlan, meals: [PlannedMeal]) throws {
        if failWrites { throw LarderError.storageFailure }
        saveCount += 1
        storedPlans.removeAll { $0.id == plan.id }
        storedPlans.append(plan)
        let ids = Set(meals.map(\.id))
        storedMeals.removeAll { $0.planID == plan.id || ids.contains($0.id) }
        storedMeals += meals
    }

    func meals(for planID: MealPlanID) -> [PlannedMeal] {
        storedMeals.filter { $0.planID == planID }.sorted { $0.date < $1.date }
    }

    func updateMeal(_ meal: PlannedMeal) throws {
        if failWrites { throw LarderError.storageFailure }
        guard let index = storedMeals.firstIndex(where: { $0.id == meal.id }) else { throw LarderError.notFound }
        storedMeals[index] = meal
    }
}

struct FakeRecipeRepository: RecipeRepository {
    var recipes: [Recipe] = Fixtures.recipes
    var lines: [RecipeID: [Ingredient]] = Fixtures.lines

    func all() -> [Recipe] { recipes }
    func search(text: String, limit: Int) -> [Recipe] { [] }
    func recipe(by id: RecipeID) -> Recipe? { recipes.first { $0.id == id } }
    func save(_ recipe: Recipe, ingredients: [Ingredient]) {}
    func delete(_ id: RecipeID) {}
    func ingredients(for recipeID: RecipeID) -> [Ingredient] { lines[recipeID] ?? [] }
}

struct FakeFoodRepository: FoodRepository {
    var foods: [Food] = Fixtures.foods

    func search(text: String, limit: Int) -> [Food] { [] }
    func food(by id: FoodID) -> Food? { foods.first { $0.id == id } }
    func foods(byIDs ids: [FoodID]) -> [Food] { foods.filter { ids.contains($0.id) } }
    func food(byGTIN gtin: String) -> Food? { nil }
    func upsert(_ foods: [Food]) {}
}

/// Shelves and the event log in memory; `consume` takes from the earliest best-by first, like the real store.
actor FakePantryRepository: PantryRepository {
    private(set) var stored: [PantryItem]
    private(set) var loggedEvents: [PantryEvent] = []
    /// Every `consume` call, in order.
    private(set) var consumed: [FoodAmount] = []
    private var failConsumeAfter: Int?
    private var failEventWrites = false

    init(stored: [PantryItem] = Fixtures.pantry) {
        self.stored = stored
    }

    /// Makes `consume` throw once it has succeeded `count` times.
    func setFailConsume(after count: Int?) { failConsumeAfter = count }
    func setFailEventWrites(_ value: Bool) { failEventWrites = value }

    func grams(of foodID: FoodID) -> Double {
        stored.filter { $0.foodID == foodID }.map(\.quantityGrams).reduce(0, +)
    }

    func items() -> [PantryItem] { stored }

    func upsert(_ item: PantryItem) {
        stored.removeAll { $0.id == item.id }
        stored.append(item)
    }

    func remove(_ id: PantryItemID) { stored.removeAll { $0.id == id } }

    func consume(foodID: FoodID, grams: Double) throws -> [PantryItem] {
        if let limit = failConsumeAfter, consumed.count >= limit { throw LarderError.storageFailure }
        consumed.append(FoodAmount(foodID: foodID, grams: grams))
        var remaining = grams
        var touched: [PantryItem] = []
        let order = stored.indices
            .filter { stored[$0].foodID == foodID }
            .sorted { (stored[$0].bestBy ?? .distantFuture) < (stored[$1].bestBy ?? .distantFuture) }
        for index in order where remaining > 0 {
            touched.append(stored[index])
            let taken = min(remaining, stored[index].quantityGrams)
            stored[index].quantityGrams -= taken
            remaining -= taken
        }
        stored.removeAll { $0.quantityGrams <= 0 }
        return touched
    }

    func record(_ events: [PantryEvent]) throws {
        if failEventWrites { throw LarderError.storageFailure }
        loggedEvents += events
    }

    func removeEvents(_ ids: [PantryEventID]) { loggedEvents.removeAll { ids.contains($0.id) } }

    func events(from start: Date, to end: Date) -> [PantryEvent] {
        loggedEvents.filter { $0.date >= start && $0.date < end }
    }
}

struct FakeProfileRepository: ProfileRepository {
    /// Holds a saved profile, so a save is read back while `stored` stays the test's starting value.
    final class Saved: @unchecked Sendable {
        var profile: UserProfile?
    }

    var stored: UserProfile? = Fixtures.profile()
    var storedConstraints: [DietaryConstraint] = []
    let saved = Saved()

    func profile() -> UserProfile? { saved.profile ?? stored }
    func save(_ profile: UserProfile) { saved.profile = profile }
    func constraints() -> [DietaryConstraint] { storedConstraints }
    func saveConstraints(_ constraints: [DietaryConstraint]) {}
    func targets() -> [NutrientTarget] { [] }
    func saveTargets(_ targets: [NutrientTarget]) {}
}

/// Records every explain and adjust request and answers with fixed results.
actor FakeAssistant: AssistantBackend {
    private(set) var explainRequests: [PlanExplainRequest] = []
    private(set) var adjustRequests: [AdjustRequest] = []
    private var result: Result<PlanExplanation, LarderError>
    private var adjustResult: Result<ConstraintEdit, LarderError> = .failure(.assistantUnavailable)

    init(result: Result<PlanExplanation, LarderError> = .success(PlanExplanation(summary: "A steady week.", mealNotes: []))) {
        self.result = result
    }

    func setResult(_ result: Result<PlanExplanation, LarderError>) { self.result = result }

    func setAdjustResult(_ result: Result<ConstraintEdit, LarderError>) { adjustResult = result }

    func explain(plan: PlanExplainRequest) throws -> PlanExplanation {
        explainRequests.append(plan)
        return try result.get()
    }

    func parsePantry(text: String) throws -> [ParsedPantryLine] { throw LarderError.assistantUnavailable }
    func parseRecipe(text: String, imageData: Data?) throws -> ParsedRecipe { throw LarderError.assistantUnavailable }
    func adjust(request: AdjustRequest) throws -> ConstraintEdit {
        adjustRequests.append(request)
        return try adjustResult.get()
    }
}

/// Plus and free-week state, counting each question and mark.
actor FakeEntitlements {
    let isPlus: Bool
    private(set) var freeWeekAvailable: Bool
    private(set) var freeWeekChecks = 0
    private(set) var marks = 0

    init(isPlus: Bool, freeWeekAvailable: Bool) {
        self.isPlus = isPlus
        self.freeWeekAvailable = freeWeekAvailable
    }

    func canGenerate() -> Bool {
        freeWeekChecks += 1
        return freeWeekAvailable
    }

    func markUsed() {
        marks += 1
        freeWeekAvailable = false
    }
}

/// Wires the fakes into the models under test.
struct World {
    let plans = FakePlanRepository()
    var recipes = FakeRecipeRepository()
    var foods = FakeFoodRepository()
    var pantry = FakePantryRepository()
    var profiles = FakeProfileRepository()
    let assistant: FakeAssistant
    let entitlements: FakeEntitlements
    var dates = FixedDates()

    init(
        isPlus: Bool = true,
        freeWeekAvailable: Bool = true,
        explain: Result<PlanExplanation, LarderError> = .success(PlanExplanation(summary: "A steady week.", mealNotes: []))
    ) {
        assistant = FakeAssistant(result: explain)
        entitlements = FakeEntitlements(isPlus: isPlus, freeWeekAvailable: freeWeekAvailable)
    }

    @MainActor
    func ledger() -> LedgerModel {
        let entitlements = entitlements
        return LedgerModel(
            plans: plans, recipes: recipes, foods: foods, pantry: pantry, profiles: profiles,
            assistant: assistant, dates: dates,
            isPlus: { entitlements.isPlus },
            canGenerateFreeWeek: { await entitlements.canGenerate() },
            markFreeWeekUsed: { await entitlements.markUsed() },
            calendar: Fixtures.calendar
        )
    }

    @MainActor
    func tonight() -> TonightModel {
        TonightModel(plans: plans, recipes: recipes, foods: foods, pantry: pantry, profiles: profiles, dates: dates, calendar: Fixtures.calendar)
    }

    func service() -> PlanningService {
        PlanningService(plans: plans, recipes: recipes, foods: foods, pantry: pantry, profiles: profiles, dates: dates, calendar: Fixtures.calendar)
    }

    /// Seeds an active plan with `meals` and returns it.
    @MainActor @discardableResult
    func seed(_ plan: MealPlan = Fixtures.plan(), meals: (MealPlan) -> [PlannedMeal]) async -> (MealPlan, [PlannedMeal]) {
        let built = meals(plan)
        await plans.seed(plan, meals: built)
        return (plan, built)
    }
}
