import Foundation
import GRDB
import LarderCore

struct PantryEventRecord: LarderRecord {
    static let databaseTableName = "pantryEvent"

    var id: UUID
    var kind: PantryEventKind
    var foodID: UUID?
    var name: String
    var grams: Double
    var date: Date
    var plannedMealID: UUID?

    init(_ event: PantryEvent) {
        id = event.id.rawValue
        kind = event.kind
        foodID = event.foodID?.rawValue
        name = event.name
        grams = event.grams
        date = event.date
        plannedMealID = event.plannedMealID?.rawValue
    }

    var event: PantryEvent {
        PantryEvent(
            id: PantryEventID(rawValue: id),
            kind: kind,
            foodID: foodID.map(FoodID.init(rawValue:)),
            name: name,
            grams: grams,
            date: date,
            plannedMealID: plannedMealID.map(PlannedMealID.init(rawValue:))
        )
    }
}
