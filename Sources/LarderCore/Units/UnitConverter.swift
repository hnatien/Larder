import Foundation

/// Why a quantity could not be converted to grams.
public enum UnitConversionError: Error, Hashable, Sendable {
    /// A count unit was given without a portion weight.
    case needsPortion
    /// A volume unit was given without a density.
    case needsDensity
    /// The quantity was negative, infinite or NaN.
    case invalidQuantity
    /// The density was zero, negative, infinite or NaN.
    case invalidDensity
    /// The portion weight was zero, negative, infinite or NaN.
    case invalidPortion
}

/// Converts quantities to grams, the canonical unit.
public enum UnitConverter {
    /// Grams in `quantity` of `unit`; volumes need `gPerMl`, count units need `portion` (grams per item).
    public static func grams(
        from quantity: Double,
        unit: UnitOfMeasure,
        density gPerMl: Double? = nil,
        portion: Portion? = nil
    ) throws(UnitConversionError) -> Double {
        guard quantity.isFinite, quantity >= 0 else { throw .invalidQuantity }
        if let gramsPerUnit = unit.gramsPerUnit {
            return quantity * gramsPerUnit
        }
        if let millilitresPerUnit = unit.millilitresPerUnit {
            guard let gPerMl else { throw .needsDensity }
            guard gPerMl.isFinite, gPerMl > 0 else { throw .invalidDensity }
            return quantity * millilitresPerUnit * gPerMl
        }
        guard let portion else { throw .needsPortion }
        guard portion.grams.isFinite, portion.grams > 0 else { throw .invalidPortion }
        return quantity * portion.grams
    }
}
