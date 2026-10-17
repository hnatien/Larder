import Foundation

/// Grams of one food.
public struct FoodAmount: Hashable, Sendable {
    public var foodID: FoodID
    public var grams: Double

    /// Creates an amount.
    public init(foodID: FoodID, grams: Double) {
        self.foodID = foodID
        self.grams = grams
    }
}

/// What cooking takes from the shelves.
public enum CookingDraw {
    /// The food cooking `meal` uses; a leftover uses none, since its food left the shelves with the meal it came from.
    public static func amounts(
        cooking meal: PlannedMeal,
        recipe: Recipe,
        ingredients: [Ingredient],
        foods: [FoodID: Food]
    ) -> [FoodAmount] {
        guard meal.leftoverOf == nil, meal.recipeID == recipe.id else { return [] }
        return amounts(recipe: recipe, servings: meal.servings, ingredients: ingredients, foods: foods)
    }

    /// The food cooking `recipe` for `servings` uses, one amount per food in recipe order.
    ///
    /// Optional and garnish lines are left out, since the cook may have done without them, as are lines with no
    /// matched food or no weighable amount. Lines scale by `servings` over the recipe's servings, and lines of the same
    /// food add up.
    public static func amounts(recipe: Recipe, servings: Int, ingredients: [Ingredient], foods: [FoodID: Food]) -> [FoodAmount] {
        guard servings > 0 else { return [] }
        let factor = Double(servings) / Double(max(recipe.servings, 1))
        var order: [FoodID] = []
        var totals: [FoodID: Double] = [:]
        for ingredient in ingredients where ingredient.recipeID == recipe.id && !ingredient.isOptional && !ingredient.isGarnish {
            guard let foodID = ingredient.foodID,
                  let grams = IngredientGrams.resolve(ingredient, food: foods[foodID]),
                  grams > 0
            else { continue }
            if totals[foodID] == nil { order.append(foodID) }
            totals[foodID, default: 0] += grams * factor
        }
        return order.compactMap { id in totals[id].map { FoodAmount(foodID: id, grams: $0) } }
    }
}
