import Foundation
import Testing
@testable import LarderCore

@Suite("Cooking draw")
struct CookingDrawTests {
    let planID = MealPlanID()

    private func meal(_ recipe: Recipe, servings: Int, leftoverOf: PlannedMealID? = nil) -> PlannedMeal {
        PlannedMeal(planID: planID, date: Fixtures.date(2026, 10, 19), slot: .dinner, recipeID: recipe.id, servings: servings, leftoverOf: leftoverOf)
    }

    @Test func scalesEachLineByMealServingsOverRecipeServings() {
        let rice = Kitchen.food("Rice", group: .grains)
        let onion = Kitchen.food("Onion", group: .produce)
        let curry = Kitchen.recipe("Curry", servings: 4)
        let lines = [
            Kitchen.line("300 g rice", 300, food: rice, recipe: curry.id, grams: 300),
            Kitchen.line("1 onion", 1, .piece, food: onion, recipe: curry.id, grams: 150),
        ]

        let amounts = CookingDraw.amounts(cooking: meal(curry, servings: 6), recipe: curry, ingredients: lines, foods: Kitchen.foods(rice, onion))

        // 300 g * 6/4 = 450 g; 150 g * 6/4 = 225 g
        #expect(amounts == [FoodAmount(foodID: rice.id, grams: 450), FoodAmount(foodID: onion.id, grams: 225)])
    }

    @Test func linesOfTheSameFoodAddUpInFirstSeenOrder() {
        let garlic = Kitchen.food("Garlic", group: .produce)
        let oil = Kitchen.food("Olive oil", group: .fats)
        let recipe = Kitchen.recipe(servings: 2)
        let lines = [
            Kitchen.line("garlic for the base", food: garlic, recipe: recipe.id, grams: 10),
            Kitchen.line("oil", food: oil, recipe: recipe.id, grams: 20),
            Kitchen.line("garlic to finish", food: garlic, recipe: recipe.id, grams: 5),
        ]

        let amounts = CookingDraw.amounts(recipe: recipe, servings: 2, ingredients: lines, foods: Kitchen.foods(garlic, oil))

        #expect(amounts == [FoodAmount(foodID: garlic.id, grams: 15), FoodAmount(foodID: oil.id, grams: 20)])
    }

    @Test func leftoverTakesNothing() {
        let rice = Kitchen.food("Rice", group: .grains)
        let recipe = Kitchen.recipe(servings: 2)
        let lines = [Kitchen.line("rice", food: rice, recipe: recipe.id, grams: 200)]
        let cooked = meal(recipe, servings: 4)

        let leftover = meal(recipe, servings: 2, leftoverOf: cooked.id)

        #expect(CookingDraw.amounts(cooking: leftover, recipe: recipe, ingredients: lines, foods: Kitchen.foods(rice)).isEmpty)
        #expect(CookingDraw.amounts(cooking: cooked, recipe: recipe, ingredients: lines, foods: Kitchen.foods(rice))
            == [FoodAmount(foodID: rice.id, grams: 400)])
    }

    @Test func optionalGarnishUnmatchedAndUnweighableLinesAreLeftOut() {
        let rice = Kitchen.food("Rice", group: .grains)
        let parsley = Kitchen.food("Parsley", group: .produce)
        let chilli = Kitchen.food("Chilli", group: .produce)
        let lemon = Kitchen.food("Lemon", group: .produce)
        let recipe = Kitchen.recipe(servings: 2)
        let lines = [
            Kitchen.line("rice", food: rice, recipe: recipe.id, grams: 200),
            Kitchen.line("parsley", food: parsley, recipe: recipe.id, grams: 5, garnish: true),
            Kitchen.line("chilli", food: chilli, recipe: recipe.id, grams: 3, optional: true),
            Kitchen.line("a mystery spice", recipe: recipe.id, grams: 2),
            // A count with no portion on the food cannot become grams.
            Kitchen.line("1 lemon", 1, .piece, food: lemon, recipe: recipe.id),
        ]

        let amounts = CookingDraw.amounts(recipe: recipe, servings: 2, ingredients: lines, foods: Kitchen.foods(rice, parsley, chilli, lemon))

        #expect(amounts == [FoodAmount(foodID: rice.id, grams: 200)])
    }

    @Test func unresolvedLinesConvertWithTheFoodsPortion() {
        let egg = Kitchen.food("Egg", group: .protein, portions: [Portion(label: "1 large", grams: 50)])
        let recipe = Kitchen.recipe(servings: 2)
        let lines = [Kitchen.line("3 eggs", 3, .piece, food: egg, recipe: recipe.id)]

        #expect(CookingDraw.amounts(recipe: recipe, servings: 4, ingredients: lines, foods: Kitchen.foods(egg))
            == [FoodAmount(foodID: egg.id, grams: 300)])
    }

    @Test(arguments: [0, -2])
    func noServingsTakeNothing(servings: Int) {
        let rice = Kitchen.food("Rice", group: .grains)
        let recipe = Kitchen.recipe(servings: 2)
        let lines = [Kitchen.line("rice", food: rice, recipe: recipe.id, grams: 200)]
        #expect(CookingDraw.amounts(recipe: recipe, servings: servings, ingredients: lines, foods: Kitchen.foods(rice)).isEmpty)
    }

    @Test func recipeWithZeroServingsCountsAsOne() {
        let rice = Kitchen.food("Rice", group: .grains)
        let recipe = Kitchen.recipe(servings: 0)
        let lines = [Kitchen.line("rice", food: rice, recipe: recipe.id, grams: 100)]
        #expect(CookingDraw.amounts(recipe: recipe, servings: 3, ingredients: lines, foods: Kitchen.foods(rice))
            == [FoodAmount(foodID: rice.id, grams: 300)])
    }

    @Test func linesOfAnotherRecipeOrAMealOfAnotherRecipeTakeNothing() {
        let rice = Kitchen.food("Rice", group: .grains)
        let recipe = Kitchen.recipe(servings: 2)
        let other = Kitchen.recipe("Other", servings: 2)
        let stray = [Kitchen.line("rice", food: rice, recipe: other.id, grams: 100)]
        let own = [Kitchen.line("rice", food: rice, recipe: recipe.id, grams: 100)]
        #expect(CookingDraw.amounts(recipe: recipe, servings: 2, ingredients: stray, foods: Kitchen.foods(rice)).isEmpty)
        #expect(CookingDraw.amounts(cooking: meal(other, servings: 2), recipe: recipe, ingredients: own, foods: Kitchen.foods(rice)).isEmpty)
    }
}
