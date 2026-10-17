import Foundation
import LarderCore

struct StoreFailure: Error {}

struct FixedDates: DateProvider {
    var now: Date { Date(timeIntervalSince1970: 1_800_000_000) }
}

/// In-memory stand-in for every repository the grocery model reads or writes.
actor FakeStore: PlanRepository, RecipeRepository, FoodRepository, PantryRepository {
    var plan: MealPlan?
    var plannedMeals: [PlannedMeal] = []
    var recipeList: [Recipe] = []
    var ingredientLines: [RecipeID: [Ingredient]] = [:]
    var foodList: [Food] = []
    var shelves: [PantryItem] = []
    var failReads = false
    var failPantryWrites = false
    private(set) var upserts: [PantryItem] = []
    private(set) var removals: [PantryItemID] = []

    func setFailReads(_ value: Bool) { failReads = value }
    func setFailPantryWrites(_ value: Bool) { failPantryWrites = value }

    func seed(plan: MealPlan?, meals: [PlannedMeal], recipes: [Recipe], ingredients: [RecipeID: [Ingredient]], foods: [Food], pantry: [PantryItem] = []) {
        self.plan = plan
        plannedMeals = meals
        recipeList = recipes
        ingredientLines = ingredients
        foodList = foods
        shelves = pantry
    }

    func currentPlan() async throws -> MealPlan? {
        if failReads { throw StoreFailure() }
        return plan
    }
    func plans() async throws -> [MealPlan] { plan.map { [$0] } ?? [] }
    func save(_ plan: MealPlan, meals: [PlannedMeal]) async throws {}
    func meals(for planID: MealPlanID) async throws -> [PlannedMeal] { plannedMeals }
    func updateMeal(_ meal: PlannedMeal) async throws {}

    func all() async throws -> [Recipe] { recipeList }
    func search(text: String, limit: Int) async throws -> [Recipe] { [] }
    func recipe(by id: RecipeID) async throws -> Recipe? { recipeList.first { $0.id == id } }
    func save(_ recipe: Recipe, ingredients: [Ingredient]) async throws {}
    func delete(_ id: RecipeID) async throws {}
    func ingredients(for recipeID: RecipeID) async throws -> [Ingredient] { ingredientLines[recipeID] ?? [] }

    func search(text: String, limit: Int) async throws -> [Food] {
        Array(foodList.filter { $0.name.localizedCaseInsensitiveContains(text) }.prefix(limit))
    }
    func food(by id: FoodID) async throws -> Food? { foodList.first { $0.id == id } }
    func foods(byIDs ids: [FoodID]) async throws -> [Food] { foodList.filter { ids.contains($0.id) } }
    func food(byGTIN gtin: String) async throws -> Food? { nil }
    func upsert(_ foods: [Food]) async throws {}

    func items() async throws -> [PantryItem] { shelves }
    func upsert(_ item: PantryItem) async throws {
        if failPantryWrites { throw StoreFailure() }
        upserts.append(item)
        shelves.removeAll { $0.id == item.id }
        shelves.append(item)
    }
    func remove(_ id: PantryItemID) async throws {
        if failPantryWrites { throw StoreFailure() }
        removals.append(id)
        shelves.removeAll { $0.id == id }
    }
    func consume(foodID: FoodID, grams: Double) async throws -> [PantryItem] { [] }
    func record(_ events: [PantryEvent]) async throws {}
    func removeEvents(_ ids: [PantryEventID]) async throws {}
    func events(from start: Date, to end: Date) async throws -> [PantryEvent] { [] }
}

/// The grocery basket in memory; several models over one instance behave like relaunches over one store.
actor FakeBasket: GroceryBasketRepository {
    private(set) var storedManualItems: [ManualItem] = []
    private(set) var storedLines: [BasketLine] = []
    private var failWrites = false

    func setFailWrites(_ value: Bool) { failWrites = value }

    func manualItems() -> [ManualItem] { storedManualItems }

    func saveManualItem(_ item: ManualItem) throws {
        if failWrites { throw StoreFailure() }
        if let index = storedManualItems.firstIndex(where: { $0.id == item.id }) {
            storedManualItems[index] = item
        } else {
            storedManualItems.append(item)
        }
    }

    func removeManualItem(_ id: ManualItemID) throws {
        if failWrites { throw StoreFailure() }
        storedManualItems.removeAll { $0.id == id }
        storedLines.removeAll { $0.key == GroceryItemKey(identity: .manual(id), unit: nil) }
    }

    func basketLines() -> [BasketLine] { storedLines }

    func saveBasketLine(_ line: BasketLine) throws {
        if failWrites { throw StoreFailure() }
        if let index = storedLines.firstIndex(where: { $0.key == line.key }) {
            storedLines[index] = line
        } else {
            storedLines.append(line)
        }
    }

    func removeBasketLine(_ key: GroceryItemKey) throws {
        if failWrites { throw StoreFailure() }
        storedLines.removeAll { $0.key == key }
    }

    func clearBasket() throws {
        if failWrites { throw StoreFailure() }
        let ticked = Set(storedLines.map(\.key))
        storedManualItems.removeAll { ticked.contains(GroceryItemKey($0)) }
        storedLines = []
    }
}
