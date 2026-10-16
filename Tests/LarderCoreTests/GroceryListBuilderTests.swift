import Foundation
import Testing
@testable import LarderCore

struct GroceryListBuilderTests {
    let builder = GroceryListBuilder()
    let planID = MealPlanID()

    private func meal(_ recipe: Recipe, servings: Int, status: MealStatus = .planned, leftoverOf: PlannedMealID? = nil) -> PlannedMeal {
        PlannedMeal(
            planID: planID, date: Fixtures.date(2026, 10, 19), slot: .dinner, recipeID: recipe.id, servings: servings,
            leftoverOf: leftoverOf, status: status
        )
    }

    private func pantryItem(_ food: Food, grams: Double) -> PantryItem {
        PantryItem(foodID: food.id, rawName: food.name, quantityGrams: grams, location: .pantry, source: .manual, addedOn: Fixtures.date(2026, 10, 1))
    }

    private func build(
        _ meals: [PlannedMeal],
        recipes: [Recipe],
        lines: [Ingredient],
        foods: [Food],
        pantry: [PantryItem] = []
    ) -> GroceryList {
        builder.build(
            meals: meals,
            recipes: Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) }),
            ingredients: Dictionary(grouping: lines, by: \.recipeID),
            foods: Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) }),
            pantry: pantry
        )
    }

    @Test func aggregatesSameFoodAcrossTwoMealsScaledByServings() throws {
        let rice = Kitchen.food("Basmati rice", group: .grains)
        let curry = Kitchen.recipe("Curry", servings: 4)
        let bowl = Kitchen.recipe("Rice bowl", servings: 1)
        let lines = [
            Kitchen.line("300 g rice", 300, food: rice, recipe: curry.id),
            Kitchen.line("80 g rice", 80, food: rice, recipe: bowl.id),
        ]
        let first = meal(curry, servings: 2)
        let second = meal(bowl, servings: 2)

        let list = build([first, second], recipes: [curry, bowl], lines: lines, foods: [rice])

        // 300 g * 2/4 + 80 g * 2/1 = 150 + 160 = 310 g
        let item = try #require(list.items.first)
        #expect(list.items.count == 1)
        #expect(Kitchen.isClose(item.neededGrams, 310))
        #expect(item.forMeals == [first.id, second.id])
        #expect(item.foodID == rice.id)
        #expect(item.name == "Basmati rice")
        #expect(!item.partiallyInPantry)
    }

    @Test func pantryCoversPartOfTheNeed() throws {
        let rice = Kitchen.food("Rice", group: .grains)
        let recipe = Kitchen.recipe(servings: 2)
        let lines = [Kitchen.line("400 g rice", 400, food: rice, recipe: recipe.id)]

        let list = build([meal(recipe, servings: 2)], recipes: [recipe], lines: lines, foods: [rice], pantry: [
            pantryItem(rice, grams: 100), pantryItem(rice, grams: 50),
        ])

        // 400 - (100 + 50) = 250 g
        let item = try #require(list.items.first)
        #expect(Kitchen.isClose(item.neededGrams, 250))
        #expect(item.partiallyInPantry)
    }

    @Test func fullyCoveredItemsAreDropped() {
        let rice = Kitchen.food("Rice", group: .grains)
        let recipe = Kitchen.recipe(servings: 2)
        let lines = [Kitchen.line("400 g rice", 400, food: rice, recipe: recipe.id)]

        let exact = build([meal(recipe, servings: 2)], recipes: [recipe], lines: lines, foods: [rice], pantry: [pantryItem(rice, grams: 400)])
        let surplus = build([meal(recipe, servings: 2)], recipes: [recipe], lines: lines, foods: [rice], pantry: [pantryItem(rice, grams: 1000)])

        #expect(exact.items.isEmpty)
        #expect(surplus.sections.isEmpty)
    }

    @Test func invalidPantryQuantitiesAreIgnored() throws {
        let rice = Kitchen.food("Rice", group: .grains)
        let recipe = Kitchen.recipe(servings: 1)
        let lines = [Kitchen.line("100 g rice", 100, food: rice, recipe: recipe.id)]

        let list = build([meal(recipe, servings: 1)], recipes: [recipe], lines: lines, foods: [rice], pantry: [
            pantryItem(rice, grams: -50), pantryItem(rice, grams: .nan),
        ])

        let item = try #require(list.items.first)
        #expect(Kitchen.isClose(item.neededGrams, 100))
        #expect(!item.partiallyInPantry)
    }

    @Test func garnishIsSkipped() {
        let parsley = Kitchen.food("Parsley", group: .produce)
        let recipe = Kitchen.recipe(servings: 1)
        let lines = [Kitchen.line("parsley to serve", 5, food: parsley, recipe: recipe.id, garnish: true)]

        let list = build([meal(recipe, servings: 1)], recipes: [recipe], lines: lines, foods: [parsley])

        #expect(list.items.isEmpty)
    }

    @Test func cookedSkippedAndLeftoverMealsNeedNothing() {
        let rice = Kitchen.food("Rice", group: .grains)
        let recipe = Kitchen.recipe(servings: 1)
        let lines = [Kitchen.line("100 g rice", 100, food: rice, recipe: recipe.id)]
        let meals = [
            meal(recipe, servings: 1, status: .cooked),
            meal(recipe, servings: 1, status: .skipped),
            meal(recipe, servings: 1, leftoverOf: PlannedMealID()),
            meal(recipe, servings: 0),
        ]

        #expect(build(meals, recipes: [recipe], lines: lines, foods: [rice]).items.isEmpty)
    }

    @Test func mealWithUnknownRecipeIsIgnored() {
        let recipe = Kitchen.recipe(servings: 1)

        #expect(build([meal(recipe, servings: 1)], recipes: [], lines: [], foods: []).items.isEmpty)
    }

    @Test func unmatchedLinesAggregateByNormalisedText() throws {
        let recipe = Kitchen.recipe(servings: 1)
        let lines = [
            Kitchen.line("Fresh  Basil", 10, recipe: recipe.id),
            Kitchen.line("fresh basil ", 15, recipe: recipe.id),
        ]

        let list = build([meal(recipe, servings: 1)], recipes: [recipe], lines: lines, foods: [])

        let item = try #require(list.items.first)
        #expect(list.items.count == 1)
        #expect(Kitchen.isClose(item.neededGrams, 25))
        #expect(item.foodID == nil)
        #expect(item.name == "Fresh  Basil")
        #expect(item.aisle == .other)
    }

    @Test func linesThatCannotBeWeighedKeepTheirUnit() throws {
        let garlic = Kitchen.food("Garlic", group: .produce)
        let recipe = Kitchen.recipe(servings: 2)
        let lines = [Kitchen.line("2 cloves garlic", 2, .clove, food: garlic, recipe: recipe.id)]

        let list = build([meal(recipe, servings: 4)], recipes: [recipe], lines: lines, foods: [garlic], pantry: [pantryItem(garlic, grams: 30)])

        let item = try #require(list.items.first)
        #expect(item.neededGrams == nil)
        #expect(item.displayQuantity == Quantity(value: 4, unit: .clove))
        #expect(item.partiallyInPantry)
    }

    @Test func displayQuantityUsesMostCommonMassUnit() throws {
        let flour = Kitchen.food("Flour", group: .grains)
        let first = Kitchen.recipe("Bread", servings: 1)
        let second = Kitchen.recipe("Pancakes", servings: 1)
        let third = Kitchen.recipe("Cake", servings: 1)
        let lines = [
            Kitchen.line("0.5 kg flour", 0.5, .kilogram, food: flour, recipe: first.id),
            Kitchen.line("0.25 kg flour", 0.25, .kilogram, food: flour, recipe: second.id),
            Kitchen.line("250 g flour", 250, food: flour, recipe: third.id),
        ]

        let list = build([meal(first, servings: 1), meal(second, servings: 1), meal(third, servings: 1)], recipes: [first, second, third], lines: lines, foods: [flour])

        // 500 + 250 + 250 = 1000 g = 1 kg
        let item = try #require(list.items.first)
        #expect(Kitchen.isClose(item.neededGrams, 1000))
        #expect(item.displayQuantity.unit == .kilogram)
        #expect(Kitchen.isClose(item.displayQuantity.value, 1))
    }

    @Test func displayQuantityConvertsCountUnitsThroughPortion() throws {
        let onion = Kitchen.food("Onion", group: .produce, portions: [Portion(label: "1 medium", grams: 110)])
        let recipe = Kitchen.recipe(servings: 2)
        let lines = [Kitchen.line("3 onions", 3, .piece, food: onion, recipe: recipe.id)]

        let list = build([meal(recipe, servings: 2)], recipes: [recipe], lines: lines, foods: [onion], pantry: [pantryItem(onion, grams: 110)])

        // 3 * 110 g - 110 g = 220 g = 2 pieces
        let item = try #require(list.items.first)
        #expect(Kitchen.isClose(item.neededGrams, 220))
        #expect(item.displayQuantity.unit == .piece)
        #expect(Kitchen.isClose(item.displayQuantity.value, 2))
    }

    @Test func displayQuantityConvertsVolumeThroughDensity() throws {
        let milk = Kitchen.food("Whole milk", group: .dairy, density: 1.03, tags: [.dairy])
        let recipe = Kitchen.recipe(servings: 1)
        let lines = [Kitchen.line("2 cups milk", 2, .cup, food: milk, recipe: recipe.id)]

        let list = build([meal(recipe, servings: 1)], recipes: [recipe], lines: lines, foods: [milk])

        // 2 * 236.59 ml * 1.03 g/ml = 487.3754 g, shown as 2 cups
        let item = try #require(list.items.first)
        #expect(Kitchen.isClose(item.neededGrams, 487.3754))
        #expect(item.displayQuantity.unit == .cup)
        #expect(Kitchen.isClose(item.displayQuantity.value, 2))
    }

    @Test func displayQuantityFallsBackToGramsWithoutDensity() throws {
        let stock = Kitchen.food("Chicken stock", group: .other)
        let recipe = Kitchen.recipe(servings: 1)
        let lines = [Kitchen.line("1 cup stock", 1, .cup, food: stock, recipe: recipe.id, grams: 240)]

        let list = build([meal(recipe, servings: 1)], recipes: [recipe], lines: lines, foods: [stock])

        let item = try #require(list.items.first)
        #expect(item.displayQuantity == Quantity(value: 240, unit: .gram))
    }

    static let aisleCases: [(String, FoodGroup, Set<FoodTag>, Aisle)] = [
        ("Spinach", .produce, [], .produce),
        ("Sourdough bread", .grains, [], .bakery),
        ("Chicken thigh", .protein, [.poultry, .meat], .meatAndFish),
        ("Salmon fillet", .protein, [.fish], .meatAndFish),
        ("Eggs", .protein, [.egg], .dairyAndEggs),
        ("Cheddar", .dairy, [.dairy], .dairyAndEggs),
        ("Brown rice", .grains, [], .pantryDry),
        ("Red lentils", .legumes, [], .pantryDry),
        ("Canned chickpeas", .legumes, [], .cannedAndJarred),
        ("Frozen peas", .produce, [], .frozen),
        ("Olive oil", .fats, [], .spicesAndOils),
        ("Ground cumin", .other, [], .spicesAndOils),
        ("Firm tofu", .protein, [], .other),
    ]

    @Test(arguments: aisleCases)
    func aisleComesFromNameTagsAndGroup(name: String, group: FoodGroup, tags: Set<FoodTag>, aisle: Aisle) throws {
        let food = Kitchen.food(name, group: group, tags: tags)
        let recipe = Kitchen.recipe(servings: 1)
        let lines = [Kitchen.line(name, 100, food: food, recipe: recipe.id)]

        let list = build([meal(recipe, servings: 1)], recipes: [recipe], lines: lines, foods: [food])

        #expect(try #require(list.items.first).aisle == aisle)
    }

    @Test func sectionsFollowStoreWalkOrderAndSortItemsByName() {
        let recipe = Kitchen.recipe(servings: 1)
        let foods = [
            Kitchen.food("Salt", group: .other),
            Kitchen.food("Kale", group: .produce),
            Kitchen.food("Apples", group: .produce),
            Kitchen.food("Frozen berries", group: .produce),
            Kitchen.food("Butter", group: .fats, tags: [.dairy]),
        ]
        let lines = foods.map { Kitchen.line($0.name, 100, food: $0, recipe: recipe.id) }

        let list = build([meal(recipe, servings: 1)], recipes: [recipe], lines: lines, foods: foods)

        #expect(list.sections.map(\.aisle) == [.produce, .dairyAndEggs, .frozen, .spicesAndOils])
        #expect(list.sections.first?.items.map(\.name) == ["Apples", "Kale"])
    }
}
