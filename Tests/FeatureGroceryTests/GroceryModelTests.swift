import Foundation
import Testing
import LarderCore
@testable import FeatureGrocery

let locale = Locale(identifier: "en_US")

@MainActor struct World {
    let store = FakeStore()
    let plan = MealPlan(startDate: Date(timeIntervalSince1970: 1_800_000_000), days: 7, constraintsSnapshot: "", solverVersion: "t", seed: 1, status: .active)
    let spinach = Food(name: "Spinach", source: .seedApproximate, foodGroup: .produce)
    let chicken = Food(name: "Chicken", source: .seedApproximate, foodGroup: .protein, tags: [.poultry])
    let milk = Food(name: "Milk", source: .seedApproximate, foodGroup: .dairy)
    let rice = Food(name: "Rice", source: .seedApproximate, foodGroup: .grains)
    let oil = Food(name: "Olive oil", source: .seedApproximate, foodGroup: .fats)
    let recipe = Recipe(title: "Stir fry", origin: .generated, servings: 2, prepMinutes: 5, cookMinutes: 10)

    func line(_ food: Food, grams: Double, in recipe: Recipe) -> Ingredient {
        Ingredient(recipeID: recipe.id, rawText: food.name, quantity: grams, unit: .gram, foodID: food.id, gramsResolved: grams, matchConfidence: 1)
    }

    func meal(_ status: MealStatus = .planned) -> PlannedMeal {
        PlannedMeal(planID: plan.id, date: plan.startDate, slot: .dinner, recipeID: recipe.id, servings: 2, status: status)
    }

    func model(meals: [PlannedMeal], lines: [Ingredient], pantry: [PantryItem] = []) async -> GroceryModel {
        await store.seed(
            plan: plan, meals: meals, recipes: [recipe], ingredients: [recipe.id: lines],
            foods: [spinach, chicken, milk, rice, oil], pantry: pantry
        )
        return GroceryModel(plans: store, recipes: store, foods: store, pantry: store, dates: FixedDates(), locale: locale)
    }

    func item(_ model: GroceryModel, _ name: String) throws -> GroceryItem {
        try #require(model.list?.items.first { $0.name == name })
    }
}

@MainActor @Suite struct GroceryModelTests {
    let world = World()

    @Test func loadAggregatesAcrossTwoPlannedMeals() async throws {
        let model = await world.model(
            meals: [world.meal(), world.meal()],
            lines: [world.line(world.spinach, grams: 100, in: world.recipe)]
        )
        await model.load()
        let spinach = try world.item(model, "Spinach")
        #expect(spinach.neededGrams == 200)
        #expect(spinach.forMeals.count == 2)
        #expect(model.error == nil)
        #expect(!model.isLoading)
    }

    @Test func loadSkipsCookedMeals() async throws {
        let model = await world.model(
            meals: [world.meal(), world.meal(.cooked)],
            lines: [world.line(world.spinach, grams: 100, in: world.recipe)]
        )
        await model.load()
        #expect(try world.item(model, "Spinach").neededGrams == 100)
    }

    @Test func loadWithoutPlanGivesEmptyList() async {
        let model = GroceryModel(plans: world.store, recipes: world.store, foods: world.store, pantry: world.store, dates: FixedDates(), locale: locale)
        await model.load()
        #expect(model.list?.items.isEmpty == true)
        #expect(model.isEmpty)
    }

    @Test func pantrySubtractionMarksPartiallyInPantry() async throws {
        let onShelf = PantryItem(foodID: world.spinach.id, rawName: "Spinach", quantityGrams: 30, location: .fridge, source: .manual, addedOn: .distantPast)
        let model = await world.model(
            meals: [world.meal()],
            lines: [world.line(world.spinach, grams: 100, in: world.recipe)],
            pantry: [onShelf]
        )
        await model.load()
        let spinach = try world.item(model, "Spinach")
        #expect(spinach.partiallyInPantry)
        #expect(spinach.neededGrams == 70)
    }

    @Test func fullyCoveredItemIsDropped() async {
        let onShelf = PantryItem(foodID: world.spinach.id, rawName: "Spinach", quantityGrams: 500, location: .fridge, source: .manual, addedOn: .distantPast)
        let model = await world.model(
            meals: [world.meal()],
            lines: [world.line(world.spinach, grams: 100, in: world.recipe)],
            pantry: [onShelf]
        )
        await model.load()
        #expect(model.isEmpty)
    }

    @Test func loadFailureSetsError() async {
        let model = await world.model(meals: [world.meal()], lines: [world.line(world.spinach, grams: 100, in: world.recipe)])
        await world.store.setFailReads(true)
        await model.load()
        #expect(model.error == .loadFailed)
        #expect(model.list == nil)
        #expect(!model.isLoading)
    }

    @Test func successfulLoadClearsEarlierError() async {
        let model = await world.model(meals: [world.meal()], lines: [world.line(world.spinach, grams: 100, in: world.recipe)])
        await world.store.setFailReads(true)
        await model.load()
        await world.store.setFailReads(false)
        await model.load()
        #expect(model.error == nil)
        #expect(model.list?.items.count == 1)
    }

    @Test func toggleWritesPantryItemWithGramsAndLocation() async throws {
        let model = await world.model(meals: [world.meal()], lines: [world.line(world.spinach, grams: 120, in: world.recipe)])
        await model.load()
        let spinach = try world.item(model, "Spinach")
        await model.toggle(spinach)
        let written = try #require(await world.store.upserts.first)
        #expect(written.quantityGrams == 120)
        #expect(written.foodID == world.spinach.id)
        #expect(written.location == .fridge)
        #expect(written.source == .manual)
        #expect(written.bestBy == nil)
        #expect(written.addedOn == FixedDates().now)
        #expect(model.checked.contains(GroceryItemKey(spinach)))
    }

    @Test(arguments: [
        ("Chicken", StorageLocation.fridge), ("Milk", .fridge), ("Spinach", .fridge),
        ("Rice", .pantry), ("Olive oil", .pantry),
    ])
    func locationFollowsFoodGroup(name: String, location: StorageLocation) async throws {
        let foods = [world.spinach, world.chicken, world.milk, world.rice, world.oil]
        let model = await world.model(meals: [world.meal()], lines: foods.map { world.line($0, grams: 50, in: world.recipe) })
        await model.load()
        await model.toggle(try world.item(model, name))
        #expect(await world.store.upserts.first?.location == location)
    }

    @Test func untoggleRemovesTheItemItCreated() async throws {
        let model = await world.model(meals: [world.meal()], lines: [world.line(world.spinach, grams: 120, in: world.recipe)])
        await model.load()
        let spinach = try world.item(model, "Spinach")
        await model.toggle(spinach)
        let created = try #require(await world.store.upserts.first?.id)
        await model.toggle(spinach)
        #expect(await world.store.removals == [created])
        #expect(model.checked.isEmpty)
    }

    @Test func itemsWithoutGramsTickWithoutWriting() async throws {
        let limes = Ingredient(recipeID: world.recipe.id, rawText: "limes", quantity: 2, unit: .piece)
        let model = await world.model(meals: [world.meal()], lines: [limes])
        await model.load()
        let item = try world.item(model, "limes")
        #expect(item.neededGrams == nil)
        await model.toggle(item)
        #expect(model.checked.contains(GroceryItemKey(item)))
        #expect(await world.store.upserts.isEmpty)
        await model.toggle(item)
        #expect(model.checked.isEmpty)
        #expect(await world.store.removals.isEmpty)
    }

    @Test func failedPantryWriteLeavesItemUnticked() async throws {
        let model = await world.model(meals: [world.meal()], lines: [world.line(world.spinach, grams: 120, in: world.recipe)])
        await model.load()
        await world.store.setFailPantryWrites(true)
        await model.toggle(try world.item(model, "Spinach"))
        #expect(model.error == .pantryUpdateFailed)
        #expect(model.checked.isEmpty)
    }

    @Test func failedPantryRemovalKeepsItemTicked() async throws {
        let model = await world.model(meals: [world.meal()], lines: [world.line(world.spinach, grams: 120, in: world.recipe)])
        await model.load()
        let spinach = try world.item(model, "Spinach")
        await model.toggle(spinach)
        await world.store.setFailPantryWrites(true)
        await model.toggle(spinach)
        #expect(model.error == .pantryUpdateFailed)
        #expect(model.checked.contains(GroceryItemKey(spinach)))
    }

    @Test func reloadKeepsTickedItemInBasket() async throws {
        let model = await world.model(meals: [world.meal()], lines: [world.line(world.spinach, grams: 120, in: world.recipe)])
        await model.load()
        await model.toggle(try world.item(model, "Spinach"))
        await model.load()
        let spinach = try world.item(model, "Spinach")
        #expect(spinach.neededGrams == 120)
        #expect(model.basket.flatMap(\.entries) == [.planned(spinach)])
    }

    @Test func manualItemsAreTrimmedAndBlankOnesIgnored() {
        let model = GroceryModel(plans: world.store, recipes: world.store, foods: world.store, pantry: world.store, dates: FixedDates(), locale: locale)
        model.addManual(name: "  Lemons ", quantity: " 3 ")
        model.addManual(name: "   ")
        #expect(model.manualItems.map(\.name) == ["Lemons"])
        #expect(model.manualItems.first?.quantity == "3")
    }

    @Test func manualItemsAppearInShareText() {
        let model = GroceryModel(plans: world.store, recipes: world.store, foods: world.store, pantry: world.store, dates: FixedDates(), locale: locale)
        model.addManual(name: "Oat milk", quantity: "2 cartons", aisle: .dairyAndEggs)
        model.addManual(name: "Candles")
        #expect(model.shareText() == "Dairy and eggs\n- 2 cartons Oat milk\n\nOther\n- Candles")
    }

    @Test func shareTextListsAislesInStoreWalkOrderWithoutCheckedItems() async throws {
        let model = await world.model(
            meals: [world.meal()],
            lines: [
                world.line(world.rice, grams: 500, in: world.recipe),
                world.line(world.spinach, grams: 250, in: world.recipe),
                world.line(world.milk, grams: 100, in: world.recipe),
            ]
        )
        await model.load()
        model.addManual(name: "Candles")
        #expect(model.shareText() == "Produce\n- 250 g Spinach\n\nDairy and eggs\n- 100 g Milk\n\nDry staples\n- 500 g Rice\n\nOther\n- Candles")
        await model.toggle(try world.item(model, "Milk"))
        #expect(!model.shareText().contains("Milk"))
        #expect(!model.shareText().contains("Dairy and eggs"))
    }

    @Test func shareTextIsEmptyWithNothingToBuy() {
        let model = GroceryModel(plans: world.store, recipes: world.store, foods: world.store, pantry: world.store, dates: FixedDates(), locale: locale)
        #expect(model.shareText().isEmpty)
    }

    @Test func removeManualDropsTheItem() {
        let model = GroceryModel(plans: world.store, recipes: world.store, foods: world.store, pantry: world.store, dates: FixedDates(), locale: locale)
        model.addManual(name: "Lemons")
        let item = model.manualItems[0]
        model.toggle(item)
        model.removeManual(item)
        #expect(model.manualItems.isEmpty)
        #expect(model.checked.isEmpty)
    }

    @Test func manualItemsTickWithoutTouchingThePantry() async {
        let model = GroceryModel(plans: world.store, recipes: world.store, foods: world.store, pantry: world.store, dates: FixedDates(), locale: locale)
        model.addManual(name: "Lemons")
        await model.toggle(GroceryEntry.manual(model.manualItems[0]))
        #expect(model.basket.flatMap(\.entries).count == 1)
        #expect(model.toBuy.isEmpty)
        #expect(await world.store.upserts.isEmpty)
    }

    @Test func clearCheckedEmptiesTheBasketAndKeepsTheRest() async throws {
        let model = await world.model(
            meals: [world.meal()],
            lines: [world.line(world.spinach, grams: 100, in: world.recipe), world.line(world.rice, grams: 200, in: world.recipe)]
        )
        await model.load()
        model.addManual(name: "Lemons")
        model.addManual(name: "Candles")
        await model.toggle(try world.item(model, "Spinach"))
        model.toggle(model.manualItems[0])
        model.clearChecked()
        #expect(model.checked.isEmpty)
        #expect(model.manualItems.map(\.name) == ["Candles"])
        #expect(model.list?.items.map(\.name) == ["Rice"])
        #expect(model.basket.isEmpty)
        #expect(await world.store.removals.isEmpty)
    }

    @Test func keysMatchForTheSameFoodWhateverItsName() {
        let id = FoodID()
        let a = GroceryItem(name: "Spinach", foodID: id, neededGrams: 10, displayQuantity: Quantity(value: 10, unit: .gram), aisle: .produce, partiallyInPantry: false, forMeals: [])
        let b = GroceryItem(name: "Baby spinach", foodID: id, neededGrams: 99, displayQuantity: Quantity(value: 99, unit: .gram), aisle: .produce, partiallyInPantry: true, forMeals: [])
        let other = GroceryItem(name: "Spinach", foodID: FoodID(), neededGrams: 10, displayQuantity: Quantity(value: 10, unit: .gram), aisle: .produce, partiallyInPantry: false, forMeals: [])
        #expect(GroceryItemKey(a) == GroceryItemKey(b))
        #expect(GroceryItemKey(a) != GroceryItemKey(other))
    }

    @Test func keysMatchForTheSameNormalisedNameWithoutAFood() {
        func text(_ name: String, unit: UnitOfMeasure = .piece) -> GroceryItem {
            GroceryItem(name: name, foodID: nil, neededGrams: nil, displayQuantity: Quantity(value: 1, unit: unit), aisle: .other, partiallyInPantry: false, forMeals: [])
        }
        #expect(GroceryItemKey(text("Crème  Fraîche")) == GroceryItemKey(text(" creme fraiche ")))
        #expect(GroceryItemKey(text("Limes")) != GroceryItemKey(text("Lemons")))
        #expect(GroceryItemKey(text("Limes", unit: .piece)) != GroceryItemKey(text("Limes", unit: .tablespoon)))
    }
}

@Suite("Grocery names")
struct GroceryNameTests {
    @Test func databaseNamesReadAsShoppersWriteThem() {
        #expect(GroceryCopy.shoppingName("Potato, raw, flesh and skin") == "Potato")
        #expect(GroceryCopy.shoppingName("Ginger root, raw") == "Ginger root")
        #expect(GroceryCopy.shoppingName("Lemons") == "Lemons")
        #expect(GroceryCopy.shoppingName(", odd") == ", odd")
    }
}
