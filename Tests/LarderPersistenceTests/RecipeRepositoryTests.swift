import Foundation
import GRDB
import LarderCore
import Testing
@testable import LarderPersistence

struct RecipeRepositoryTests {
    let database: LarderDatabase
    let recipes: GRDBRecipeRepository
    let foods: GRDBFoodRepository

    init() throws {
        database = try LarderDatabase.inMemory()
        recipes = GRDBRecipeRepository(database: database)
        foods = GRDBFoodRepository(database: database)
    }

    @Test func recipeAndIngredientsRoundTripEveryField() async throws {
        let rice = Fixtures.food("Rice")
        try await foods.upsert([rice])
        let recipe = Recipe(
            title: "Rice and greens",
            origin: .userImport,
            sourceURL: URL(string: "https://example.com/rice?x=1"),
            license: "personal use",
            servings: 2,
            prepMinutes: 10,
            cookMinutes: 15,
            steps: [RecipeStep(text: "Rinse the rice."), RecipeStep(text: "Simmer.", timerSeconds: 900)],
            tags: RecipeTags(cuisine: "Korean", mealTypes: [.lunch, .dinner], equipment: [.stovetop, .oven], dietFlags: [.vegan]),
            photoFileName: "rice-and-greens.jpg"
        )
        let ingredients = [
            Ingredient(
                recipeID: recipe.id, rawText: "1 cup rice", quantity: 1, unit: .cup, foodID: rice.id,
                gramsResolved: 185, matchConfidence: 0.92, isOptional: false, isGarnish: false
            ),
            Ingredient(
                recipeID: recipe.id, rawText: "sesame seeds", quantity: 1, unit: .pinch,
                matchConfidence: 0, isOptional: true, isGarnish: true
            ),
        ]
        try await recipes.save(recipe, ingredients: ingredients)
        #expect(try await recipes.recipe(by: recipe.id) == recipe)
        #expect(try await recipes.ingredients(for: recipe.id) == ingredients)
    }

    @Test func saveReplacesIngredients() async throws {
        let recipe = Fixtures.recipe("Toast")
        try await recipes.save(recipe, ingredients: [
            Fixtures.ingredient("bread", recipeID: recipe.id),
            Fixtures.ingredient("butter", recipeID: recipe.id),
        ])
        let replacement = [Fixtures.ingredient("rye bread", recipeID: recipe.id)]
        try await recipes.save(recipe, ingredients: replacement)
        #expect(try await recipes.ingredients(for: recipe.id) == replacement)
        #expect(try await Fixtures.count("ingredient", in: database) == 1)
        #expect(try await Fixtures.count("recipe", in: database) == 1)
    }

    @Test func searchFindsRecipeByIngredientWord() async throws {
        let stew = Fixtures.recipe("Weeknight stew")
        let salad = Fixtures.recipe("Green salad")
        try await recipes.save(stew, ingredients: [Fixtures.ingredient("2 cans chickpeas, drained", recipeID: stew.id)])
        try await recipes.save(salad, ingredients: [Fixtures.ingredient("1 head lettuce", recipeID: salad.id)])
        #expect(try await recipes.search(text: "chickpea", limit: 10) == [stew])
        #expect(try await recipes.search(text: "green", limit: 10) == [salad])
    }

    @Test func resavingAndDeletingKeepTheSearchIndexConsistent() async throws {
        let recipe = Fixtures.recipe("Lentil soup")
        try await recipes.save(recipe, ingredients: [Fixtures.ingredient("1 jalapeño", recipeID: recipe.id)])
        #expect(try await recipes.search(text: "jalapeno", limit: 10) == [recipe])

        var renamed = recipe
        renamed.title = "Red lentil dal"
        try await recipes.save(renamed, ingredients: [Fixtures.ingredient("1 tsp cumin", recipeID: recipe.id)])
        #expect(try await recipes.search(text: "jalapeno", limit: 10).isEmpty)
        #expect(try await recipes.search(text: "soup", limit: 10).isEmpty)
        #expect(try await recipes.search(text: "cumin dal", limit: 10) == [renamed])
        try await Fixtures.checkSearchIndexes(in: database)

        try await recipes.delete(recipe.id)
        #expect(try await recipes.search(text: "cumin", limit: 10).isEmpty)
        #expect(try await recipes.recipe(by: recipe.id) == nil)
        #expect(try await Fixtures.count("ingredient", in: database) == 0)
        try await Fixtures.checkSearchIndexes(in: database)
    }

    @Test func deletingUnknownRecipeChangesNothing() async throws {
        let recipe = Fixtures.recipe("Porridge")
        try await recipes.save(recipe, ingredients: [])
        try await recipes.delete(RecipeID())
        #expect(try await recipes.all() == [recipe])
        try await Fixtures.checkSearchIndexes(in: database)
    }

    @Test func titleSearchFallsBackToLikeAndAllSortsByTitle() async throws {
        let b = Fixtures.recipe("B: 5-minute eggs")
        let a = Fixtures.recipe("A-1 sauce")
        try await recipes.save(b, ingredients: [])
        try await recipes.save(a, ingredients: [])
        #expect(try await recipes.all() == [a, b])
        #expect(try await recipes.search(text: ":", limit: 10) == [b])
        #expect(try await recipes.search(text: "", limit: 10).isEmpty)
    }

    @Test func deletingFoodClearsIngredientFoodID() async throws {
        let rice = Fixtures.food("Rice")
        try await foods.upsert([rice])
        let recipe = Fixtures.recipe("Rice bowl")
        try await recipes.save(recipe, ingredients: [Fixtures.ingredient("rice", recipeID: recipe.id, foodID: rice.id)])
        try await database.writer.write { db in
            _ = try FoodRecord.deleteOne(db, key: rice.id.key)
        }
        #expect(try await recipes.ingredients(for: recipe.id).first?.foodID == nil)
    }
}
