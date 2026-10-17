#if DEBUG
import Foundation
import LarderCore

/// In-memory repositories and sample recipes for SwiftUI previews.
actor PreviewStore: RecipeRepository, RecipePhotoStore, FoodRepository, ProfileRepository, PantryRepository, RecipeMarkRepository {
    private var recipeList: [Recipe]
    private var lines: [RecipeID: [Ingredient]]
    private let foodList: [Food]

    init(recipes: [Recipe] = PreviewData.recipes, ingredients: [RecipeID: [Ingredient]] = PreviewData.ingredients) {
        recipeList = recipes
        lines = ingredients
        foodList = PreviewData.foods
    }

    func all() -> [Recipe] { recipeList }
    func search(text: String, limit: Int) -> [Recipe] {
        Array(recipeList.filter { $0.title.localizedCaseInsensitiveContains(text) }.prefix(limit))
    }
    func recipe(by id: RecipeID) -> Recipe? { recipeList.first { $0.id == id } }
    func save(_ recipe: Recipe, ingredients: [Ingredient]) {
        recipeList.removeAll { $0.id == recipe.id }
        recipeList.append(recipe)
        lines[recipe.id] = ingredients
    }
    func delete(_ id: RecipeID) { recipeList.removeAll { $0.id == id } }
    func ingredients(for recipeID: RecipeID) -> [Ingredient] { lines[recipeID] ?? [] }
    func save(_ jpeg: Data, for recipeID: RecipeID) -> String { recipeID.rawValue.uuidString + ".jpg" }
    func delete(_ fileName: String) {}

    func search(text: String, limit: Int) -> [Food] {
        Array(foodList.filter { $0.name.localizedCaseInsensitiveContains(text) }.prefix(limit))
    }
    func food(by id: FoodID) -> Food? { foodList.first { $0.id == id } }
    func foods(byIDs ids: [FoodID]) -> [Food] { foodList.filter { ids.contains($0.id) } }
    func food(byGTIN gtin: String) -> Food? { nil }
    func upsert(_ foods: [Food]) {}

    func profile() -> UserProfile? {
        UserProfile(
            birthYear: 1990, heightCm: 170, activityLevel: .moderate, goal: .eatBetter,
            householdSize: 2, currencyCode: "USD", maxCookMinutes: 45, showsNumbers: true
        )
    }
    func save(_ profile: UserProfile) {}
    func constraints() -> [DietaryConstraint] { [] }
    func saveConstraints(_ constraints: [DietaryConstraint]) {}
    func targets() -> [NutrientTarget] { [] }
    func saveTargets(_ targets: [NutrientTarget]) {}

    func items() -> [PantryItem] {
        [PantryItem(foodID: PreviewData.chickpeas.id, rawName: "Chickpeas", quantityGrams: 480, location: .pantry, source: .manual, addedOn: .now)]
    }
    func upsert(_ item: PantryItem) {}
    func remove(_ id: PantryItemID) {}
    func consume(foodID: FoodID, grams: Double) -> [PantryItem] { [] }
    func record(_ events: [PantryEvent]) {}
    func removeEvents(_ ids: [PantryEventID]) {}
    func events(from start: Date, to end: Date) -> [PantryEvent] { [] }

    func favourites() -> Set<RecipeID> { [PreviewData.chanaMasala.id] }
    func setFavourite(_ id: RecipeID, _ isFavourite: Bool) {}
    func hiddenRecipes() -> [Recipe] { [] }
    func setHidden(_ id: RecipeID, _ isHidden: Bool) {}
}

/// An assistant that is never reachable.
struct PreviewAssistant: AssistantBackend {
    func explain(plan: PlanExplainRequest) async throws -> PlanExplanation { throw LarderError.assistantUnavailable }
    func parsePantry(text: String) async throws -> [ParsedPantryLine] { throw LarderError.assistantUnavailable }
    func parseRecipe(text: String, imageData: Data?) async throws -> ParsedRecipe { throw LarderError.assistantUnavailable }
    func adjust(request: AdjustRequest) async throws -> ConstraintEdit { throw LarderError.assistantUnavailable }
}

/// Sample data shared by the previews.
nonisolated enum PreviewData {
    static let chickpeas = Food(
        name: "Chickpeas, canned", source: .seedApproximate,
        nutrientsPer100g: Nutrients(energyKcal: 120, proteinG: 7, fiberG: 6, sodiumMg: 250),
        foodGroup: .legumes
    )
    static let foods = [chickpeas]

    static let chanaMasala = Recipe(
        title: "Weeknight chana masala", origin: .userImport,
        sourceURL: URL(string: "https://example.com/chana-masala"),
        servings: 4, prepMinutes: 10, cookMinutes: 25,
        steps: [
            RecipeStep(text: "Warm the oil over medium heat and fry the garlic until soft."),
            RecipeStep(text: "Add the chickpeas and simmer for 15 minutes.", timerSeconds: 900),
            RecipeStep(text: "Stir through the spinach and serve."),
        ],
        tags: RecipeTags(cuisine: "Indian", mealTypes: [.dinner], dietFlags: [.vegan, .vegetarian])
    )
    static let porridge = Recipe(
        title: "Oat porridge", origin: .generated, servings: 2, prepMinutes: 2, cookMinutes: 8,
        steps: [RecipeStep(text: "Simmer the oats in milk for 8 minutes.", timerSeconds: 480)],
        tags: RecipeTags(mealTypes: [.breakfast], dietFlags: [.vegetarian])
    )
    static let recipes = [chanaMasala, porridge]

    static let ingredients: [RecipeID: [Ingredient]] = [
        chanaMasala.id: [
            Ingredient(recipeID: chanaMasala.id, rawText: "2 tbsp olive oil", quantity: 2, unit: .tablespoon),
            Ingredient(recipeID: chanaMasala.id, rawText: "2 cloves garlic, minced", quantity: 2, unit: .clove),
            Ingredient(
                recipeID: chanaMasala.id, rawText: "2 cans chickpeas, drained", quantity: 480, unit: .gram,
                foodID: chickpeas.id, matchConfidence: 1
            ),
            Ingredient(recipeID: chanaMasala.id, rawText: "100 g spinach", quantity: 100, unit: .gram),
        ],
        porridge.id: [
            Ingredient(recipeID: porridge.id, rawText: "1 cup rolled oats", quantity: 1, unit: .cup),
            Ingredient(recipeID: porridge.id, rawText: "2 cups milk", quantity: 2, unit: .cup),
        ],
    ]

    @MainActor static func model() -> RecipesModel {
        let store = PreviewStore()
        return RecipesModel(
            recipes: store, photos: store, foods: store, profile: store, pantry: store, marks: store,
            assistant: PreviewAssistant(), isPlus: { false }
        )
    }
}
#endif
