import LarderCore
import Testing
@testable import FeatureRecipes

@MainActor
struct RecipesModelTests {
    private let curry = Sample.recipe("Chana masala", prep: 10, cook: 25, cuisine: "Indian", meals: [.dinner], diets: [.vegan, .vegetarian])
    private let porridge = Sample.recipe("Oat porridge", prep: 2, cook: 8, meals: [.breakfast], diets: [.vegetarian])
    private let pasta = Sample.recipe("Chicken pasta", prep: 15, cook: 30, cuisine: "italian", meals: [.dinner, .lunch])
    private let salad = Sample.recipe("Lentil salad", prep: 10, cook: 0, cuisine: "Indian", meals: [.lunch], diets: [.vegan, .vegetarian])

    private func loadedModel(extra: [Recipe] = []) async -> (RecipesModel, FakeStore) {
        let store = FakeStore(recipes: [curry, porridge, pasta, salad] + extra)
        let model = Sample.model(store: store)
        await model.load()
        return (model, store)
    }

    @Test func loadFillsRecipesAndResults() async {
        let (model, _) = await loadedModel()
        #expect(model.recipes.count == 4)
        #expect(model.results.count == 4)
        #expect(model.hasLoaded)
        #expect(!model.isLoading)
        #expect(model.error == nil)
    }

    @Test func loadFailureSetsErrorAndKeepsLibraryUnloaded() async {
        let store = FakeStore(recipes: [curry])
        await store.setFailReads(true)
        let model = Sample.model(store: store)
        await model.load()
        #expect(model.error == .loadFailed)
        #expect(!model.hasLoaded)
        #expect(model.results.isEmpty)
    }

    @Test func mealTypeFilterMatchesAnySelected() async {
        let (model, _) = await loadedModel()
        model.filters.mealTypes = [.breakfast]
        #expect(model.results.map(\.title) == ["Oat porridge"])
        model.filters.mealTypes = [.breakfast, .lunch]
        #expect(Set(model.results.map(\.title)) == ["Oat porridge", "Chicken pasta", "Lentil salad"])
    }

    @Test func dietFilterRequiresEveryChosenFlag() async {
        let (model, _) = await loadedModel()
        model.filters.dietFlags = [.vegetarian]
        #expect(Set(model.results.map(\.title)) == ["Chana masala", "Oat porridge", "Lentil salad"])
        model.filters.dietFlags = [.vegetarian, .vegan]
        #expect(Set(model.results.map(\.title)) == ["Chana masala", "Lentil salad"])
    }

    @Test func maxMinutesCountsPrepPlusCook() async {
        let (model, _) = await loadedModel()
        model.filters.maxMinutes = 10
        #expect(Set(model.results.map(\.title)) == ["Oat porridge", "Lentil salad"])
        model.filters.maxMinutes = 35
        #expect(model.results.count == 3)
    }

    @Test func cuisineFilterIgnoresCase() async {
        let (model, _) = await loadedModel()
        model.filters.cuisine = "Italian"
        #expect(model.results.map(\.title) == ["Chicken pasta"])
    }

    @Test func filtersCombineAndClear() async {
        let (model, _) = await loadedModel()
        model.filters = RecipeFilters(mealTypes: [.lunch], dietFlags: [.vegan], maxMinutes: 20, cuisine: "indian")
        #expect(model.results.map(\.title) == ["Lentil salad"])
        model.filters = RecipeFilters()
        #expect(model.results.count == 4)
        #expect(model.filters.isEmpty)
    }

    @Test func filterThatMatchesNothingGivesNoResults() async {
        let (model, _) = await loadedModel()
        model.filters.mealTypes = [.snack]
        #expect(model.results.isEmpty)
        #expect(model.recipes.count == 4)
    }

    @Test func cuisinesAreUniqueAndSorted() async {
        let (model, _) = await loadedModel()
        #expect(model.cuisines == ["Indian", "italian"])
    }

    @Test func searchUsesTheRepositoryWhenQueryIsNotEmpty() async {
        let (model, _) = await loadedModel()
        model.query = "pasta"
        await model.search()
        #expect(model.results.map(\.title) == ["Chicken pasta"])
    }

    @Test func searchResultsAreFilteredInMemory() async {
        let (model, _) = await loadedModel()
        model.query = "a"
        await model.search()
        #expect(model.results.count == 4)
        model.filters.mealTypes = [.breakfast]
        #expect(model.results.map(\.title) == ["Oat porridge"])
    }

    @Test func blankQueryShowsEverything() async {
        let (model, _) = await loadedModel()
        model.query = "pasta"
        await model.search()
        model.query = "   "
        await model.search()
        #expect(model.results.count == 4)
    }

    @Test func searchBeforeLoadLoadsFirst() async {
        let store = FakeStore(recipes: [curry, pasta])
        let model = Sample.model(store: store)
        model.query = "chana"
        await model.search()
        #expect(model.hasLoaded)
        #expect(model.results.map(\.title) == ["Chana masala"])
    }

    @Test func searchFailureEmptiesResultsAndReportsError() async {
        let (model, store) = await loadedModel()
        await store.setFailReads(true)
        model.query = "pasta"
        await model.search()
        #expect(model.results.isEmpty)
        #expect(model.error == .loadFailed)
    }

    @Test func deleteRefusedForSeedAndGeneratedRecipes() async {
        let (model, store) = await loadedModel()
        let deleted = await model.delete(curry)
        #expect(!deleted)
        #expect(model.error == .notDeletable)
        #expect(await store.recipes.count == 4)
    }

    @Test func deleteRemovesUserImports() async {
        let imported = Sample.recipe("Imported stew", origin: .userImport)
        let (model, store) = await loadedModel(extra: [imported])
        let deleted = await model.delete(imported)
        #expect(deleted)
        #expect(model.error == nil)
        #expect(await store.recipes.count == 4)
        #expect(!model.results.contains { $0.id == imported.id })
    }

    @Test func deleteFailureKeepsTheRecipeAndReports() async {
        let imported = Sample.recipe("Imported stew", origin: .userImport)
        let (model, store) = await loadedModel(extra: [imported])
        await store.setFailDelete(true)
        let deleted = await model.delete(imported)
        #expect(!deleted)
        #expect(model.error == .deleteFailed)
        #expect(model.results.contains { $0.id == imported.id })
    }

    @Test func dismissErrorClearsIt() async {
        let (model, _) = await loadedModel()
        await model.delete(curry)
        model.dismissError()
        #expect(model.error == nil)
    }

    @Test func saveStoresTheImportAndReloads() async throws {
        let (model, store) = await loadedModel()
        let imported = Sample.recipe("Imported stew", origin: .userImport)
        try await model.save(ImportResult(recipe: imported, ingredients: [], source: .structuredData))
        #expect(model.recipes.contains { $0.id == imported.id })
        #expect(await store.saved.count == 1)
    }

    @Test func saveFailureThrowsAndSetsError() async {
        let (model, store) = await loadedModel()
        await store.setFailSave(true)
        let imported = Sample.recipe("Imported stew", origin: .userImport)
        await #expect(throws: RecipesError.saveFailed) {
            try await model.save(ImportResult(recipe: imported, ingredients: [], source: .structuredData))
        }
        #expect(model.error == .saveFailed)
    }
}

@MainActor
struct RecipeDetailTests {
    private let peanutAllergy = DietaryConstraint(
        axis: .medical, kind: .allergen(.peanut), strictness: .hard, source: .user, lastConfirmed: .now
    )

    @Test func detailComputesNutritionPerServing() async throws {
        let recipe = Sample.recipe("Chickpeas", servings: 2)
        let chickpeas = Food(
            name: "Chickpeas", source: .seedApproximate,
            nutrientsPer100g: Nutrients(energyKcal: 100, proteinG: 10), foodGroup: .legumes
        )
        let lines = [Sample.ingredient(recipe, "400 g chickpeas", quantity: 400, unit: .gram, food: chickpeas)]
        let store = FakeStore(recipes: [recipe], ingredients: [recipe.id: lines], foods: [chickpeas], profile: Sample.profile())
        let detail = try await Sample.model(store: store).detail(for: recipe)
        #expect(detail.nutrition.perServing.energyKcal == 200)
        #expect(detail.nutrition.perRecipe.proteinG == 40)
        #expect(detail.nutrition.coverage == 1)
        #expect(detail.ingredients.count == 1)
    }

    @Test func detailPassesWithoutConstraints() async throws {
        let recipe = Sample.recipe("Toast")
        let lines = [Sample.ingredient(recipe, "2 slices bread", quantity: 2, unit: .slice)]
        let store = FakeStore(recipes: [recipe], ingredients: [recipe.id: lines])
        let detail = try await Sample.model(store: store).detail(for: recipe)
        #expect(detail.verdict == .pass(softPenalties: []))
    }

    @Test func detailExcludesWhenTheTextNamesTheAllergen() async throws {
        let recipe = Sample.recipe("Satay")
        let lines = [Sample.ingredient(recipe, "3 tbsp peanut butter", quantity: 3, unit: .tablespoon)]
        let store = FakeStore(recipes: [recipe], ingredients: [recipe.id: lines], constraints: [peanutAllergy])
        let detail = try await Sample.model(store: store).detail(for: recipe)
        guard case .excluded(let reasons) = detail.verdict else {
            Issue.record("expected excluded, got \(detail.verdict)")
            return
        }
        #expect(!reasons.isEmpty)
    }

    @Test func detailIsUncertainWhenIngredientDataIsMissing() async throws {
        let recipe = Sample.recipe("Mystery bake")
        let lines = [Sample.ingredient(recipe, "200 g flour", quantity: 200, unit: .gram)]
        let store = FakeStore(recipes: [recipe], ingredients: [recipe.id: lines], constraints: [peanutAllergy])
        let detail = try await Sample.model(store: store).detail(for: recipe)
        guard case .uncertain = detail.verdict else {
            Issue.record("unknown allergen data must not read as safe, got \(detail.verdict)")
            return
        }
    }

    @Test func showsNumbersFollowsTheProfile() async throws {
        let recipe = Sample.recipe("Toast")
        let store = FakeStore(recipes: [recipe], profile: Sample.profile(showsNumbers: true))
        let model = Sample.model(store: store)
        #expect(try await model.detail(for: recipe).showsNumbers)
        await store.setProfile(Sample.profile(showsNumbers: false))
        #expect(try await !model.detail(for: recipe).showsNumbers)
        await store.setProfile(nil)
        #expect(try await !model.detail(for: recipe).showsNumbers)
    }

    @Test func detailThrowsInsteadOfReturningAPartialVerdict() async {
        let recipe = Sample.recipe("Toast")
        let store = FakeStore(recipes: [recipe])
        await store.setFailReads(true)
        await #expect(throws: StoreFailure.self) { try await Sample.model(store: store).detail(for: recipe) }
    }

    @Test func scaledUsesTheRecipeServingsAsBase() async throws {
        let recipe = Sample.recipe("Rice", servings: 2)
        let lines = [Sample.ingredient(recipe, "1 cup rice", quantity: 1, unit: .cup)]
        let store = FakeStore(recipes: [recipe], ingredients: [recipe.id: lines])
        let detail = try await Sample.model(store: store).detail(for: recipe)
        #expect(detail.scaled(to: 2) == lines)
        #expect(detail.scaled(to: 6).first?.rawText == "3 cup rice")
    }
}
