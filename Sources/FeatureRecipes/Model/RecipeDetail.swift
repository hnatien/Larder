import LarderCore

/// A recipe with everything its detail screen shows.
public nonisolated struct RecipeDetail: Sendable {
    public var recipe: Recipe
    public var ingredients: [Ingredient]
    public var nutrition: RecipeNutrition
    public var verdict: FilterVerdict
    /// Whether the profile asks to see nutrient numbers.
    public var showsNumbers: Bool
    /// The foods on the shelves, so each line can say whether you have it.
    public var pantryFoods: Set<FoodID>
    /// Whether the user has set any allergy, diet or health rule, so a pass is worth saying.
    public var hasConstraints: Bool

    /// Creates a detail.
    public init(
        recipe: Recipe,
        ingredients: [Ingredient],
        nutrition: RecipeNutrition,
        verdict: FilterVerdict,
        showsNumbers: Bool,
        pantryFoods: Set<FoodID> = [],
        hasConstraints: Bool = false
    ) {
        self.recipe = recipe
        self.ingredients = ingredients
        self.nutrition = nutrition
        self.verdict = verdict
        self.showsNumbers = showsNumbers
        self.pantryFoods = pantryFoods
        self.hasConstraints = hasConstraints
    }

    /// Whether a line's food is on the shelves: `true` or `false` for a line matched to a food, `nil` when the line
    /// names nothing Larder knows, so it can say neither.
    public func isInPantry(_ ingredient: Ingredient) -> Bool? {
        ingredient.foodID.map(pantryFoods.contains)
    }

    /// The lines to buy before cooking: matched foods that are not on the shelves, leaving out optional lines and
    /// garnish.
    public func missing(at servings: Int) -> [Ingredient] {
        scaled(to: servings).filter { !$0.isOptional && !$0.isGarnish && isInPantry($0) == false }
    }

    /// The ingredient lines for `servings` servings.
    public func scaled(to servings: Int) -> [Ingredient] {
        IngredientScaler.scale(ingredients: ingredients, from: recipe.servings, to: servings)
    }
}
