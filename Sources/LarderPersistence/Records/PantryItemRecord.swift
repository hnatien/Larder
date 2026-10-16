import Foundation
import GRDB
import LarderCore

struct PantryItemRecord: LarderRecord {
    static let databaseTableName = "pantryItem"

    var id: UUID
    var foodID: UUID?
    var rawName: String
    var quantityGrams: Double
    var location: StorageLocation
    var bestBy: Date?
    var source: PantrySource
    var addedOn: Date

    init(_ item: PantryItem) {
        id = item.id.rawValue
        foodID = item.foodID?.rawValue
        rawName = item.rawName
        quantityGrams = item.quantityGrams
        location = item.location
        bestBy = item.bestBy
        source = item.source
        addedOn = item.addedOn
    }

    var item: PantryItem {
        PantryItem(
            id: PantryItemID(rawValue: id),
            foodID: foodID.map(FoodID.init(rawValue:)),
            rawName: rawName,
            quantityGrams: quantityGrams,
            location: location,
            bestBy: bestBy,
            source: source,
            addedOn: addedOn
        )
    }
}
