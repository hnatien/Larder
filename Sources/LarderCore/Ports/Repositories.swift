import Foundation

/// Reads and writes foods.
public protocol FoodRepository: Sendable {
    /// Foods whose names match `text`, best match first.
    func search(text: String, limit: Int) async throws -> [Food]
    /// The food with `id`, or `nil` if there is none.
    func food(by id: FoodID) async throws -> Food?
    /// The foods with the given identifiers; unknown identifiers are skipped.
    func foods(byIDs ids: [FoodID]) async throws -> [Food]
    /// The food whose barcode is `gtin` in any of its spellings (see `GTIN.spellings(of:)`), or `nil`.
    func food(byGTIN gtin: String) async throws -> Food?
    /// Inserts or replaces foods by identifier.
    func upsert(_ foods: [Food]) async throws
}

extension FoodRepository {
    /// The food an item the user named is, if any: the top search hit, accepted only when its name starts with the
    /// same word as `name`, ignoring case and a plural s.
    public func match(forItemNamed name: String) async throws -> Food? {
        guard let word = Self.firstWord(of: name),
            let hit = try await search(text: name, limit: 1).first,
            Self.firstWord(of: hit.name) == word
        else { return nil }
        return hit
    }

    /// The first word, lowercased, with a plural "s" dropped so "onions" meets "Onion, raw".
    private static func firstWord(of text: String) -> String? {
        text.split(whereSeparator: { !$0.isLetter }).first.map { word in
            let lowered = word.lowercased()
            return lowered.count > 3 && lowered.hasSuffix("s") ? String(lowered.dropLast()) : lowered
        }
    }
}

/// Reads and writes recipes and their ingredient lines.
public protocol RecipeRepository: Sendable {
    /// Every recipe the user has not hidden.
    func all() async throws -> [Recipe]
    /// Recipes matching `text`, best match first, leaving out hidden ones.
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

/// Keeps which recipes the user marked as a favourite or hid from the library. A hidden recipe stays readable by
/// identifier, so plans that use it still show it, but `RecipeRepository.all()` and `search` leave it out.
public protocol RecipeMarkRepository: Sendable {
    /// The recipes marked as favourites.
    func favourites() async throws -> Set<RecipeID>
    /// Marks or unmarks a recipe as a favourite.
    func setFavourite(_ id: RecipeID, _ isFavourite: Bool) async throws
    /// The hidden recipes, by title.
    func hiddenRecipes() async throws -> [Recipe]
    /// Hides a recipe from the library and the planner, or shows it again.
    func setHidden(_ id: RecipeID, _ isHidden: Bool) async throws
}

/// Keeps recipe photos as files on the device.
public protocol RecipePhotoStore: Sendable {
    /// Writes `jpeg` as the photo of `recipeID`, replacing any earlier one, and returns its file name.
    func save(_ jpeg: Data, for recipeID: RecipeID) async throws -> String
    /// Deletes the photo with `fileName`; a missing file is not an error.
    func delete(_ fileName: String) async throws
}

/// Reads and writes the user's shelves.
public protocol PantryRepository: Sendable {
    /// Every pantry item.
    func items() async throws -> [PantryItem]
    /// Inserts or replaces a pantry item by identifier.
    func upsert(_ item: PantryItem) async throws
    /// Removes a pantry item.
    func remove(_ id: PantryItemID) async throws
    /// Deducts `grams` of a food from the shelves, earliest best-by first, and returns the items it changed or
    /// removed as they were before, so the deduction can be undone.
    @discardableResult
    func consume(foodID: FoodID, grams: Double) async throws -> [PantryItem]
    /// Adds events to the log of food leaving the shelves.
    func record(_ events: [PantryEvent]) async throws
    /// Removes events from the log, when the action that wrote them is undone.
    func removeEvents(_ ids: [PantryEventID]) async throws
    /// Logged events dated from `start` up to but not including `end`, oldest first.
    func events(from start: Date, to end: Date) async throws -> [PantryEvent]
}

/// Keeps the grocery basket and the hand-written items between launches.
public protocol GroceryBasketRepository: Sendable {
    /// Hand-written items, in the order they were added.
    func manualItems() async throws -> [ManualItem]
    /// Adds a hand-written item after the others, or replaces it by identifier in its place.
    func saveManualItem(_ item: ManualItem) async throws
    /// Removes a hand-written item and its basket line.
    func removeManualItem(_ id: ManualItemID) async throws
    /// Basket lines, in the order they were ticked.
    func basketLines() async throws -> [BasketLine]
    /// Adds a basket line, or replaces the one with the same key.
    func saveBasketLine(_ line: BasketLine) async throws
    /// Removes the basket line with `key`; a missing line is not an error.
    func removeBasketLine(_ key: GroceryItemKey) async throws
    /// Empties the basket and removes the hand-written items that were in it.
    func clearBasket() async throws
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
