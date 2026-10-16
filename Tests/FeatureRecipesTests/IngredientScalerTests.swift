import LarderCore
import Testing
@testable import FeatureRecipes

struct IngredientScalerTests {
    private let recipe = Sample.recipe("Scaling")

    private func line(_ text: String, _ quantity: Double, _ unit: UnitOfMeasure, grams: Double? = nil) -> Ingredient {
        Ingredient(recipeID: recipe.id, rawText: text, quantity: quantity, unit: unit, gramsResolved: grams)
    }

    @Test func sameServingsReturnsIngredientsUntouched() {
        let lines = [line("2 cups flour", 2, .cup)]
        #expect(IngredientScaler.scale(ingredients: lines, from: 4, to: 4) == lines)
    }

    @Test(arguments: [(0, 4), (4, 0), (-2, 4), (4, -1)] as [(Int, Int)])
    func nonPositiveServingsReturnIngredientsUntouched(source: Int, target: Int) {
        let lines = [line("2 cups flour", 2, .cup)]
        #expect(IngredientScaler.scale(ingredients: lines, from: source, to: target) == lines)
    }

    @Test func doublingScalesQuantityAndText() {
        let scaled = IngredientScaler.scale(ingredients: [line("2 cups flour", 2, .cup)], from: 4, to: 8)
        #expect(scaled[0].quantity == 4)
        #expect(scaled[0].rawText == "4 cups flour")
    }

    @Test func halvingRoundsToQuarters() {
        let scaled = IngredientScaler.scale(ingredients: [line("1 tsp salt", 1, .teaspoon)], from: 4, to: 1)
        #expect(scaled[0].quantity == 0.25)
        #expect(scaled[0].rawText == "\u{BC} tsp salt")
    }

    @Test func mixedNumbersScaleInText() {
        let scaled = IngredientScaler.scale(ingredients: [line("1 cup milk", 1, .cup)], from: 4, to: 6)
        #expect(scaled[0].quantity == 1.5)
        #expect(scaled[0].rawText == "1 \u{BD} cup milk")
    }

    @Test func gramsRoundToFiveFromFifty() {
        let scaled = IngredientScaler.scale(ingredients: [line("100 g rice", 100, .gram)], from: 3, to: 7)
        #expect(scaled[0].quantity == 235)
        #expect(scaled[0].rawText == "235 g rice")
    }

    @Test func smallGramsKeepHalfGramSteps() {
        let scaled = IngredientScaler.scale(ingredients: [line("10 g yeast", 10, .gram)], from: 4, to: 3)
        #expect(scaled[0].quantity == 7.5)
    }

    @Test func rangesScaleBothEnds() {
        let scaled = IngredientScaler.scale(ingredients: [line("2-3 cloves garlic", 3, .clove)], from: 4, to: 8)
        #expect(scaled[0].rawText == "4-6 cloves garlic")
        #expect(scaled[0].quantity == 6)
    }

    @Test func countInParenthesisedPackSizeScalesTheCount() {
        let scaled = IngredientScaler.scale(ingredients: [line("1 (400 g) can chickpeas", 400, .gram)], from: 4, to: 8)
        #expect(scaled[0].rawText == "2 (400 g) can chickpeas")
        #expect(scaled[0].quantity == 800)
    }

    @Test func glyphStuckToTheNumberScales() {
        let scaled = IngredientScaler.scale(ingredients: [line("400g spaghetti", 400, .gram)], from: 4, to: 6)
        #expect(scaled[0].rawText == "600g spaghetti")
    }

    @Test func linesWithoutAmountsStayAsWritten() {
        let scaled = IngredientScaler.scale(ingredients: [line("salt to taste", 0, .piece)], from: 4, to: 8)
        #expect(scaled[0].quantity == 0)
        #expect(scaled[0].rawText == "salt to taste")
    }

    @Test func resolvedGramsScaleExactly() {
        let scaled = IngredientScaler.scale(ingredients: [line("2 cans chickpeas", 480, .gram, grams: 480)], from: 4, to: 6)
        #expect(scaled[0].gramsResolved == 720)
        #expect(scaled[0].rawText == "3 cans chickpeas")
    }

    @Test func identityAndOrderArePreserved() {
        let lines = [line("1 cup milk", 1, .cup), line("2 eggs", 2, .piece)]
        let scaled = IngredientScaler.scale(ingredients: lines, from: 2, to: 4)
        #expect(scaled.map(\.id) == lines.map(\.id))
    }

    @Test(arguments: [
        (0.37, UnitOfMeasure.cup, 0.25), (1.9, .cup, 2.0), (0.05, .teaspoon, 0.25), (1.1, .piece, 1.0),
        (49.0, .gram, 49.0), (52.0, .gram, 50.0), (333.0, .gram, 335.0), (333.0, .millilitre, 335.0), (0.0, .cup, 0.0),
    ] as [(Double, UnitOfMeasure, Double)])
    func roundingTable(value: Double, unit: UnitOfMeasure, expected: Double) {
        #expect(IngredientScaler.rounded(value, unit: unit) == expected)
    }
}
