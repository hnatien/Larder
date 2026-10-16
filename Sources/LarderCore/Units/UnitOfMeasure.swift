import Foundation

/// A unit an ingredient or pantry quantity can be written in. Volumes are US customary.
public enum UnitOfMeasure: String, CaseIterable, Hashable, Codable, Sendable {
    case gram
    case kilogram
    case milligram
    case millilitre
    case litre
    case teaspoon
    case tablespoon
    case cup
    case fluidOunce
    case ounce
    case pound
    case piece
    case pinch
    case clove
    case slice

    /// Whether the unit measures mass.
    public var isMass: Bool { gramsPerUnit != nil }

    /// Whether the unit measures volume.
    public var isVolume: Bool { millilitresPerUnit != nil }

    /// Whether the unit counts items and needs a `Portion` to become grams.
    public var isCount: Bool { !isMass && !isVolume }

    var gramsPerUnit: Double? {
        switch self {
        case .gram: 1
        case .kilogram: 1000
        case .milligram: 0.001
        case .ounce: 28.3495
        case .pound: 453.592
        default: nil
        }
    }

    var millilitresPerUnit: Double? {
        switch self {
        case .millilitre: 1
        case .litre: 1000
        case .teaspoon: 4.93
        case .tablespoon: 14.79
        case .cup: 236.59
        case .fluidOunce: 29.57
        default: nil
        }
    }
}
