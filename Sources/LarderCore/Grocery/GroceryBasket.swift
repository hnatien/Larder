import Foundation

/// Identifies a `ManualItem`.
public typealias ManualItemID = Identifier<ManualItem>

/// An item the user typed onto the grocery list by hand.
public struct ManualItem: Identifiable, Hashable, Sendable {
    public var id: ManualItemID
    public var name: String
    /// Free text such as "2 tins"; may be empty.
    public var quantity: String
    public var aisle: Aisle

    /// Creates a manual item.
    public init(id: ManualItemID = ManualItemID(), name: String, quantity: String = "", aisle: Aisle = .other) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.aisle = aisle
    }
}

/// Identifies a grocery line across reloads: by food, else by normalised name; lines that could not be weighed also by unit.
public struct GroceryItemKey: Hashable, Sendable {
    /// What the line is for.
    public enum Identity: Hashable, Sendable {
        case food(FoodID)
        case name(String)
        case manual(ManualItemID)
    }

    public let identity: Identity
    /// The unit of a line that could not be weighed; `nil` otherwise.
    public let unit: UnitOfMeasure?

    /// The key of a list item.
    public init(_ item: GroceryItem) {
        let identity: Identity = item.foodID.map(Identity.food) ?? .name(Self.normalised(item.name))
        self.init(identity: identity, unit: item.neededGrams == nil ? item.displayQuantity.unit : nil)
    }

    /// The key of a hand-written item.
    public init(_ item: ManualItem) {
        self.init(identity: .manual(item.id), unit: nil)
    }

    /// A key from its parts, as stored.
    public init(identity: Identity, unit: UnitOfMeasure?) {
        self.identity = identity
        self.unit = unit
    }

    static func normalised(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// A ticked grocery line and what the tick put on the shelves.
public struct BasketLine: Hashable, Sendable {
    public var key: GroceryItemKey
    /// The planned item as it was when ticked, so the basket keeps it when the plan stops needing it; `nil` for a
    /// hand-written item, which its `ManualItem` describes.
    public var item: GroceryItem?
    /// The shelf item the tick added, which unticking takes off again.
    public var pantryItemID: PantryItemID?
    public var checkedOn: Date

    /// Creates a basket line.
    public init(key: GroceryItemKey, item: GroceryItem?, pantryItemID: PantryItemID?, checkedOn: Date) {
        self.key = key
        self.item = item
        self.pantryItemID = pantryItemID
        self.checkedOn = checkedOn
    }
}
