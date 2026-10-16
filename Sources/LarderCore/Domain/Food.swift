import Foundation

/// A food with nutrients per 100 g, household portions and allergen tags.
public struct Food: Identifiable, Hashable, Codable, Sendable {
    public var id: FoodID
    public var name: String
    public var source: FoodSource
    /// USDA FoodData Central identifier, when the food came from FDC.
    public var fdcID: Int?
    /// Barcode (GTIN), for branded foods.
    public var gtin: String?
    public var nutrientsPer100g: Nutrients
    public var portions: [Portion]
    public var foodGroup: FoodGroup
    public var allergens: AllergenTags
    /// Grams per millilitre, for converting volumes.
    public var densityGPerMl: Double?
    /// Diet, religious and medical facts about the food.
    public var tags: Set<FoodTag>

    /// Creates a food.
    public init(
        id: FoodID = FoodID(),
        name: String,
        source: FoodSource,
        fdcID: Int? = nil,
        gtin: String? = nil,
        nutrientsPer100g: Nutrients = Nutrients(),
        portions: [Portion] = [],
        foodGroup: FoodGroup,
        allergens: AllergenTags = AllergenTags(),
        densityGPerMl: Double? = nil,
        tags: Set<FoodTag> = []
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.fdcID = fdcID
        self.gtin = gtin
        self.nutrientsPer100g = nutrientsPer100g
        self.portions = portions
        self.foodGroup = foodGroup
        self.allergens = allergens
        self.densityGPerMl = densityGPerMl
        self.tags = tags
    }
}

/// Nutrient amounts per 100 g; `nil` means the source has no value, not zero.
public struct Nutrients: Hashable, Codable, Sendable {
    public var energyKcal: Double?
    public var proteinG: Double?
    public var fatG: Double?
    public var saturatedFatG: Double?
    public var monounsaturatedFatG: Double?
    public var polyunsaturatedFatG: Double?
    public var carbohydrateG: Double?
    public var fiberG: Double?
    public var totalSugarG: Double?
    public var addedSugarG: Double?
    public var sodiumMg: Double?
    public var potassiumMg: Double?
    public var calciumMg: Double?
    public var ironMg: Double?
    public var vitaminDMcg: Double?
    public var vitaminB12Mcg: Double?

    /// Creates a nutrient profile; omitted nutrients are unknown.
    public init(
        energyKcal: Double? = nil,
        proteinG: Double? = nil,
        fatG: Double? = nil,
        saturatedFatG: Double? = nil,
        monounsaturatedFatG: Double? = nil,
        polyunsaturatedFatG: Double? = nil,
        carbohydrateG: Double? = nil,
        fiberG: Double? = nil,
        totalSugarG: Double? = nil,
        addedSugarG: Double? = nil,
        sodiumMg: Double? = nil,
        potassiumMg: Double? = nil,
        calciumMg: Double? = nil,
        ironMg: Double? = nil,
        vitaminDMcg: Double? = nil,
        vitaminB12Mcg: Double? = nil
    ) {
        self.energyKcal = energyKcal
        self.proteinG = proteinG
        self.fatG = fatG
        self.saturatedFatG = saturatedFatG
        self.monounsaturatedFatG = monounsaturatedFatG
        self.polyunsaturatedFatG = polyunsaturatedFatG
        self.carbohydrateG = carbohydrateG
        self.fiberG = fiberG
        self.totalSugarG = totalSugarG
        self.addedSugarG = addedSugarG
        self.sodiumMg = sodiumMg
        self.potassiumMg = potassiumMg
        self.calciumMg = calciumMg
        self.ironMg = ironMg
        self.vitaminDMcg = vitaminDMcg
        self.vitaminB12Mcg = vitaminB12Mcg
    }
}

/// A household measure of a food, such as "1 medium" = 118 g.
public struct Portion: Hashable, Codable, Sendable {
    public var label: String
    public var grams: Double

    /// Creates a portion.
    public init(label: String, grams: Double) {
        self.label = label
        self.grams = grams
    }
}

/// The food group used for shelf balance.
public enum FoodGroup: String, CaseIterable, Hashable, Codable, Sendable {
    case produce
    case grains
    case protein
    case dairy
    case fats
    case legumes
    case other
}

/// Where a food's data came from, which sets how far it can be trusted.
public enum FoodSource: String, CaseIterable, Hashable, Codable, Sendable {
    case fdcFoundation
    case srLegacy
    case fdcBranded
    /// Open Food Facts community data; show as unverified.
    case offUnverified
    case seedApproximate
}
