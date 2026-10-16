import LarderCore

/// A recipe with everything its detail screen shows.
public nonisolated struct RecipeDetail: Sendable {
    public var recipe: Recipe
    public var ingredients: [Ingredient]
    public var nutrition: RecipeNutrition
    public var verdict: FilterVerdict
    /// Whether the profile asks to see nutrient numbers.
    public var showsNumbers: Bool

    /// Creates a detail.
    public init(
        recipe: Recipe,
        ingredients: [Ingredient],
        nutrition: RecipeNutrition,
        verdict: FilterVerdict,
        showsNumbers: Bool
    ) {
        self.recipe = recipe
        self.ingredients = ingredients
        self.nutrition = nutrition
        self.verdict = verdict
        self.showsNumbers = showsNumbers
    }

    /// The ingredient lines for `servings` servings.
    public func scaled(to servings: Int) -> [Ingredient] {
        IngredientScaler.scale(ingredients: ingredients, from: recipe.servings, to: servings)
    }
}
