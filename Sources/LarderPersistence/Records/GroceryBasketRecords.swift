import Foundation
import GRDB
import LarderCore

struct GroceryManualItemRecord: LarderRecord {
    static let databaseTableName = "groceryManualItem"

    var id: UUID
    var position: Int
    var name: String
    var quantity: String
    var aisle: Aisle

    init(_ item: ManualItem, position: Int) {
        id = item.id.rawValue
        self.position = position
        name = item.name
        quantity = item.quantity
        aisle = item.aisle
    }

    var item: ManualItem {
        ManualItem(id: ManualItemID(rawValue: id), name: name, quantity: quantity, aisle: aisle)
    }
}

struct GroceryBasketLineRecord: LarderRecord {
    static let databaseTableName = "groceryBasketLine"

    var identityKind: String
    var identity: String
    /// The unit of a line that could not be weighed; empty for a weighed line.
    var unit: String
    var item: GroceryItem?
    var pantryItemID: UUID?
    var checkedOn: Date

    init(_ line: BasketLine) {
        (identityKind, identity, unit) = Self.columns(of: line.key)
        item = line.item
        pantryItemID = line.pantryItemID?.rawValue
        checkedOn = line.checkedOn
    }

    /// The primary key columns of `key`, in table order.
    static func columns(of key: GroceryItemKey) -> (identityKind: String, identity: String, unit: String) {
        let unit = key.unit?.rawValue ?? ""
        switch key.identity {
        case .food(let id): return ("food", id.key, unit)
        case .name(let name): return ("name", name, unit)
        case .manual(let id): return ("manual", id.key, unit)
        }
    }

    func line() throws -> BasketLine {
        BasketLine(key: try key(), item: item, pantryItemID: pantryItemID.map(PantryItemID.init(rawValue:)), checkedOn: checkedOn)
    }

    private func key() throws -> GroceryItemKey {
        let storedUnit: UnitOfMeasure?
        if unit.isEmpty {
            storedUnit = nil
        } else if let parsed = UnitOfMeasure(rawValue: unit) {
            storedUnit = parsed
        } else {
            throw InvalidStoredValue(column: "unit", value: unit)
        }
        switch identityKind {
        case "food":
            guard let uuid = UUID(uuidString: identity) else { throw InvalidStoredValue(column: "identity", value: identity) }
            return GroceryItemKey(identity: .food(FoodID(rawValue: uuid)), unit: storedUnit)
        case "name":
            return GroceryItemKey(identity: .name(identity), unit: storedUnit)
        case "manual":
            guard let uuid = UUID(uuidString: identity) else { throw InvalidStoredValue(column: "identity", value: identity) }
            return GroceryItemKey(identity: .manual(ManualItemID(rawValue: uuid)), unit: storedUnit)
        default:
            throw InvalidStoredValue(column: "identityKind", value: identityKind)
        }
    }
}
