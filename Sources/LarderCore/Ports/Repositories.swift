import Foundation

/// Reads and writes foods.
public protocol FoodRepository: Sendable {
    /// Foods whose names match `text`, best match first.
    func search(text: String, limit: Int) async throws -> [Food]
    /// The food with `id`, or `nil` if there is none.
    func food(by id: FoodID) async throws -> Food?
    /// The foods with the given identifiers; unknown identifiers are skipped.
    func foods(byIDs ids: [FoodID]) async throws -> [Food]
    /// Inserts or replaces foods by identifier.
    func upsert(_ foods: [Food]) async throws
}

/// Reads and writes recipes and their ingredient lines.
public protocol RecipeRepository: Sendable {
    /// Every recipe.
    func all() async throws -> [Recipe]
    /// Recipes matching `text`, best match first.
    func search(text: String, limit: Int) async throws -> [Recipe]
    /// The recipe with `id`, or `nil` if there is none.
    func recipe(by id: RecipeID) async throws -> Recipe?
    /// Inserts or replaces a recipe together with its full set of ingredient lines.
    func save(_ recipe: Recipe, ingredients: [Ingredient]) async throws
    /// Deletes a recipe and its ingredient lines.
    func delete(_ id: RecipeID) async throws
    /// The ingredient lines of a recipe, in recipe order.
    func ingredients(for recipeID: RecipeID) async throws -> [Ingredient]
}

/// Reads and writes the user's shelves.
public protocol PantryRepository: Sendable {
    /// Every pantry item.
    func items() async throws -> [PantryItem]
    /// Inserts or replaces a pantry item by identifier.
    func upsert(_ item: PantryItem) async throws
    /// Removes a pantry item.
    func remove(_ id: PantryItemID) async throws
    /// Deducts `grams` of a food from the shelves, earliest best-by first.
    func consume(foodID: FoodID, grams: Double) async throws
}

/// Reads and writes meal plans and their meals.
public protocol PlanRepository: Sendable {
    /// The active plan, if any.
    func currentPlan() async throws -> MealPlan?
    /// Every plan, newest first.
    func plans() async throws -> [MealPlan]
    /// Inserts or replaces a plan together with its full set of meals.
    func save(_ plan: MealPlan, meals: [PlannedMeal]) async throws
    /// The meals of a plan, in date and slot order.
    func meals(for planID: MealPlanID) async throws -> [PlannedMeal]
    /// Replaces one planned meal.
    func updateMeal(_ meal: PlannedMeal) async throws
}

/// Reads and writes the local-only profile, constraints and nutrient targets.
public protocol ProfileRepository: Sendable {
    /// The profile, or `nil` before onboarding.
    func profile() async throws -> UserProfile?
    /// Replaces the profile.
    func save(_ profile: UserProfile) async throws
    /// Every dietary constraint.
    func constraints() async throws -> [DietaryConstraint]
    /// Replaces the full set of dietary constraints.
    func saveConstraints(_ constraints: [DietaryConstraint]) async throws
    /// Every nutrient target.
    func targets() async throws -> [NutrientTarget]
    /// Replaces the full set of nutrient targets.
    func saveTargets(_ targets: [NutrientTarget]) async throws
}

/// Supplies the current time so date-dependent logic is testable.
public protocol DateProvider: Sendable {
    /// The current date and time.
    var now: Date { get }
}
