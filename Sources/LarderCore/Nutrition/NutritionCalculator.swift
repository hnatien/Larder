import Foundation

/// Nutrients of a recipe and how much of it the food data covers.
public struct RecipeNutrition: Hashable, Sendable {
    /// Nutrients in one serving.
    public var perServing: Nutrients
    /// Nutrients in the whole recipe.
    public var perRecipe: Nutrients
    /// Fraction (0...1) of resolved ingredient grams whose food has energy data; 0 when nothing resolved.
    public var coverage: Double
    /// Non-garnish ingredients left out because they have no food or no gram amount.
    public var unresolved: [IngredientID]

    /// Creates a recipe nutrition summary.
    public init(perServing: Nutrients, perRecipe: Nutrients, coverage: Double, unresolved: [IngredientID]) {
        self.perServing = perServing
        self.perRecipe = perRecipe
        self.coverage = coverage
        self.unresolved = unresolved
    }
}

/// Computes recipe nutrients from ingredient grams and per-100 g food data.
public struct NutritionCalculator: Sendable {
    /// Creates a calculator.
    public init() {}

    /// Nutrients for `recipe`; garnish is skipped, optional ingredients count, a recipe with fewer than one serving counts as one.
    public func nutrition(for recipe: Recipe, ingredients: [Ingredient], foods: [FoodID: Food]) -> RecipeNutrition {
        var total = Nutrients()
        var resolvedGrams = 0.0
        var gramsWithEnergy = 0.0
        var unresolved: [IngredientID] = []

        for ingredient in ingredients where !ingredient.isGarnish {
            guard let food = ingredient.foodID.flatMap({ foods[$0] }),
                  let grams = IngredientGrams.resolve(ingredient, food: food)
            else {
                unresolved.append(ingredient.id)
                continue
            }
            total = total + food.nutrientsPer100g.scaled(by: grams / 100)
            resolvedGrams += grams
            if food.nutrientsPer100g.energyKcal != nil {
                gramsWithEnergy += grams
            }
        }

        return RecipeNutrition(
            perServing: scaled(total, servings: recipe.servings, to: 1),
            perRecipe: total,
            coverage: resolvedGrams > 0 ? gramsWithEnergy / resolvedGrams : 0,
            unresolved: unresolved
        )
    }

    /// Rescales nutrients for `servings` servings to `target` servings; fewer than one source serving counts as one, a negative target as zero.
    public func scaled(_ nutrients: Nutrients, servings: Int, to target: Int) -> Nutrients {
        nutrients.scaled(by: Double(max(target, 0)) / Double(max(servings, 1)))
    }
}
