import Foundation
import Testing
import LarderCore
@testable import LarderOnDeviceAI

struct PantryLineMapperTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
    /// Monday 19 October 2026, 17:00 GMT.
    private static let now = Date(timeIntervalSince1970: 1_792_429_200)

    @Test func mapsEveryField() throws {
        let line = PantryLine(name: "  basmati rice ", quantity: 500, unit: "grams", location: "pantry", bestByHint: "use by Friday")
        let friday = try #require(Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 23)))
        #expect(PantryLineMapper.map(line, now: Self.now, calendar: Self.calendar, locale: Locale(identifier: "en_GB")) == ParsedPantryLine(
            rawText: "basmati rice",
            name: "basmati rice",
            quantity: 500,
            unit: .gram,
            location: .pantry,
            bestBy: friday
        ))
    }

    @Test func bestByWordingWithNoDayStaysNil() {
        let line = PantryLine(name: "milk", quantity: nil, unit: nil, location: nil, bestByHint: "check the lid")
        #expect(PantryLineMapper.map(line, now: Self.now, calendar: Self.calendar).bestBy == nil)
    }

    @Test func missingOptionalFieldsStayNil() {
        let line = PantryLine(name: "onions", quantity: nil, unit: nil, location: nil, bestByHint: nil)
        #expect(PantryLineMapper.map(line, now: Self.now) == ParsedPantryLine(rawText: "onions", name: "onions"))
    }

    @Test(arguments: [
        ("g", UnitOfMeasure.gram), ("Grams", .gram), ("kg", .kilogram), ("Tbsp.", .tablespoon), ("tsp", .teaspoon),
        ("fl oz", .fluidOunce), ("cups", .cup), ("ml", .millilitre), ("L", .litre), ("lbs", .pound), ("cloves", .clove),
    ])
    func unitSpellingsMapThroughUnitParser(unit: String, expected: UnitOfMeasure) {
        let line = PantryLine(name: "x", quantity: 1, unit: unit, location: nil, bestByHint: nil)
        #expect(PantryLineMapper.map(line, now: Self.now).unit == expected)
    }

    @Test(arguments: ["bag", "tin", "handful", "", "  "])
    func containerWordsAndBlankUnitsMapToNoUnit(unit: String) {
        let line = PantryLine(name: "rice", quantity: 1, unit: unit, location: nil, bestByHint: nil)
        #expect(PantryLineMapper.map(line, now: Self.now).unit == nil)
        #expect(PantryLineMapper.map(line, now: Self.now).quantity == 1)
    }

    @Test(arguments: [0, -2, Double.nan, Double.infinity])
    func quantitiesThatAreNotPositiveAndFiniteAreDropped(quantity: Double) {
        let line = PantryLine(name: "eggs", quantity: quantity, unit: nil, location: nil, bestByHint: nil)
        #expect(PantryLineMapper.map(line, now: Self.now).quantity == nil)
    }
}

struct StorageLocationMapperTests {
    @Test(arguments: [
        ("fridge", StorageLocation.fridge), ("Refrigerator", .fridge), ("refrigerated", .fridge), (" Fridge. ", .fridge),
        ("FREEZER", .freezer), ("frozen", .freezer),
        ("pantry", .pantry), ("cupboard", .pantry), ("larder", .pantry), ("shelf", .pantry),
        ("other", .other),
    ])
    func storageWordsMap(text: String, expected: StorageLocation) {
        #expect(StorageLocationMapper.location(from: text) == expected)
    }

    @Test(arguments: [nil, "", "garage", "in the fridge door"] as [String?])
    func unknownWordsMapToNil(text: String?) {
        #expect(StorageLocationMapper.location(from: text) == nil)
    }

    @Test func everyValueTheSchemaAllowsMapsAndCoversEveryLocation() {
        let mapped = PantryLocationHint.allowedValues.map(StorageLocationMapper.location(from:))
        #expect(!mapped.contains(nil))
        #expect(Set(mapped.compactMap(\.self)) == Set(StorageLocation.allCases))
    }
}

struct RecipeDraftMapperTests {
    @Test func mapsEveryField() {
        let draft = RecipeDraft(
            title: " Red lentil dal ",
            servings: 4,
            prepMinutes: 10,
            cookMinutes: 25,
            ingredients: [
                IngredientLine(rawText: "200 g red lentils", name: "red lentils", quantity: 200, unit: "g"),
                IngredientLine(rawText: "1 tbsp oil", name: "oil", quantity: 1, unit: "tbsp"),
                IngredientLine(rawText: "salt", name: "salt", quantity: nil, unit: nil),
            ],
            steps: [
                StepLine(text: "Rinse the lentils.", timerSeconds: nil),
                StepLine(text: "Simmer for 20 minutes.", timerSeconds: 1200),
            ]
        )
        #expect(RecipeDraftMapper.map(draft) == ParsedRecipe(
            title: "Red lentil dal",
            servings: 4,
            prepMinutes: 10,
            cookMinutes: 25,
            ingredients: [
                ParsedIngredient(rawText: "200 g red lentils", name: "red lentils", quantity: 200, unit: .gram),
                ParsedIngredient(rawText: "1 tbsp oil", name: "oil", quantity: 1, unit: .tablespoon),
                ParsedIngredient(rawText: "salt", name: "salt"),
            ],
            steps: [
                RecipeStep(text: "Rinse the lentils."),
                RecipeStep(text: "Simmer for 20 minutes.", timerSeconds: 1200),
            ]
        ))
    }

    @Test func countsAndTimesThatAreNotPositiveAreDropped() {
        let draft = RecipeDraft(
            title: "Toast",
            servings: 0,
            prepMinutes: -5,
            cookMinutes: 0,
            ingredients: [IngredientLine(rawText: "bread", name: "bread", quantity: -1, unit: "slices")],
            steps: [StepLine(text: "Toast it.", timerSeconds: 0)]
        )
        let recipe = RecipeDraftMapper.map(draft)
        #expect(recipe.servings == nil)
        #expect(recipe.prepMinutes == nil)
        #expect(recipe.cookMinutes == nil)
        #expect(recipe.ingredients == [ParsedIngredient(rawText: "bread", name: "bread", unit: .slice)])
        #expect(recipe.steps == [RecipeStep(text: "Toast it.")])
    }

    @Test func blankIngredientsAndStepsAreDroppedAndBlankRawTextFallsBackToName() {
        let draft = RecipeDraft(
            title: "Soup",
            servings: nil,
            prepMinutes: nil,
            cookMinutes: nil,
            ingredients: [
                IngredientLine(rawText: "  ", name: "leek", quantity: 2, unit: nil),
                IngredientLine(rawText: "garnish", name: " ", quantity: nil, unit: nil),
            ],
            steps: [StepLine(text: "  ", timerSeconds: 60), StepLine(text: "Blend.", timerSeconds: nil)]
        )
        let recipe = RecipeDraftMapper.map(draft)
        #expect(recipe.ingredients == [ParsedIngredient(rawText: "leek", name: "leek", quantity: 2)])
        #expect(recipe.steps == [RecipeStep(text: "Blend.")])
    }
}
