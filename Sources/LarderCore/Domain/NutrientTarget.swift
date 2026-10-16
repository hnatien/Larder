import Foundation

/// A range for one nutrient, tagged with the guidance it came from.
public struct NutrientTarget: Hashable, Codable, Sendable {
    public var nutrient: Nutrient
    public var basis: TargetBasis
    public var min: Double?
    public var target: Double?
    public var max: Double?
    /// Higher values matter more when targets conflict.
    public var priority: Int
    public var source: TargetSource

    /// Creates a nutrient target.
    public init(
        nutrient: Nutrient,
        basis: TargetBasis,
        min: Double? = nil,
        target: Double? = nil,
        max: Double? = nil,
        priority: Int,
        source: TargetSource
    ) {
        self.nutrient = nutrient
        self.basis = basis
        self.min = min
        self.target = target
        self.max = max
        self.priority = priority
        self.source = source
    }
}

/// A nutrient tracked in `Nutrients`.
public enum Nutrient: String, CaseIterable, Hashable, Codable, Sendable {
    case energy
    case protein
    case fat
    case saturatedFat
    case monounsaturatedFat
    case polyunsaturatedFat
    case carbohydrate
    case fiber
    case totalSugar
    case addedSugar
    case sodium
    case potassium
    case calcium
    case iron
    case vitaminD
    case vitaminB12
}

/// What a target amount is measured against.
public enum TargetBasis: String, CaseIterable, Hashable, Codable, Sendable {
    case perDay
    case perMeal
    case per1000kcal
    case percentEnergy
}

/// The guidance a target is taken from.
public enum TargetSource: String, CaseIterable, Hashable, Codable, Sendable {
    case dga2025
    case who
    case custom
    case clinician
}
