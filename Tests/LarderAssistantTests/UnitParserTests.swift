import Testing
import LarderCore
@testable import LarderAssistant

struct UnitParserTests {
    @Test(arguments: [
        ("g", UnitOfMeasure.gram), ("grams", .gram), ("Gram", .gram), ("kg", .kilogram), ("kilos", .kilogram),
        ("mg", .milligram), ("ml", .millilitre), ("milliliters", .millilitre), ("l", .litre), ("Litres", .litre),
        ("tsp", .teaspoon), ("teaspoons", .teaspoon), ("tbsp", .tablespoon), ("Tbsp.", .tablespoon),
        ("tablespoons", .tablespoon), ("cup", .cup), ("cups", .cup), ("fl oz", .fluidOunce), ("fl  oz", .fluidOunce),
        ("fluid ounces", .fluidOunce), ("oz", .ounce), ("ounces", .ounce), ("lb", .pound), ("lbs", .pound),
        ("pounds", .pound), ("pcs", .piece), ("pinch", .pinch), ("cloves", .clove), ("slices", .slice), (" g ", .gram),
    ])
    func knownSpellingsMapToUnits(text: String, unit: UnitOfMeasure) {
        #expect(UnitParser.unit(from: text) == unit)
    }

    @Test(arguments: [nil, "", "   ", "bag", "bucket", "handful", "t", "c"] as [String?])
    func unknownOrAmbiguousTextIsNil(text: String?) {
        #expect(UnitParser.unit(from: text) == nil)
    }

    @Test func everyUnitHasAtLeastOneSpelling() {
        let spelled = Set(["g", "kg", "mg", "ml", "l", "tsp", "tbsp", "cup", "fl oz", "oz", "lb", "piece", "pinch", "clove", "slice"].compactMap(UnitParser.unit(from:)))
        #expect(spelled == Set(UnitOfMeasure.allCases))
    }
}
