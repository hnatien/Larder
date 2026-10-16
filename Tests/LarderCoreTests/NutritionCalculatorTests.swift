import Foundation
import Testing
@testable import LarderCore

struct NutritionCalculatorTests {
    let calculator = NutritionCalculator()

    @Test func goldenTwoIngredientRecipe() {
        let chicken = Kitchen.food("Chicken breast", nutrients: Nutrients(energyKcal: 165, proteinG: 31, fatG: 3.6, sodiumMg: 74))
        let rice = Kitchen.food("Cooked rice", nutrients: Nutrients(energyKcal: 130, proteinG: 2.7, fatG: 0.3, fiberG: 0.4, sodiumMg: 1))
        let recipe = Kitchen.recipe(servings: 2)
        let lines = [
            Kitchen.line("200 g chicken", 200, food: chicken, recipe: recipe.id),
            Kitchen.line("150 g rice", 150, food: rice, recipe: recipe.id),
        ]

        let result = calculator.nutrition(for: recipe, ingredients: lines, foods: Kitchen.foods(chicken, rice))

        // energy: 165 * 2.0 + 130 * 1.5 = 330 + 195 = 525 kcal
        #expect(Kitchen.isClose(result.perRecipe.energyKcal, 525))
        // protein: 31 * 2.0 + 2.7 * 1.5 = 62 + 4.05 = 66.05 g
        #expect(Kitchen.isClose(result.perRecipe.proteinG, 66.05))
        // fat: 3.6 * 2.0 + 0.3 * 1.5 = 7.2 + 0.45 = 7.65 g
        #expect(Kitchen.isClose(result.perRecipe.fatG, 7.65))
        // sodium: 74 * 2.0 + 1 * 1.5 = 148 + 1.5 = 149.5 mg
        #expect(Kitchen.isClose(result.perRecipe.sodiumMg, 149.5))
        // fibre: chicken unknown, rice 0.4 * 1.5 = 0.6 g
        #expect(Kitchen.isClose(result.perRecipe.fiberG, 0.6))
        #expect(result.perRecipe.saturatedFatG == nil)
        // per serving: 525 / 2 = 262.5 kcal, 66.05 / 2 = 33.025 g protein
        #expect(Kitchen.isClose(result.perServing.energyKcal, 262.5))
        #expect(Kitchen.isClose(result.perServing.proteinG, 33.025))
        #expect(result.coverage == 1)
        #expect(result.unresolved.isEmpty)
    }

    @Test func coverageIsShareOfResolvedGramsWithEnergy() {
        let withEnergy = Kitchen.food("Oats", nutrients: Nutrients(energyKcal: 380))
        let withoutEnergy = Kitchen.food("Mystery stock", nutrients: Nutrients(sodiumMg: 400))
        let recipe = Kitchen.recipe()
        let lines = [
            Kitchen.line("oats", 100, food: withEnergy, recipe: recipe.id),
            Kitchen.line("stock", 300, food: withoutEnergy, recipe: recipe.id),
        ]

        let result = calculator.nutrition(for: recipe, ingredients: lines, foods: Kitchen.foods(withEnergy, withoutEnergy))

        // 100 g of 400 g resolved grams have energy data
        #expect(result.coverage == 0.25)
        #expect(Kitchen.isClose(result.perRecipe.energyKcal, 380))
    }

    @Test func unresolvedListsLinesWithoutFoodOrGrams() {
        let oil = Kitchen.food("Oil", nutrients: Nutrients(energyKcal: 884))
        let rice = Kitchen.food("Rice", nutrients: Nutrients(energyKcal: 130))
        let recipe = Kitchen.recipe()
        let noFood = Kitchen.line("a splash of something", 1, .tablespoon, recipe: recipe.id)
        let missingFood = Kitchen.line("rice", 100, food: rice, recipe: recipe.id)
        let noDensity = Kitchen.line("1 tbsp oil", 1, .tablespoon, food: oil, recipe: recipe.id)

        let result = calculator.nutrition(for: recipe, ingredients: [noFood, missingFood, noDensity], foods: Kitchen.foods(oil))

        #expect(result.unresolved == [noFood.id, missingFood.id, noDensity.id])
        #expect(result.coverage == 0)
        #expect(result.perRecipe == Nutrients())
    }

    @Test func garnishIsSkippedAndNotUnresolved() {
        let parsley = Kitchen.food("Parsley", nutrients: Nutrients(energyKcal: 36))
        let recipe = Kitchen.recipe()
        let garnish = Kitchen.line("parsley to serve", 10, food: parsley, recipe: recipe.id, garnish: true)
        let unmatchedGarnish = Kitchen.line("lemon wedge", 1, .piece, recipe: recipe.id, garnish: true)

        let result = calculator.nutrition(for: recipe, ingredients: [garnish, unmatchedGarnish], foods: Kitchen.foods(parsley))

        #expect(result.perRecipe.energyKcal == nil)
        #expect(result.unresolved.isEmpty)
    }

    @Test func optionalIngredientsCount() {
        let cheese = Kitchen.food("Cheddar", nutrients: Nutrients(energyKcal: 400))
        let recipe = Kitchen.recipe(servings: 1)
        let line = Kitchen.line("cheddar (optional)", 50, food: cheese, recipe: recipe.id, optional: true)

        let result = calculator.nutrition(for: recipe, ingredients: [line], foods: Kitchen.foods(cheese))

        // 400 * 0.5 = 200 kcal
        #expect(Kitchen.isClose(result.perRecipe.energyKcal, 200))
    }

    @Test func gramsResolvedWinsOverUnitConversion() {
        let flour = Kitchen.food("Flour", nutrients: Nutrients(energyKcal: 364), density: 0.53)
        let recipe = Kitchen.recipe(servings: 1)
        let line = Kitchen.line("1 cup flour", 1, .cup, food: flour, recipe: recipe.id, grams: 120)

        let result = calculator.nutrition(for: recipe, ingredients: [line], foods: Kitchen.foods(flour))

        // 364 * 1.2 = 436.8 kcal, not the density figure
        #expect(Kitchen.isClose(result.perRecipe.energyKcal, 436.8))
    }

    @Test func countUnitUsesPortionWhoseLabelNamesTheUnit() {
        let garlic = Kitchen.food(
            "Garlic",
            nutrients: Nutrients(energyKcal: 149),
            portions: [Portion(label: "1 medium bulb", grams: 40), Portion(label: "1 clove", grams: 3)]
        )
        let recipe = Kitchen.recipe(servings: 1)
        let line = Kitchen.line("3 cloves garlic", 3, .clove, food: garlic, recipe: recipe.id)

        let result = calculator.nutrition(for: recipe, ingredients: [line], foods: Kitchen.foods(garlic))

        // 3 cloves * 3 g = 9 g; 149 * 0.09 = 13.41 kcal
        #expect(Kitchen.isClose(result.perRecipe.energyKcal, 13.41))
    }

    @Test func countUnitFallsBackToFirstPortion() {
        let apple = Kitchen.food(
            "Apple",
            nutrients: Nutrients(energyKcal: 52),
            portions: [Portion(label: "1 medium", grams: 182), Portion(label: "1 cup sliced", grams: 109)]
        )
        let recipe = Kitchen.recipe(servings: 1)
        let line = Kitchen.line("2 apples", 2, .piece, food: apple, recipe: recipe.id)

        let result = calculator.nutrition(for: recipe, ingredients: [line], foods: Kitchen.foods(apple))

        // 2 * 182 g = 364 g; 52 * 3.64 = 189.28 kcal
        #expect(Kitchen.isClose(result.perRecipe.energyKcal, 189.28))
    }

    @Test func countUnitWithoutPortionIsUnresolved() {
        let egg = Kitchen.food("Egg", nutrients: Nutrients(energyKcal: 143))
        let recipe = Kitchen.recipe()
        let line = Kitchen.line("2 eggs", 2, .piece, food: egg, recipe: recipe.id)

        let result = calculator.nutrition(for: recipe, ingredients: [line], foods: Kitchen.foods(egg))

        #expect(result.unresolved == [line.id])
    }

    @Test func volumeUsesFoodDensity() {
        let oil = Kitchen.food("Olive oil", nutrients: Nutrients(energyKcal: 884, fatG: 100), density: 0.91)
        let recipe = Kitchen.recipe(servings: 1)
        let line = Kitchen.line("2 tbsp olive oil", 2, .tablespoon, food: oil, recipe: recipe.id)

        let result = calculator.nutrition(for: recipe, ingredients: [line], foods: Kitchen.foods(oil))

        // 2 * 14.79 ml * 0.91 g/ml = 26.9178 g; fat 100 * 0.269178 = 26.9178 g; energy 884 * 0.269178 = 237.953352
        #expect(Kitchen.isClose(result.perRecipe.fatG, 26.9178))
        #expect(Kitchen.isClose(result.perRecipe.energyKcal, 237.953352))
    }

    @Test func emptyRecipeHasNoDataAndZeroCoverage() {
        let result = calculator.nutrition(for: Kitchen.recipe(), ingredients: [], foods: [:])

        #expect(result.perRecipe == Nutrients())
        #expect(result.perServing == Nutrients())
        #expect(result.coverage == 0)
        #expect(result.unresolved.isEmpty)
    }

    @Test func zeroServingRecipeCountsAsOneServing() {
        let rice = Kitchen.food("Rice", nutrients: Nutrients(energyKcal: 130))
        let recipe = Kitchen.recipe(servings: 0)
        let line = Kitchen.line("rice", 100, food: rice, recipe: recipe.id)

        let result = calculator.nutrition(for: recipe, ingredients: [line], foods: Kitchen.foods(rice))

        #expect(result.perServing == result.perRecipe)
    }

    @Test func scalingServings() {
        let nutrients = Nutrients(energyKcal: 800, proteinG: 40)

        let scaled = calculator.scaled(nutrients, servings: 4, to: 6)

        // factor 6 / 4 = 1.5
        #expect(Kitchen.isClose(scaled.energyKcal, 1200))
        #expect(Kitchen.isClose(scaled.proteinG, 60))
        #expect(scaled.fatG == nil)
        #expect(calculator.scaled(nutrients, servings: 0, to: 2) == nutrients.scaled(by: 2))
        #expect(calculator.scaled(nutrients, servings: 4, to: -1).energyKcal == 0)
    }
}
