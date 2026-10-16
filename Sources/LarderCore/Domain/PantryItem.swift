import Foundation

/// Something on the user's shelves.
public struct PantryItem: Identifiable, Hashable, Codable, Sendable {
    public var id: PantryItemID
    public var foodID: FoodID?
    public var rawName: String
    public var quantityGrams: Double
    public var location: StorageLocation
    public var bestBy: Date?
    public var source: PantrySource
    public var addedOn: Date

    /// Creates a pantry item.
    public init(
        id: PantryItemID = PantryItemID(),
        foodID: FoodID? = nil,
        rawName: String,
        quantityGrams: Double,
        location: StorageLocation,
        bestBy: Date? = nil,
        source: PantrySource,
        addedOn: Date
    ) {
        self.id = id
        self.foodID = foodID
        self.rawName = rawName
        self.quantityGrams = quantityGrams
        self.location = location
        self.bestBy = bestBy
        self.source = source
        self.addedOn = addedOn
    }
}

/// Where a pantry item is kept.
public enum StorageLocation: String, CaseIterable, Hashable, Codable, Sendable {
    case fridge
    case freezer
    case pantry
    case other
}

/// How a pantry item was added.
public enum PantrySource: String, CaseIterable, Hashable, Codable, Sendable {
    case manual
    case barcode
    case naturalLanguage
    case receipt
}
