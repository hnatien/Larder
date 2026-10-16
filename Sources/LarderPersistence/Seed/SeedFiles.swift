import Foundation

/// The `seed-foods.json` schema, with enum values kept as strings until `SeedLoader` validates them.
struct SeedFoodsFile: Decodable {
    var foods: [SeedFood]
}

struct SeedFood: Decodable {
    var slug: String
    var name: String
    var source: String
    /// USDA FoodData Central identifier; present for `fdcFoundation` and `srLegacy` foods.
    var fdcId: Int?
    var foodGroup: String
    var tags: [String]
    var allergens: [String: String]
    var portions: [SeedPortion]
    var densityGPerMl: Double?
    /// Nutrient name to amount per 100 g; names are checked against `Nutrients` by `SeedLoader`.
    var per100g: [String: Double?]
}

struct SeedPortion: Decodable {
    var label: String
    var grams: Double
}

/// The `seed-recipes.json` schema, with enum values kept as strings until `SeedLoader` validates them.
struct SeedRecipesFile: Decodable {
    var recipes: [SeedRecipe]
}

struct SeedRecipe: Decodable {
    var slug: String
    var title: String
    var servings: Int
    var prepMinutes: Int
    var cookMinutes: Int
    var cuisine: String?
    var mealTypes: [String]
    var equipment: [String]
    var dietFlags: [String]
    var ingredients: [SeedIngredient]
    var steps: [SeedStep]
}

struct SeedIngredient: Decodable {
    var text: String
    var quantity: Double
    var unit: String
    /// Slug of the matching seed food, or `nil` when the line has no food (water, for example).
    var food: String?
    var optional: Bool
    var garnish: Bool
}

struct SeedStep: Decodable {
    var text: String
    var timerSeconds: Int?
}
