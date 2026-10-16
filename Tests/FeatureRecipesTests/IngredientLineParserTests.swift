import LarderCore
import Testing
@testable import FeatureRecipes

struct IngredientLineParserTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let line: String
        let quantity: Double?
        let unit: UnitOfMeasure?
        let name: String
        var isOptional = false

        var testDescription: String { line }
    }

    static let cases: [Case] = [
        Case(line: "2 cups flour", quantity: 2, unit: .cup, name: "flour"),
        Case(line: "1 1/2 cups sugar", quantity: 1.5, unit: .cup, name: "sugar"),
        Case(line: "\u{BD} tsp salt", quantity: 0.5, unit: .teaspoon, name: "salt"),
        Case(line: "1\u{BD} tablespoons olive oil", quantity: 1.5, unit: .tablespoon, name: "olive oil"),
        Case(line: "\u{BE} cup milk", quantity: 0.75, unit: .cup, name: "milk"),
        Case(line: "1 \u{BC} cups water", quantity: 1.25, unit: .cup, name: "water"),
        Case(line: "a pinch of salt", quantity: 1, unit: .pinch, name: "salt"),
        Case(line: "2 cloves garlic, minced", quantity: 2, unit: .clove, name: "garlic, minced"),
        Case(line: "salt to taste", quantity: nil, unit: nil, name: "salt"),
        Case(line: "Salt, to taste", quantity: nil, unit: nil, name: "Salt"),
        Case(line: "1 (400 g) can chickpeas, drained", quantity: 400, unit: .gram, name: "chickpeas, drained"),
        Case(line: "2 (14 oz) cans diced tomatoes", quantity: 28, unit: .ounce, name: "diced tomatoes"),
        Case(line: "400g spaghetti", quantity: 400, unit: .gram, name: "spaghetti"),
        Case(line: "250 ml milk", quantity: 250, unit: .millilitre, name: "milk"),
        Case(line: "1.5 kg potatoes", quantity: 1.5, unit: .kilogram, name: "potatoes"),
        Case(line: "3 eggs", quantity: 3, unit: nil, name: "eggs"),
        Case(line: "2-3 tbsp lemon juice", quantity: 3, unit: .tablespoon, name: "lemon juice"),
        Case(line: "1-1/2 cups flour", quantity: 1.5, unit: .cup, name: "flour"),
        Case(line: "\u{BE} cup (180 ml) water", quantity: 0.75, unit: .cup, name: "water"),
        Case(line: "1 lb ground beef", quantity: 1, unit: .pound, name: "ground beef"),
        Case(line: "2 tbsp. butter (optional)", quantity: 2, unit: .tablespoon, name: "butter", isOptional: true),
        Case(line: "Optional: 1 tsp chilli flakes", quantity: 1, unit: .teaspoon, name: "chilli flakes", isOptional: true),
        Case(line: "\u{2022} 1 cup water", quantity: 1, unit: .cup, name: "water"),
        Case(line: "an onion", quantity: 1, unit: nil, name: "onion"),
        Case(line: "2 slices bread", quantity: 2, unit: .slice, name: "bread"),
        Case(line: "1 fl oz vodka", quantity: 1, unit: .fluidOunce, name: "vodka"),
        Case(line: "2 cans tomatoes", quantity: 2, unit: nil, name: "tomatoes"),
        Case(line: "juice of 1 lemon", quantity: nil, unit: nil, name: "juice of 1 lemon"),
        Case(line: "a little olive oil", quantity: nil, unit: nil, name: "a little olive oil"),
        Case(line: "1 tablespoon sugar, or to taste", quantity: 1, unit: .tablespoon, name: "sugar"),
        Case(line: "1 large onion", quantity: 1, unit: nil, name: "large onion"),
    ]

    @Test(arguments: cases)
    func parsesLine(_ expected: Case) {
        let parsed = IngredientLineParser.parse(expected.line)
        #expect(parsed.quantity == expected.quantity)
        #expect(parsed.unit == expected.unit)
        #expect(parsed.name == expected.name)
        #expect(parsed.isOptional == expected.isOptional)
    }

    @Test func emptyLineYieldsEmptyName() {
        let parsed = IngredientLineParser.parse("   ")
        #expect(parsed.quantity == nil)
        #expect(parsed.name.isEmpty)
    }

    @Test func amountWithoutNameKeepsTheLine() {
        #expect(IngredientLineParser.parse("2").name == "2")
    }

    @Test func quantityTextScansMixedAndRanges() throws {
        let mixed = try #require(QuantityText.scan("1 1/2 cups"))
        #expect(mixed.lower == 1.5)
        #expect(mixed.upper == nil)
        let range = try #require(QuantityText.scan("8 to 10 minutes"))
        #expect(range.lower == 8)
        #expect(range.upper == 10)
        #expect(QuantityText.scan("salt") == nil)
    }

    @Test func formatsQuarterFractions() {
        #expect(QuantityText.format(1.5) == "1 \u{BD}")
        #expect(QuantityText.format(0.25) == "\u{BC}")
        #expect(QuantityText.format(0.75) == "\u{BE}")
        #expect(QuantityText.format(3) == "3")
        #expect(QuantityText.format(2.1) == 2.1.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)))
        #expect(QuantityText.format(1000) == "1000")
    }
}
