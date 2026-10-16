import Foundation

/// A recipe with everything the planner needs precomputed once.
public struct RecipeCandidate: Hashable, Sendable {
    public var recipe: Recipe
    public var ingredients: [Ingredient]
    public var nutrition: RecipeNutrition
    /// Grams per food group in the whole recipe (all servings), garnish excluded.
    public var foodGroupsGrams: [FoodGroup: Double]

    /// Creates a candidate.
    public init(recipe: Recipe, ingredients: [Ingredient], nutrition: RecipeNutrition, foodGroupsGrams: [FoodGroup: Double]) {
        self.recipe = recipe
        self.ingredients = ingredients
        self.nutrition = nutrition
        self.foodGroupsGrams = foodGroupsGrams
    }

    /// Prep plus cook minutes.
    public var totalMinutes: Int { recipe.prepMinutes + recipe.cookMinutes }

    /// Whether the recipe can fill `slot`; a recipe without meal types fits any slot.
    public func fits(_ slot: MealType) -> Bool {
        recipe.tags.mealTypes.isEmpty || recipe.tags.mealTypes.contains(slot)
    }
}

/// Builds planner candidates from stored recipes.
public enum CandidateBuilder {
    /// One candidate per recipe, in input order; a recipe without ingredient lines gets an empty list.
    public static func build(
        recipes: [Recipe],
        ingredients: [RecipeID: [Ingredient]],
        foods: [FoodID: Food]
    ) -> [RecipeCandidate] {
        let calculator = NutritionCalculator()
        return recipes.map { recipe in
            let lines = ingredients[recipe.id] ?? []
            var groups: [FoodGroup: Double] = [:]
            for line in lines where !line.isGarnish {
                guard let food = line.foodID.flatMap({ foods[$0] }),
                      let grams = IngredientGrams.resolve(line, food: food), grams.isFinite, grams > 0
                else { continue }
                groups[food.foodGroup, default: 0] += grams
            }
            return RecipeCandidate(
                recipe: recipe,
                ingredients: lines,
                nutrition: calculator.nutrition(for: recipe, ingredients: lines, foods: foods),
                foodGroupsGrams: groups
            )
        }
    }
}
