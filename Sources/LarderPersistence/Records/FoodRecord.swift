import Foundation
import GRDB
import LarderCore

struct FoodRecord: LarderRecord {
    static let databaseTableName = "food"

    var id: UUID
    var name: String
    var source: FoodSource
    var fdcID: Int?
    var gtin: String?
    var foodGroup: FoodGroup
    var densityGPerMl: Double?
    var nutrients: Nutrients
    var portions: [Portion]
    var allergens: [Allergen: AllergenPresence]
    var tags: [String]

    init(_ food: Food) throws {
        let fields = try FoodFields(food)
        id = fields.id
        name = fields.name
        source = fields.source
        fdcID = fields.fdcID
        gtin = fields.gtin
        foodGroup = fields.foodGroup
        densityGPerMl = fields.densityGPerMl
        nutrients = fields.nutrientsPer100g
        portions = fields.portions
        allergens = fields.allergens.entries
        tags = fields.tags
    }

    func food() throws -> Food {
        try FoodFields(
            id: id,
            name: name,
            source: source,
            fdcID: fdcID,
            gtin: gtin,
            nutrientsPer100g: nutrients,
            portions: portions,
            foodGroup: foodGroup,
            allergens: AllergenTags(allergens),
            densityGPerMl: densityGPerMl,
            tags: tags
        ).food()
    }
}

/// `Food` in its Codable form, including `densityGPerMl` and `tags`, which `Food` gains in a later change.
///
/// Converting through Codable keeps this module compiling whether or not `Food` has those properties yet:
/// keys `Food` does not know are ignored on decode and absent keys decode as empty.
struct FoodFields: Codable {
    var id: UUID
    var name: String
    var source: FoodSource
    var fdcID: Int?
    var gtin: String?
    var nutrientsPer100g: Nutrients
    var portions: [Portion]
    var foodGroup: FoodGroup
    var allergens: AllergenTags
    var densityGPerMl: Double?
    var tags: [String]

    init(
        id: UUID,
        name: String,
        source: FoodSource,
        fdcID: Int?,
        gtin: String?,
        nutrientsPer100g: Nutrients,
        portions: [Portion],
        foodGroup: FoodGroup,
        allergens: AllergenTags,
        densityGPerMl: Double?,
        tags: [String]
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
        self.tags = tags.sorted()
    }

    init(_ food: Food) throws {
        self = try RecordCoding.decoder.decode(FoodFields.self, from: RecordCoding.encoder.encode(food))
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            source: try container.decode(FoodSource.self, forKey: .source),
            fdcID: try container.decodeIfPresent(Int.self, forKey: .fdcID),
            gtin: try container.decodeIfPresent(String.self, forKey: .gtin),
            nutrientsPer100g: try container.decode(Nutrients.self, forKey: .nutrientsPer100g),
            portions: try container.decode([Portion].self, forKey: .portions),
            foodGroup: try container.decode(FoodGroup.self, forKey: .foodGroup),
            allergens: try container.decode(AllergenTags.self, forKey: .allergens),
            densityGPerMl: try container.decodeIfPresent(Double.self, forKey: .densityGPerMl),
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        )
    }

    func food() throws -> Food {
        try RecordCoding.decoder.decode(Food.self, from: RecordCoding.encoder.encode(self))
    }
}
