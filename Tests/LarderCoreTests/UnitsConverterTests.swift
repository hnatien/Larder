import Foundation
import Testing
@testable import LarderCore

struct UnitConverterTests {
    @Test(arguments: [
        (UnitOfMeasure.gram, 1.0),
        (.kilogram, 1000),
        (.milligram, 0.001),
        (.ounce, 28.3495),
        (.pound, 453.592),
    ])
    func massUnitsConvertByFixedFactor(unit: UnitOfMeasure, gramsPerUnit: Double) throws {
        #expect(try UnitConverter.grams(from: 2, unit: unit) == 2 * gramsPerUnit)
    }

    @Test(arguments: [
        (UnitOfMeasure.millilitre, 1.0),
        (.litre, 1000),
        (.teaspoon, 4.93),
        (.tablespoon, 14.79),
        (.cup, 236.59),
        (.fluidOunce, 29.57),
    ])
    func volumeUnitsUseUSCustomaryMillilitresTimesDensity(unit: UnitOfMeasure, millilitresPerUnit: Double) throws {
        let grams = try UnitConverter.grams(from: 2, unit: unit, density: 0.5)
        #expect(abs(grams - millilitresPerUnit) < 1e-9)
    }

    @Test(arguments: UnitOfMeasure.allCases.filter(\.isVolume))
    func volumeWithoutDensityThrowsNeedsDensity(unit: UnitOfMeasure) {
        #expect(throws: UnitConversionError.needsDensity) {
            try UnitConverter.grams(from: 1, unit: unit)
        }
    }

    @Test(arguments: [UnitOfMeasure.piece, .pinch, .clove, .slice])
    func countUnitsUsePortionGrams(unit: UnitOfMeasure) throws {
        let grams = try UnitConverter.grams(from: 3, unit: unit, portion: Portion(label: "1 \(unit)", grams: 5))
        #expect(grams == 15)
    }

    @Test(arguments: UnitOfMeasure.allCases.filter(\.isCount))
    func countWithoutPortionThrowsNeedsPortion(unit: UnitOfMeasure) {
        #expect(throws: UnitConversionError.needsPortion) {
            try UnitConverter.grams(from: 1, unit: unit, density: 1)
        }
    }

    @Test(arguments: [UnitOfMeasure.gram, .cup, .clove])
    func negativeQuantityThrows(unit: UnitOfMeasure) {
        #expect(throws: UnitConversionError.invalidQuantity) {
            try UnitConverter.grams(from: -1, unit: unit, density: 1, portion: Portion(label: "1", grams: 1))
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteQuantityThrows(quantity: Double) {
        #expect(throws: UnitConversionError.invalidQuantity) {
            try UnitConverter.grams(from: quantity, unit: .gram)
        }
    }

    @Test func zeroQuantityIsZeroGrams() throws {
        #expect(try UnitConverter.grams(from: 0, unit: .cup, density: 1.03) == 0)
    }

    @Test(arguments: [0, -1, Double.nan, .infinity])
    func invalidDensityThrows(density: Double) {
        #expect(throws: UnitConversionError.invalidDensity) {
            try UnitConverter.grams(from: 1, unit: .tablespoon, density: density)
        }
    }

    @Test(arguments: [0, -5, Double.nan, .infinity])
    func invalidPortionThrows(grams: Double) {
        #expect(throws: UnitConversionError.invalidPortion) {
            try UnitConverter.grams(from: 1, unit: .piece, portion: Portion(label: "1 medium", grams: grams))
        }
    }

    @Test func massIgnoresDensityAndPortion() throws {
        let grams = try UnitConverter.grams(from: 1, unit: .pound, density: 2, portion: Portion(label: "1", grams: 9))
        #expect(grams == 453.592)
    }

    @Test(arguments: UnitOfMeasure.allCases)
    func everyUnitHasExactlyOneKind(unit: UnitOfMeasure) {
        #expect([unit.isMass, unit.isVolume, unit.isCount].filter { $0 }.count == 1)
    }

    @Test func unitKindsPartitionAllCases() {
        #expect(Set(UnitOfMeasure.allCases.filter(\.isMass)) == [.gram, .kilogram, .milligram, .ounce, .pound])
        #expect(
            Set(UnitOfMeasure.allCases.filter(\.isVolume))
                == [.millilitre, .litre, .teaspoon, .tablespoon, .cup, .fluidOunce]
        )
        #expect(Set(UnitOfMeasure.allCases.filter(\.isCount)) == [.piece, .pinch, .clove, .slice])
    }
}
