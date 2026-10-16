import Foundation
import Testing
@testable import LarderCore

struct QuantityTests {
    private let unitedStates = Locale(identifier: "en_US")
    private let germany = Locale(identifier: "de_DE")

    @Test func formatsMassWithAbbreviation() {
        #expect(Quantity(value: 200, unit: .gram).formatted(locale: unitedStates) == "200 g")
        #expect(Quantity(value: 1, unit: .pound).formatted(locale: unitedStates) == "1 lb")
    }

    @Test func formatsSpoonsAndFluidOunces() {
        #expect(Quantity(value: 2, unit: .tablespoon).formatted(locale: unitedStates) == "2 tbsp")
        #expect(Quantity(value: 8, unit: .fluidOunce).formatted(locale: unitedStates) == "8 fl oz")
    }

    @Test func cupsUseFullName() {
        #expect(Quantity(value: 1.5, unit: .cup).formatted(locale: unitedStates) == "1.5 cups")
    }

    @Test func usesLocaleDecimalSeparator() {
        #expect(Quantity(value: 1.5, unit: .kilogram).formatted(locale: germany) == "1,5 kg")
    }

    @Test func roundsToTwoFractionDigits() {
        #expect(Quantity(value: 1.0 / 3.0, unit: .teaspoon).formatted(locale: unitedStates) == "0.33 tsp")
    }

    @Test func countUnitsPluralise() {
        #expect(Quantity(value: 1, unit: .pinch).formatted(locale: unitedStates) == "1 pinch")
        #expect(Quantity(value: 2, unit: .clove).formatted(locale: unitedStates) == "2 cloves")
        #expect(Quantity(value: 3, unit: .piece).formatted(locale: unitedStates) == "3 pieces")
        #expect(Quantity(value: 0, unit: .slice).formatted(locale: unitedStates) == "0 slices")
    }

    @Test func countUnitsUseLocaleNumberFormat() {
        #expect(Quantity(value: 1.5, unit: .slice).formatted(locale: germany) == "1,5 slices")
    }

    @Test func roundTripsThroughJSON() throws {
        let quantity = Quantity(value: 0.25, unit: .cup)
        let decoded = try JSONDecoder().decode(Quantity.self, from: JSONEncoder().encode(quantity))
        #expect(decoded == quantity)
    }
}
