#if DEBUG
import Foundation
import LarderCore

/// An in-memory kitchen for previews: every repository, a fixed clock and an offline assistant.
actor PreviewStore: PlanRepository, RecipeRepository, FoodRepository, PantryRepository, ProfileRepository {
    private var storedPlans: [MealPlan] = []
    private var storedMeals: [PlannedMeal] = []
    private let recipeList: [Recipe]
    private let lines: [RecipeID: [Ingredient]]
    private let foodList: [Food]
    private var shelves: [PantryItem]
    private var storedProfile: UserProfile?

    init(
        recipes: [Recipe],
        lines: [RecipeID: [Ingredient]],
        foods: [Food],
        pantry: [PantryItem],
        profile: UserProfile?,
        plans: [MealPlan],
        meals: [PlannedMeal]
    ) {
        storedPlans = plans
        storedMeals = meals
        recipeList = recipes
        self.lines = lines
        foodList = foods
        shelves = pantry
        storedProfile = profile
    }

    func currentPlan() -> MealPlan? { storedPlans.first { $0.status == .active } }
    func plans() -> [MealPlan] { storedPlans.sorted { $0.startDate > $1.startDate } }
    func save(_ plan: MealPlan, meals: [PlannedMeal]) {
        storedPlans.removeAll { $0.id == plan.id }
        storedPlans.append(plan)
        storedMeals.removeAll { $0.planID == plan.id }
        storedMeals += meals
    }
    func meals(for planID: MealPlanID) -> [PlannedMeal] { storedMeals.filter { $0.planID == planID } }
    func updateMeal(_ meal: PlannedMeal) {
        if let index = storedMeals.firstIndex(where: { $0.id == meal.id }) { storedMeals[index] = meal }
    }

    func all() -> [Recipe] { recipeList }
    func search(text: String, limit: Int) -> [Recipe] { [] }
    func recipe(by id: RecipeID) -> Recipe? { recipeList.first { $0.id == id } }
    func save(_ recipe: Recipe, ingredients: [Ingredient]) {}
    func delete(_ id: RecipeID) {}
    func ingredients(for recipeID: RecipeID) -> [Ingredient] { lines[recipeID] ?? [] }

    func search(text: String, limit: Int) -> [Food] { [] }
    func food(by id: FoodID) -> Food? { foodList.first { $0.id == id } }
    func foods(byIDs ids: [FoodID]) -> [Food] { foodList.filter { ids.contains($0.id) } }
    func food(byGTIN gtin: String) -> Food? { nil }
    func upsert(_ foods: [Food]) {}

    func items() -> [PantryItem] { shelves }
    func upsert(_ item: PantryItem) { shelves.append(item) }
    func remove(_ id: PantryItemID) { shelves.removeAll { $0.id == id } }
    func consume(foodID: FoodID, grams: Double) -> [PantryItem] { [] }
    func record(_ events: [PantryEvent]) {}
    func removeEvents(_ ids: [PantryEventID]) {}
    func events(from start: Date, to end: Date) -> [PantryEvent] { [] }

    func profile() -> UserProfile? { storedProfile }
    func save(_ profile: UserProfile) { storedProfile = profile }
    func constraints() -> [DietaryConstraint] { [] }
    func saveConstraints(_ constraints: [DietaryConstraint]) {}
    func targets() -> [NutrientTarget] { [] }
    func saveTargets(_ targets: [NutrientTarget]) {}
}

/// The assistant offline, as it is before consent.
struct PreviewAssistant: AssistantBackend {
    func explain(plan: PlanExplainRequest) async throws -> PlanExplanation { throw LarderError.consentRequired }
    func parsePantry(text: String) async throws -> [ParsedPantryLine] { [] }
    func parseRecipe(text: String, imageData: Data?) async throws -> ParsedRecipe { throw LarderError.consentRequired }
    func adjust(request: AdjustRequest) async throws -> ConstraintEdit { throw LarderError.consentRequired }
}

struct PreviewClock: DateProvider {
    let now: Date
}

/// Sample recipes and shelves for previews.
enum PreviewKitchen {
    static func food(_ name: String, _ group: FoodGroup, kcal: Double, protein: Double, fibre: Double) -> Food {
        Food(
            name: name,
            source: .seedApproximate,
            nutrientsPer100g: Nutrients(energyKcal: kcal, proteinG: protein, fiberG: fibre, sodiumMg: 50),
            foodGroup: group
        )
    }

    static func store(empty: Bool = false, withPlan: Bool = false) -> PreviewStore {
        let now = Date.now
        let spinach = food("Spinach", .produce, kcal: 23, protein: 2.9, fibre: 2.2)
        let chickpeas = food("Chickpeas", .legumes, kcal: 139, protein: 7, fibre: 7.6)
        let rice = food("Rice", .grains, kcal: 130, protein: 2.7, fibre: 0.4)
        let chicken = food("Chicken thigh", .protein, kcal: 177, protein: 24, fibre: 0)
        let tomato = food("Tomatoes", .produce, kcal: 18, protein: 0.9, fibre: 1.2)
        let lentils = food("Red lentils", .legumes, kcal: 116, protein: 9, fibre: 7.9)
        let foods = [spinach, chickpeas, rice, chicken, tomato, lentils]

        let dishes: [(String, String, Int, Int, [(Food, Double)])] = [
            ("Chickpea and spinach curry", "Indian", 8, 35, [(chickpeas, 800), (spinach, 300), (tomato, 600), (rice, 500)]),
            ("Chicken and rice traybake", "British", 4, 40, [(chicken, 600), (rice, 300), (tomato, 300)]),
            ("Red lentil soup", "Moroccan", 4, 30, [(lentils, 400), (tomato, 600), (spinach, 100)]),
            ("Spinach fried rice", "Chinese", 2, 20, [(rice, 300), (spinach, 150)]),
        ]
        var recipes: [Recipe] = []
        var lines: [RecipeID: [Ingredient]] = [:]
        for (title, cuisine, servings, minutes, parts) in dishes {
            let recipe = Recipe(
                title: title, origin: .generated, servings: servings, prepMinutes: 10, cookMinutes: minutes - 10,
                tags: RecipeTags(cuisine: cuisine, mealTypes: [.dinner])
            )
            recipes.append(recipe)
            lines[recipe.id] = parts.map { food, grams in
                Ingredient(recipeID: recipe.id, rawText: food.name, quantity: grams, unit: .gram, foodID: food.id, gramsResolved: grams, matchConfidence: 1)
            }
        }
        let pantry = empty ? [] : [
            PantryItem(foodID: spinach.id, rawName: "Spinach", quantityGrams: 300, location: .fridge,
                       bestBy: now.addingTimeInterval(2 * 86_400), source: .manual, addedOn: now),
            PantryItem(foodID: rice.id, rawName: "Rice", quantityGrams: 1_000, location: .pantry, source: .manual, addedOn: now),
            PantryItem(foodID: chickpeas.id, rawName: "Chickpeas", quantityGrams: 800, location: .pantry, source: .manual, addedOn: now),
        ]
        let profile = UserProfile(
            birthYear: 1990, heightCm: 170, activityLevel: .moderate, goal: .lessWaste, householdSize: 2,
            currencyCode: "USD", maxCookMinutes: 45
        )
        let start = Calendar.current.startOfDay(for: now)
        let plan = MealPlan(startDate: start, days: 7, constraintsSnapshot: "", solverVersion: "preview", seed: 1, status: .active)
        let cooked = PlannedMeal(
            planID: plan.id, date: start, slot: .dinner, recipeID: recipes[0].id, servings: 4, status: .cooked,
            reasonCodes: [.pantryOverlap(count: 3)]
        )
        let meals = [
            cooked,
            PlannedMeal(
                planID: plan.id, date: day(1, from: start), slot: .dinner, recipeID: recipes[0].id, servings: 2,
                leftoverOf: cooked.id, reasonCodes: [.leftoverOf(meal: cooked.id)]
            ),
            PlannedMeal(planID: plan.id, date: day(2, from: start), slot: .dinner, recipeID: recipes[1].id, servings: 2, isLocked: true),
            PlannedMeal(planID: plan.id, date: day(3, from: start), slot: .dinner, recipeID: recipes[2].id, servings: 2, status: .skipped),
            PlannedMeal(
                planID: plan.id, date: day(5, from: start), slot: .dinner, recipeID: recipes[3].id, servings: 2,
                reasonCodes: [.quick(minutes: 20), .varietyCuisine(cuisine: "Chinese")]
            ),
        ]
        return PreviewStore(
            recipes: recipes, lines: lines, foods: foods, pantry: pantry, profile: profile,
            plans: withPlan ? [plan] : [], meals: withPlan ? meals : []
        )
    }

    private static func day(_ offset: Int, from start: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: start) ?? start
    }

    @MainActor
    static func ledgerModel(withPlan: Bool = true, isPlus: Bool = true) -> LedgerModel {
        let store = store(withPlan: withPlan)
        return LedgerModel(
            plans: store, recipes: store, foods: store, pantry: store, profiles: store,
            assistant: PreviewAssistant(), dates: PreviewClock(now: .now),
            isPlus: { isPlus }, canGenerateFreeWeek: { true }, markFreeWeekUsed: {}
        )
    }

    @MainActor
    static func tonightModel(empty: Bool = false) -> TonightModel {
        let store = store(empty: empty)
        return TonightModel(plans: store, recipes: store, foods: store, pantry: store, profiles: store, dates: PreviewClock(now: .now))
    }
}
#endif
