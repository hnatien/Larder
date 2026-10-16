import Foundation

/// An amount in a unit, as written in a recipe or entered by a user.
public struct Quantity: Hashable, Codable, Sendable {
    public var value: Double
    public var unit: UnitOfMeasure

    /// Creates a quantity.
    public init(value: Double, unit: UnitOfMeasure) {
        self.value = value
        self.unit = unit
    }

    /// Localised text such as "200 g" or "2 tbsp"; count units use English unit names.
    public func formatted(locale: Locale) -> String {
        if let foundationUnit = unit.foundationUnit {
            let formatter = MeasurementFormatter()
            formatter.locale = locale
            formatter.unitOptions = .providedUnit
            // The medium style abbreviates cups to an ambiguous "c".
            formatter.unitStyle = unit == .cup ? .long : .medium
            formatter.numberFormatter.maximumFractionDigits = 2
            return formatter.string(from: Measurement(value: value, unit: foundationUnit))
        }
        let number = value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        return "\(number) \(value == 1 ? unit.countName.singular : unit.countName.plural)"
    }
}

extension UnitOfMeasure {
    fileprivate var foundationUnit: Dimension? {
        switch self {
        case .gram: UnitMass.grams
        case .kilogram: UnitMass.kilograms
        case .milligram: UnitMass.milligrams
        case .ounce: UnitMass.ounces
        case .pound: UnitMass.pounds
        case .millilitre: UnitVolume.milliliters
        case .litre: UnitVolume.liters
        case .teaspoon: UnitVolume.teaspoons
        case .tablespoon: UnitVolume.tablespoons
        case .cup: UnitVolume.cups
        case .fluidOunce: UnitVolume.fluidOunces
        case .piece, .pinch, .clove, .slice: nil
        }
    }

    fileprivate var countName: (singular: String, plural: String) {
        switch self {
        case .pinch: ("pinch", "pinches")
        case .clove: ("clove", "cloves")
        case .slice: ("slice", "slices")
        default: ("piece", "pieces")
        }
    }
}
