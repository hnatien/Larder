import Foundation

/// A record of food leaving the shelves, kept so waste can be measured later.
public struct PantryEvent: Identifiable, Hashable, Codable, Sendable {
    public var id: PantryEventID
    public var kind: PantryEventKind
    public var foodID: FoodID?
    /// The item's or food's name when it left.
    public var name: String
    /// Grams that left the shelves.
    public var grams: Double
    public var date: Date
    /// The planned meal that was cooked, for `.cooked` events from the plan.
    public var plannedMealID: PlannedMealID?

    /// Creates an event.
    public init(
        id: PantryEventID = PantryEventID(),
        kind: PantryEventKind,
        foodID: FoodID?,
        name: String,
        grams: Double,
        date: Date,
        plannedMealID: PlannedMealID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.foodID = foodID
        self.name = name
        self.grams = grams
        self.date = date
        self.plannedMealID = plannedMealID
    }
}

/// Why food left the shelves.
public enum PantryEventKind: String, CaseIterable, Hashable, Codable, Sendable {
    /// Taken by cooking a meal.
    case cooked
    /// Eaten as it was, from the shelves.
    case eaten
    /// Thrown out or given away before its best-by date.
    case letGo
    /// Thrown out once past its best-by date.
    case expired
}
