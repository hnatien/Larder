import Foundation
import LarderCore
import Testing
@testable import FeatureRecipes

/// Favourites, hidden recipes, sorting and what the pantry covers.
@MainActor
struct LibraryMarksTests {
    private let rice = Food(name: "Rice", source: .seedApproximate, foodGroup: .grains)
    private let beans = Food(name: "Black beans", source: .seedApproximate, foodGroup: .legumes)
    private let lime = Food(name: "Lime", source: .seedApproximate, foodGroup: .produce)
    private let curry = Sample.recipe("Chana masala", prep: 10, cook: 25)
    private let porridge = Sample.recipe("Oat porridge", prep: 2, cook: 8)
    private let bowl = Sample.recipe("Bean bowl", prep: 5, cook: 15)

    private func store() -> FakeStore {
        FakeStore(
            recipes: [bowl, curry, porridge],
            ingredients: [
                bowl.id: [
                    Sample.ingredient(bowl, "200 g rice", quantity: 200, unit: .gram, food: rice),
                    Sample.ingredient(bowl, "1 can black beans", quantity: 400, unit: .gram, food: beans),
                    Sample.ingredient(bowl, "1 lime", quantity: 1, unit: .piece, food: lime),
                ],
                curry.id: [Sample.ingredient(curry, "100 g rice", quantity: 100, unit: .gram, food: rice)],
            ],
            foods: [rice, beans, lime]
        )
    }

    private func shelfItem(_ food: Food) -> PantryItem {
        PantryItem(foodID: food.id, rawName: food.name, quantityGrams: 300, location: .pantry, source: .manual, addedOn: .now)
    }

    @Test func favouritesPersistAndFilter() async {
        let store = store()
        let model = Sample.model(store: store)
        await model.load()
        await model.toggleFavourite(curry)
        #expect(model.favourites == [curry.id])
        #expect(await store.favouriteIDs == [curry.id])
        model.filters.favouritesOnly = true
        #expect(model.results.map(\.title) == ["Chana masala"])
        #expect(model.filters.activeCount == 1)
        await model.toggleFavourite(curry)
        #expect(model.results.isEmpty)
    }

    @Test func aFailedFavouriteReportsAndChangesNothing() async {
        let store = store()
        await store.setFailMarks(true)
        let model = Sample.model(store: store)
        await model.load()
        await model.toggleFavourite(curry)
        #expect(model.favourites.isEmpty)
        #expect(model.error == .markFailed)
    }

    @Test func hiddenRecipesLeaveTheLibraryAndComeBack() async {
        let store = store()
        let model = Sample.model(store: store)
        await model.load()
        await model.hide(porridge)
        #expect(!model.results.contains { $0.id == porridge.id })
        #expect(model.hiddenRecipes.map(\.id) == [porridge.id])
        await model.unhide(porridge)
        #expect(model.results.contains { $0.id == porridge.id })
        #expect(model.hiddenRecipes.isEmpty)
    }

    @Test func coverageCountsMatchedFoodsOnTheShelves() async {
        let store = store()
        await store.setPantry([shelfItem(rice), shelfItem(beans)])
        let model = Sample.model(store: store)
        await model.load()
        #expect(model.coverage[bowl.id] == PantryCoverage(have: 2, total: 3))
        #expect(model.coverage[curry.id] == PantryCoverage(have: 1, total: 1))
        #expect(model.coverage[porridge.id] == PantryCoverage(have: 0, total: 0))
        await store.setPantry([])
        await model.refreshCoverage()
        #expect(model.coverage[bowl.id] == PantryCoverage(have: 0, total: 3))
    }

    @Test func sortsByTimeOrByWhatYouHave() async {
        let store = store()
        await store.setPantry([shelfItem(rice), shelfItem(beans)])
        let model = Sample.model(store: store)
        await model.load()
        model.sort = .quickest
        #expect(model.results.map(\.title) == ["Oat porridge", "Bean bowl", "Chana masala"])
        model.sort = .mostInPantry
        #expect(model.results.map(\.title) == ["Chana masala", "Bean bowl", "Oat porridge"])
        model.sort = .name
        #expect(model.results.map(\.title) == ["Bean bowl", "Chana masala", "Oat porridge"])
    }

    @Test func detailSaysWhatIsMissing() async throws {
        let store = store()
        await store.setPantry([shelfItem(rice)])
        let model = Sample.model(store: store)
        await model.load()
        let detail = try await model.detail(for: bowl)
        #expect(detail.missing(at: bowl.servings).map(\.rawText) == ["1 can black beans", "1 lime"])
        let lines = detail.scaled(to: bowl.servings)
        #expect(lines.map { detail.isInPantry($0) } == [true, false, false])
        #expect(!detail.hasConstraints)
    }

    @Test func optionalAndGarnishLinesAreNeverMissing() {
        let recipe = Sample.recipe("Tacos")
        var garnish = Sample.ingredient(recipe, "Coriander", quantity: 5, unit: .gram, food: lime)
        garnish.isGarnish = true
        var optional = Sample.ingredient(recipe, "Rice (optional)", quantity: 100, unit: .gram, food: rice)
        optional.isOptional = true
        let detail = RecipeDetail(
            recipe: recipe, ingredients: [garnish, optional],
            nutrition: NutritionCalculator().nutrition(for: recipe, ingredients: [], foods: [:]),
            verdict: .pass(softPenalties: []), showsNumbers: false
        )
        #expect(detail.missing(at: recipe.servings).isEmpty)
        #expect(PantryCoverage.of([garnish, optional], pantry: []).total == 0)
    }
}
