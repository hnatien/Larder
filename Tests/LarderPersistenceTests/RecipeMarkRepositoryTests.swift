import Foundation
import LarderCore
import Testing
@testable import LarderPersistence

struct RecipeMarkRepositoryTests {
    let database: LarderDatabase
    let recipes: GRDBRecipeRepository

    init() throws {
        database = try LarderDatabase.inMemory()
        recipes = GRDBRecipeRepository(database: database)
    }

    private func saved(_ title: String) async throws -> Recipe {
        let recipe = Recipe(title: title, origin: .generated, servings: 2, prepMinutes: 5, cookMinutes: 10)
        try await recipes.save(recipe, ingredients: [
            Ingredient(recipeID: recipe.id, rawText: "1 cup \(title.lowercased())", quantity: 1, unit: .cup),
        ])
        return recipe
    }

    @Test func favouritesRoundTripAndCanBeTakenOff() async throws {
        let soup = try await saved("Soup")
        let stew = try await saved("Stew")
        try await recipes.setFavourite(soup.id, true)
        try await recipes.setFavourite(stew.id, true)
        try await recipes.setFavourite(stew.id, false)
        #expect(try await recipes.favourites() == [soup.id])
    }

    @Test func hiddenRecipesLeaveTheLibraryAndSearchButStayReadable() async throws {
        let soup = try await saved("Soup")
        let stew = try await saved("Stew")
        try await recipes.setHidden(stew.id, true)
        #expect(try await recipes.all().map(\.id) == [soup.id])
        #expect(try await recipes.search(text: "stew", limit: 10).isEmpty)
        #expect(try await recipes.search(text: "%", limit: 10).isEmpty)
        #expect(try await recipes.recipe(by: stew.id)?.id == stew.id)
        #expect(try await recipes.hiddenRecipes().map(\.id) == [stew.id])
        try await recipes.setHidden(stew.id, false)
        #expect(try await recipes.all().map(\.title) == ["Soup", "Stew"])
        #expect(try await recipes.hiddenRecipes().isEmpty)
    }

    @Test func aFavouriteThatIsHiddenKeepsBothMarks() async throws {
        let soup = try await saved("Soup")
        try await recipes.setFavourite(soup.id, true)
        try await recipes.setHidden(soup.id, true)
        try await recipes.setHidden(soup.id, false)
        #expect(try await recipes.favourites() == [soup.id])
    }

    @Test func marksSurviveASaveAndGoWithADelete() async throws {
        let soup = try await saved("Soup")
        try await recipes.setFavourite(soup.id, true)
        try await recipes.save(soup, ingredients: [])
        #expect(try await recipes.favourites() == [soup.id])
        try await recipes.delete(soup.id)
        #expect(try await recipes.favourites().isEmpty)
    }
}
