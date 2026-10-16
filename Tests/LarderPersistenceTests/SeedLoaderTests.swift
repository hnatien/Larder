import Foundation
import LarderCore
import Testing
@testable import LarderPersistence

struct SeedLoaderTests {
    let database: LarderDatabase
    let loader: SeedLoader

    init() throws {
        database = try LarderDatabase.inMemory()
        loader = SeedLoader(database: database)
    }

    private func loadFixtures() async throws -> SeedReport {
        try await loader.load(
            foodsURL: Fixtures.seedFile("seed-foods"),
            recipesURL: Fixtures.seedFile("seed-recipes")
        )
    }

    private func load(foods: String = #"{ "foods": [] }"#, recipes: String = #"{ "recipes": [] }"#) async throws -> SeedReport {
        try await loader.load(foodsJSON: Data(foods.utf8), recipesJSON: Data(recipes.utf8))
    }

    /// `fdcID` is inserted as raw JSON, so a test can pass a malformed value.
    private static func food(
        slug: String,
        foodGroup: String = "produce",
        source: String = "seedApproximate",
        fdcID: String? = nil,
        extra: String = ""
    ) -> String {
        """
        { "slug": "\(slug)", "name": "\(slug)", "source": "\(source)", \(fdcID.map { #""fdcId": \#($0), "# } ?? "")"foodGroup": "\(foodGroup)",
          "tags": [], "allergens": {}, "portions": [], "densityGPerMl": null, "per100g": { \(extra) } }
        """
    }

    private static func recipe(slug: String, unit: String = "gram", foodSlug: String = "onion", mealType: String = "dinner") -> String {
        """
        { "slug": "\(slug)", "title": "\(slug)", "servings": 2, "prepMinutes": 5, "cookMinutes": 10, "cuisine": null,
          "mealTypes": ["\(mealType)"], "equipment": [], "dietFlags": [],
          "ingredients": [ { "text": "1 onion", "quantity": 1, "unit": "\(unit)", "food": "\(foodSlug)", "optional": false, "garnish": false } ],
          "steps": [] }
        """
    }

    private static func isSeedError(_ expected: SeedError) -> @Sendable (any Error) -> Bool {
        { error in (error as? SeedError) == expected }
    }

    @Test func seedLoaderLoadsFixturesIntoEveryTable() async throws {
        let report = try await loadFixtures()
        #expect(report == SeedReport(foodsInserted: 3, recipesInserted: 1, unresolvedFoodSlugs: []))

        let foods = GRDBFoodRepository(database: database)
        let chicken = try #require(try await foods.food(by: DeterministicID.foodID(slug: "chicken-breast")))
        #expect(chicken.name == "Chicken breast, raw")
        #expect(chicken.source == .seedApproximate)
        #expect(chicken.fdcID == nil)
        #expect(chicken.foodGroup == .protein)
        #expect(chicken.portions == [Portion(label: "breast", grams: 170)])
        #expect(chicken.allergens.presence(of: .milk) == .verifiedFree)
        #expect(chicken.allergens.presence(of: .egg) == .unknown)
        #expect(chicken.nutrientsPer100g.proteinG == 22.5)
        #expect(chicken.nutrientsPer100g.carbohydrateG == 0)
        #expect(chicken.nutrientsPer100g.vitaminDMcg == nil)
        let oliveOil = try #require(try await foods.food(by: DeterministicID.foodID(slug: "olive-oil")))
        #expect(oliveOil.source == .srLegacy)
        #expect(oliveOil.fdcID == 171413)
        let chickpeas = try #require(try await foods.food(by: DeterministicID.foodID(slug: "chickpeas-canned")))
        #expect(chickpeas.nutrientsPer100g.sodiumMg == nil)
        #expect(try await foods.search(text: "chick", limit: 10).count == 2)

        let recipes = GRDBRecipeRepository(database: database)
        let recipeID = DeterministicID.recipeID(slug: "weeknight-chana-masala")
        let recipe = try #require(try await recipes.recipe(by: recipeID))
        #expect(recipe.title == "Weeknight chana masala")
        #expect(recipe.origin == .generated)
        #expect(recipe.tags == RecipeTags(cuisine: "Indian", mealTypes: [.dinner], equipment: [.stovetop], dietFlags: [.vegan, .vegetarian]))
        #expect(recipe.steps == [RecipeStep(text: "Warm the oil over medium heat."), RecipeStep(text: "Simmer the chickpeas.", timerSeconds: 900)])

        let ingredients = try await recipes.ingredients(for: recipeID)
        #expect(ingredients.map(\.rawText) == ["2 tbsp olive oil", "2 cans chickpeas, drained", "1 cup water"])
        #expect(ingredients.map(\.foodID) == [DeterministicID.foodID(slug: "olive-oil"), DeterministicID.foodID(slug: "chickpeas-canned"), nil])
        #expect(ingredients.map(\.matchConfidence) == [1, 1, 0])
        #expect(ingredients.map(\.unit) == [.tablespoon, .gram, .cup])
        #expect(ingredients.allSatisfy { $0.gramsResolved == nil })
        #expect(try await recipes.search(text: "chickpeas", limit: 5) == [recipe])
    }

    @Test func seedLoaderRunTwiceInsertsZeroNewRows() async throws {
        _ = try await loadFixtures()
        let tables = ["food", "recipe", "ingredient"]
        var before: [Int] = []
        for table in tables {
            before.append(try await Fixtures.count(table, in: database))
        }

        let second = try await loadFixtures()

        #expect(second.foodsInserted == 0)
        #expect(second.recipesInserted == 0)
        var after: [Int] = []
        for table in tables {
            after.append(try await Fixtures.count(table, in: database))
        }
        #expect(after == before)
        #expect(before == [3, 1, 3])
        try await Fixtures.checkSearchIndexes(in: database)
    }

    @Test func unresolvedFoodSlugsAreReportedNotFatal() async throws {
        let report = try await load(
            foods: #"{ "foods": [\#(Self.food(slug: "onion"))] }"#,
            recipes: #"{ "recipes": [\#(Self.recipe(slug: "a", foodSlug: "garam-masala")), \#(Self.recipe(slug: "b", foodSlug: "onion")), \#(Self.recipe(slug: "c", foodSlug: "garam-masala"))] }"#
        )
        #expect(report == SeedReport(foodsInserted: 1, recipesInserted: 3, unresolvedFoodSlugs: ["garam-masala"]))
        let ingredient = try await GRDBRecipeRepository(database: database)
            .ingredients(for: DeterministicID.recipeID(slug: "a"))
            .first
        #expect(ingredient?.foodID == nil)
        #expect(ingredient?.matchConfidence == 0)
    }

    @Test func duplicateSlugsAreRejected() async throws {
        await #expect(throws: SeedError.duplicateSlug("onion")) {
            try await load(foods: #"{ "foods": [\#(Self.food(slug: "onion")), \#(Self.food(slug: "onion"))] }"#)
        }
        await #expect(throws: SeedError.duplicateSlug("soup")) {
            try await load(recipes: #"{ "recipes": [\#(Self.recipe(slug: "soup")), \#(Self.recipe(slug: "soup"))] }"#)
        }
        #expect(try await Fixtures.count("food", in: database) == 0)
    }

    @Test func unknownEnumValuesAreRejectedNamingSlugAndKey() async throws {
        let foodError = SeedError.invalidValue(slug: "beef-mince", key: "foodGroup", value: "meat")
        await #expect(throws: foodError) {
            try await load(foods: #"{ "foods": [\#(Self.food(slug: "beef-mince", foodGroup: "meat"))] }"#)
        }
        #expect(foodError.description.contains("beef-mince"))
        #expect(foodError.description.contains("foodGroup"))

        await #expect(throws: SeedError.invalidValue(slug: "soup", key: "ingredients.0.unit", value: "handful")) {
            try await load(
                foods: #"{ "foods": [\#(Self.food(slug: "onion"))] }"#,
                recipes: #"{ "recipes": [\#(Self.recipe(slug: "soup", unit: "handful"))] }"#
            )
        }
        await #expect(throws: SeedError.invalidValue(slug: "soup", key: "mealTypes", value: "brunch")) {
            try await load(recipes: #"{ "recipes": [\#(Self.recipe(slug: "soup", mealType: "brunch"))] }"#)
        }
        #expect(try await Fixtures.count("food", in: database) == 0)
    }

    @Test(arguments: FoodSource.allCases)
    func everySourceNameLoadsAsItsCase(source: FoodSource) async throws {
        _ = try await load(foods: #"{ "foods": [\#(Self.food(slug: "onion", source: source.rawValue))] }"#)
        let onion = try #require(try await GRDBFoodRepository(database: database).food(by: DeterministicID.foodID(slug: "onion")))
        #expect(onion.source == source)
    }

    @Test func unknownSourceIsRejected() async throws {
        await #expect(throws: SeedError.invalidValue(slug: "onion", key: "source", value: "usda")) {
            try await load(foods: #"{ "foods": [\#(Self.food(slug: "onion", source: "usda"))] }"#)
        }
    }

    @Test(arguments: [("fdcFoundation", FoodSource.fdcFoundation, 2346393), ("srLegacy", .srLegacy, 170567)])
    func fdcIdentifierIsStoredWithTheFood(source: String, expected: FoodSource, fdcID: Int) async throws {
        _ = try await load(foods: #"{ "foods": [\#(Self.food(slug: "almonds", source: source, fdcID: String(fdcID)))] }"#)
        let almonds = try #require(try await GRDBFoodRepository(database: database).food(by: DeterministicID.foodID(slug: "almonds")))
        #expect(almonds.source == expected)
        #expect(almonds.fdcID == fdcID)
    }

    @Test func approximateFoodLoadsWithoutAnFdcIdentifier() async throws {
        _ = try await load(foods: #"{ "foods": [\#(Self.food(slug: "mixed-seeds", extra: #""energyKcal": 560"#))] }"#)
        let seeds = try #require(try await GRDBFoodRepository(database: database).food(by: DeterministicID.foodID(slug: "mixed-seeds")))
        #expect(seeds.source == .seedApproximate)
        #expect(seeds.fdcID == nil)
        #expect(seeds.nutrientsPer100g.energyKcal == 560)
    }

    @Test func nonIntegerFdcIdentifierIsMalformed() async throws {
        await #expect {
            try await load(foods: #"{ "foods": [\#(Self.food(slug: "onion", source: "srLegacy", fdcID: #""170000""#))] }"#)
        } throws: { error in
            guard case let SeedError.malformed(file, reason) = error else { return false }
            return file == "seed-foods.json" && reason.contains("fdcId")
        }
        #expect(try await Fixtures.count("food", in: database) == 0)
    }

    /// The bundled seed decodes, resolves every recipe food, and stores each FDC identifier unchanged.
    @Test func shippedSeedStoresEveryFdcIdentifier() async throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "App/Larder/Resources/Seed")
        let foodsURL = directory.appending(path: "seed-foods.json")
        let report = try await loader.load(foodsURL: foodsURL, recipesURL: directory.appending(path: "seed-recipes.json"))
        #expect(report.unresolvedFoodSlugs.isEmpty)

        let seeds = try JSONDecoder().decode(SeedFoodsFile.self, from: Data(contentsOf: foodsURL)).foods
        let stored = try await GRDBFoodRepository(database: database).foods(byIDs: seeds.map { DeterministicID.foodID(slug: $0.slug) })
        #expect(stored.count == seeds.count)
        for (seed, food) in zip(seeds, stored) {
            #expect(food.fdcID == seed.fdcId, "\(seed.slug)")
            switch food.source {
            case .fdcFoundation, .srLegacy:
                #expect(food.fdcID != nil, "\(seed.slug)")
                #expect(food.nutrientsPer100g.energyKcal != nil, "\(seed.slug)")
            case .seedApproximate:
                #expect(food.fdcID == nil, "\(seed.slug)")
            case .fdcBranded, .offUnverified:
                Issue.record("\(seed.slug) has source \(food.source), which the seed does not use")
            }
        }
    }

    @Test func unknownNutrientKeysAreRejected() async throws {
        await #expect(throws: SeedError.unknownKey(slug: "onion", key: "per100g.vitaminC")) {
            try await load(foods: #"{ "foods": [\#(Self.food(slug: "onion", extra: #""energyKcal": 40, "vitaminC": 7.4"#))] }"#)
        }
    }

    @Test func malformedFilesAreRejectedWithTheFileName() async throws {
        await #expect {
            try await load(recipes: #"{ "recipes": [ { "slug": "soup" } ] }"#)
        } throws: { error in
            guard case let SeedError.malformed(file, reason) = error else { return false }
            return file == "seed-recipes.json" && reason.contains("recipes.0")
        }
        await #expect {
            try await load(foods: "not json")
        } throws: { error in
            guard case let SeedError.malformed(file, _) = error else { return false }
            return file == "seed-foods.json"
        }
    }
}
