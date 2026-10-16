import Foundation
import GRDB
import LarderCore

/// A problem with the content of a seed file.
public enum SeedError: Error, Hashable, CustomStringConvertible {
    /// The file is not valid JSON or does not match the seed schema.
    case malformed(file: String, reason: String)
    /// Two entries in one file share a slug.
    case duplicateSlug(String)
    /// A field holds a value its enumeration does not have.
    case invalidValue(slug: String, key: String, value: String)
    /// `per100g` names a nutrient that `Nutrients` does not track.
    case unknownKey(slug: String, key: String)

    public var description: String {
        switch self {
        case let .malformed(file, reason): "\(file) is malformed: \(reason)"
        case let .duplicateSlug(slug): "Slug \"\(slug)\" appears more than once"
        case let .invalidValue(slug, key, value): "\"\(slug)\": \(key) has unknown value \"\(value)\""
        case let .unknownKey(slug, key): "\"\(slug)\": unknown key \(key)"
        }
    }
}

/// What a seed load changed.
public struct SeedReport: Hashable, Sendable {
    /// Foods that were not stored before this load.
    public var foodsInserted: Int
    /// Recipes that were not stored before this load.
    public var recipesInserted: Int
    /// Food slugs referenced by ingredient lines but absent from the foods file, sorted.
    public var unresolvedFoodSlugs: [String]

    /// Creates a report.
    public init(foodsInserted: Int, recipesInserted: Int, unresolvedFoodSlugs: [String]) {
        self.foodsInserted = foodsInserted
        self.recipesInserted = recipesInserted
        self.unresolvedFoodSlugs = unresolvedFoodSlugs
    }
}

/// Loads `seed-foods.json` and `seed-recipes.json` into the store, upserting by slug-derived identifiers.
///
/// Validation happens before anything is written, and the write is one transaction, so a bad file changes nothing.
/// Throws `SeedError` for content problems and `PersistenceError` for storage failures.
public struct SeedLoader: Sendable {
    private let database: LarderDatabase

    /// Creates a loader writing to `database`.
    public init(database: LarderDatabase) {
        self.database = database
    }

    /// Reads and loads the two seed files.
    public func load(foodsURL: URL, recipesURL: URL) async throws -> SeedReport {
        try await load(foodsJSON: Data(contentsOf: foodsURL), recipesJSON: Data(contentsOf: recipesURL))
    }

    /// Validates and loads seed JSON; running it again with the same input inserts nothing new.
    public func load(foodsJSON: Data, recipesJSON: Data) async throws -> SeedReport {
        let seedFoods = try Self.decode(SeedFoodsFile.self, from: foodsJSON, file: "seed-foods.json").foods
        let seedRecipes = try Self.decode(SeedRecipesFile.self, from: recipesJSON, file: "seed-recipes.json").recipes
        let foodSlugs = try Self.uniqueSlugs(seedFoods.map(\.slug))
        _ = try Self.uniqueSlugs(seedRecipes.map(\.slug))

        let foods = try seedFoods.map(Self.food)
        var unresolved = Set<String>()
        let recipes = try seedRecipes.map { seed in
            try Self.recipe(seed, foodSlugs: foodSlugs, unresolved: &unresolved)
        }
        let unresolvedFoodSlugs = unresolved.sorted()

        return try await database.write { db in
            var foodsInserted = 0
            for food in foods {
                if try !FoodRecord.exists(db, key: food.id.key) {
                    foodsInserted += 1
                }
                try FoodRecord(food).upsert(db)
            }
            var recipesInserted = 0
            for (recipe, ingredients) in recipes {
                if try !RecipeRecord.exists(db, key: recipe.id.key) {
                    recipesInserted += 1
                }
                try GRDBRecipeRepository.save(recipe, ingredients: ingredients, in: db)
            }
            return SeedReport(
                foodsInserted: foodsInserted,
                recipesInserted: recipesInserted,
                unresolvedFoodSlugs: unresolvedFoodSlugs
            )
        }
    }

    private static func decode<File: Decodable>(_ type: File.Type, from data: Data, file: String) throws -> File {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            throw SeedError.malformed(file: file, reason: reason(for: error))
        }
    }

    private static func reason(for error: DecodingError) -> String {
        let context: DecodingError.Context
        switch error {
        case let .typeMismatch(_, errorContext), let .valueNotFound(_, errorContext),
            let .keyNotFound(_, errorContext), let .dataCorrupted(errorContext):
            context = errorContext
        @unknown default:
            return String(describing: error)
        }
        let path = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
    }

    private static func uniqueSlugs(_ slugs: [String]) throws -> Set<String> {
        var seen = Set<String>()
        for slug in slugs where !seen.insert(slug).inserted {
            throw SeedError.duplicateSlug(slug)
        }
        return seen
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
                throw SeedError.unknownKey(slug: seed.slug, key: "per100g.\(name)")
            }
            nutrients[keyPath: keyPath] = amount
        }
        let fields = FoodFields(
            id: DeterministicID.foodID(slug: seed.slug).rawValue,
            name: seed.name,
            source: try parse(seed.source, slug: seed.slug, key: "source"),
            fdcID: nil,
            gtin: nil,
            nutrientsPer100g: nutrients,
            portions: seed.portions.map { Portion(label: $0.label, grams: $0.grams) },
            foodGroup: try parse(seed.foodGroup, slug: seed.slug, key: "foodGroup"),
            allergens: AllergenTags(allergens),
            densityGPerMl: seed.densityGPerMl,
            tags: seed.tags
        )
        do {
            return try fields.food()
        } catch let DecodingError.dataCorrupted(context) where context.codingPath.first?.stringValue == "tags" {
            let value = context.codingPath.last?.intValue.map { fields.tags[$0] } ?? seed.tags.joined(separator: ", ")
            throw SeedError.invalidValue(slug: seed.slug, key: "tags", value: value)
        }
    }

    private static func recipe(
        _ seed: SeedRecipe,
        foodSlugs: Set<String>,
        unresolved: inout Set<String>
    ) throws -> (Recipe, [Ingredient]) {
        let recipeID = DeterministicID.recipeID(slug: seed.slug)
        let recipe = Recipe(
            id: recipeID,
            title: seed.title,
            origin: .generated,
            servings: seed.servings,
            prepMinutes: seed.prepMinutes,
            cookMinutes: seed.cookMinutes,
            steps: seed.steps.map { RecipeStep(text: $0.text, timerSeconds: $0.timerSeconds) },
            tags: RecipeTags(
                cuisine: seed.cuisine,
                mealTypes: Set(try seed.mealTypes.map { try parse($0, slug: seed.slug, key: "mealTypes") }),
                equipment: Set(try seed.equipment.map { try parse($0, slug: seed.slug, key: "equipment") }),
                dietFlags: Set(try seed.dietFlags.map { try parse($0, slug: seed.slug, key: "dietFlags") })
            )
        )
        var ingredients: [Ingredient] = []
        for (position, line) in seed.ingredients.enumerated() {
            var foodID: FoodID?
            if let foodSlug = line.food {
                if foodSlugs.contains(foodSlug) {
                    foodID = DeterministicID.foodID(slug: foodSlug)
                } else {
                    unresolved.insert(foodSlug)
                }
            }
            ingredients.append(Ingredient(
                id: DeterministicID.ingredientID(recipeSlug: seed.slug, position: position),
                recipeID: recipeID,
                rawText: line.text,
                quantity: line.quantity,
                unit: try parse(line.unit, slug: seed.slug, key: "ingredients.\(position).unit"),
                foodID: foodID,
                matchConfidence: foodID == nil ? 0 : 1,
                isOptional: line.optional,
                isGarnish: line.garnish
            ))
        }
        return (recipe, ingredients)
    }

    private static func parse<Value: RawRepresentable>(_ raw: String, slug: String, key: String) throws -> Value
    where Value.RawValue == String {
        guard let value = Value(rawValue: raw) else {
            throw SeedError.invalidValue(slug: slug, key: key, value: raw)
        }
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
