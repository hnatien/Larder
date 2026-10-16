import Testing
import LarderCore
@testable import LarderAssistant

struct DeterministicPantryParserTests {
    private let parser = DeterministicPantryParser()

    @Test func parsesTheReferenceSentence() {
        let lines = parser.parse("2 onions, half a bag of rice in the pantry, 500 g chicken thighs in the freezer")
        #expect(lines == [
            ParsedPantryLine(rawText: "2 onions", name: "onions", quantity: 2),
            ParsedPantryLine(rawText: "half a bag of rice in the pantry", name: "bag of rice", quantity: 0.5, location: .pantry),
            ParsedPantryLine(rawText: "500 g chicken thighs in the freezer", name: "chicken thighs", quantity: 500, unit: .gram, location: .freezer),
        ])
    }

    @Test func splitsOnSemicolonsAndNewlines() {
        let lines = parser.parse("milk in the fridge; 3 apples\n2 tbsp of honey")
        #expect(lines.map(\.name) == ["milk", "apples", "honey"])
        #expect(lines[0].location == .fridge)
        #expect(lines[2].unit == .tablespoon)
        #expect(lines[2].quantity == 2)
    }

    @Test(arguments: [
        ("1/2 cup milk", 0.5, UnitOfMeasure.cup, "milk"),
        ("1 1/2 kg flour", 1.5, .kilogram, "flour"),
        ("2.5 l water", 2.5, .litre, "water"),
        ("3/4 tsp salt", 0.75, .teaspoon, "salt"),
        ("2 fl oz vanilla", 2, .fluidOunce, "vanilla"),
        ("500g chicken", 500, .gram, "chicken"),
        ("250ml cream", 250, .millilitre, "cream"),
    ])
    func parsesNumbersFractionsAndUnits(text: String, quantity: Double, unit: UnitOfMeasure, name: String) {
        let line = parser.parse(text).first
        #expect(line?.quantity == quantity)
        #expect(line?.unit == unit)
        #expect(line?.name == name)
    }

    @Test(arguments: [("a dozen eggs", 12.0), ("dozen eggs", 12), ("2 dozen eggs", 24), ("half a dozen eggs", 6)])
    func dozensCountAsTwelve(text: String, quantity: Double) {
        #expect(parser.parse(text) == [ParsedPantryLine(rawText: text, name: "eggs", quantity: quantity)])
    }

    @Test func articlesCountAsOne() {
        #expect(parser.parse("a lemon, an apple in my fridge") == [
            ParsedPantryLine(rawText: "a lemon", name: "lemon", quantity: 1),
            ParsedPantryLine(rawText: "an apple in my fridge", name: "apple", quantity: 1, location: .fridge),
        ])
    }

    @Test func linesWithoutQuantitiesKeepTheirName() {
        #expect(parser.parse("Salt, frozen peas in freezer") == [
            ParsedPantryLine(rawText: "Salt", name: "Salt"),
            ParsedPantryLine(rawText: "frozen peas in freezer", name: "frozen peas", location: .freezer),
        ])
    }

    @Test(arguments: ["", "   ", ",;\n", " , 2 , 500 g "])
    func inputWithoutFoodNamesGivesNoLines(text: String) {
        #expect(parser.parse(text).isEmpty)
    }

    @Test func zeroAndNonsenseNumbersAreNotQuantities() {
        #expect(parser.parse("0 eggs").first?.quantity == nil)
        #expect(parser.parse("1/0 eggs").first?.quantity == nil)
    }
}
