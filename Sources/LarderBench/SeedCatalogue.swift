import CryptoKit
import Foundation
import LarderCore

/// The seed foods and recipes as planner inputs, decoded straight from the JSON files without the database.
///
/// Identifiers are derived from slugs exactly as `LarderPersistence.DeterministicID` derives them, so a recipe has the
/// same `RecipeID` here as in the app and plans produced elsewhere can name recipes by slug.
struct SeedCatalogue: Sendable {
    var foods: [FoodID: Food]
    /// Foods in file order, for seeded draws that must not depend on dictionary order.
    var foodList: [Food]
    var candidates: [RecipeCandidate]
    var recipes: [RecipeID: Recipe]
    var ingredients: [RecipeID: [Ingredient]]
    var recipeIDsBySlug: [String: RecipeID]

    enum LoadError: Error, CustomStringConvertible {
        case invalidValue(slug: String, key: String, value: String)
        case unknownFood(recipe: String, food: String)

        var description: String {
            switch self {
            case let .invalidValue(slug, key, value): "\"\(slug)\": \(key) has unknown value \"\(value)\""
            case let .unknownFood(recipe, food): "\"\(recipe)\" uses \"\(food)\", which is not in the foods file"
            }
        }
    }

    /// The seed directory in this checkout: `App/Larder/Resources/Seed` beside `Package.swift`.
    static var defaultDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "App/Larder/Resources/Seed")
    }

    /// Decodes `seed-foods.json` and `seed-recipes.json` in `directory`.
    static func load(from directory: URL = defaultDirectory) throws -> SeedCatalogue {
        let decoder = JSONDecoder()
        let foodsFile = try decoder.decode(FoodsFile.self, from: Data(contentsOf: directory.appending(path: "seed-foods.json")))
        let recipesFile = try decoder.decode(RecipesFile.self, from: Data(contentsOf: directory.appending(path: "seed-recipes.json")))

        let foodList = try foodsFile.foods.map(food)
        let foods = Dictionary(foodList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var recipes: [Recipe] = []
        var ingredients: [RecipeID: [Ingredient]] = [:]
        var slugs: [String: RecipeID] = [:]
        for seed in recipesFile.recipes {
            let (recipe, lines) = try recipe(seed, foods: foods)
            recipes.append(recipe)
            ingredients[recipe.id] = lines
            slugs[seed.slug] = recipe.id
        }
        return SeedCatalogue(
            foods: foods,
            foodList: foodList,
            candidates: CandidateBuilder.build(recipes: recipes, ingredients: ingredients, foods: foods),
            recipes: Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            ingredients: ingredients,
            recipeIDsBySlug: slugs
        )
    }

    // MARK: Identifiers

    /// A version-5-shaped UUID from the first 16 bytes of SHA-256 of `name`, as `DeterministicID.uuid(for:)`.
    static func uuid(for name: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }

    // MARK: Decoding

    private struct FoodsFile: Decodable {
        var foods: [SeedFood]
    }

    private struct SeedFood: Decodable {
        var slug: String
        var name: String
        var source: String
        var fdcId: Int?
        var foodGroup: String
        var tags: [String]
        var allergens: [String: String]
        var portions: [SeedPortion]
        var densityGPerMl: Double?
        var per100g: [String: Double?]
    }

    private struct SeedPortion: Decodable {
        var label: String
        var grams: Double
    }

    private struct RecipesFile: Decodable {
        var recipes: [SeedRecipe]
    }

    private struct SeedRecipe: Decodable {
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
    }

    private struct SeedIngredient: Decodable {
        var text: String
        var quantity: Double
        var unit: String
        var food: String?
        var optional: Bool
        var garnish: Bool
    }

    private static func food(_ seed: SeedFood) throws -> Food {
        var allergens: [Allergen: AllergenPresence] = [:]
        for (name, presence) in seed.allergens {
            let allergen: Allergen = try parse(name, slug: seed.slug, key: "allergens")
            allergens[allergen] = try parse(presence, slug: seed.slug, key: "allergens.\(name)")
        }
        var nutrients = Nutrients()
        for (name, amount) in seed.per100g {
            guard let keyPath = nutrientKeyPath(name) else {
                throw LoadError.invalidValue(slug: seed.slug, key: "per100g", value: name)
            }
            nutrients[keyPath: keyPath] = amount
        }
        return Food(
            id: FoodID(rawValue: uuid(for: seed.slug)),
            name: seed.name,
            source: try parse(seed.source, slug: seed.slug, key: "source"),
            fdcID: seed.fdcId,
            nutrientsPer100g: nutrients,
            portions: seed.portions.map { Portion(label: $0.label, grams: $0.grams) },
            foodGroup: try parse(seed.foodGroup, slug: seed.slug, key: "foodGroup"),
            allergens: AllergenTags(allergens),
            densityGPerMl: seed.densityGPerMl,
            tags: Set(try seed.tags.map { try parse($0, slug: seed.slug, key: "tags") })
        )
    }

    private static func recipe(_ seed: SeedRecipe, foods: [FoodID: Food]) throws -> (Recipe, [Ingredient]) {
        let recipeID = RecipeID(rawValue: uuid(for: seed.slug))
        let recipe = Recipe(
            id: recipeID,
            title: seed.title,
            origin: .generated,
            servings: seed.servings,
            prepMinutes: seed.prepMinutes,
            cookMinutes: seed.cookMinutes,
            tags: RecipeTags(
                cuisine: seed.cuisine,
                mealTypes: Set(try seed.mealTypes.map { try parse($0, slug: seed.slug, key: "mealTypes") }),
                equipment: Set(try seed.equipment.map { try parse($0, slug: seed.slug, key: "equipment") }),
                dietFlags: Set(try seed.dietFlags.map { try parse($0, slug: seed.slug, key: "dietFlags") })
            )
        )
        let lines = try seed.ingredients.enumerated().map { position, line in
            let foodID = line.food.map { FoodID(rawValue: uuid(for: $0)) }
            if let foodID, foods[foodID] == nil, let slug = line.food {
                throw LoadError.unknownFood(recipe: seed.slug, food: slug)
            }
            return Ingredient(
                id: IngredientID(rawValue: uuid(for: "\(seed.slug)/ingredient/\(position)")),
                recipeID: recipeID,
                rawText: line.text,
                quantity: line.quantity,
                unit: try parse(line.unit, slug: seed.slug, key: "ingredients.\(position).unit"),
                foodID: foodID,
                matchConfidence: foodID == nil ? 0 : 1,
                isOptional: line.optional,
                isGarnish: line.garnish
            )
        }
        return (recipe, lines)
    }

    private static func parse<Value: RawRepresentable>(_ raw: String, slug: String, key: String) throws -> Value
    where Value.RawValue == String {
        guard let value = Value(rawValue: raw) else { throw LoadError.invalidValue(slug: slug, key: key, value: raw) }
        return value
    }

    private static func nutrientKeyPath(_ name: String) -> WritableKeyPath<Nutrients, Double?>? {
        switch name {
        case "energyKcal": \.energyKcal
        case "proteinG": \.proteinG
        case "fatG": \.fatG
        case "saturatedFatG": \.saturatedFatG
        case "monounsaturatedFatG": \.monounsaturatedFatG
        case "polyunsaturatedFatG": \.polyunsaturatedFatG
        case "carbohydrateG": \.carbohydrateG
        case "fiberG": \.fiberG
        case "totalSugarG": \.totalSugarG
        case "addedSugarG": \.addedSugarG
        case "sodiumMg": \.sodiumMg
        case "potassiumMg": \.potassiumMg
        case "calciumMg": \.calciumMg
        case "ironMg": \.ironMg
        case "vitaminDMcg": \.vitaminDMcg
        case "vitaminB12Mcg": \.vitaminB12Mcg
        default: nil
        }
    }
}
