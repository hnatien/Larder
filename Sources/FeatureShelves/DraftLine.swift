import Foundation
import LarderCore

/// One editable line awaiting confirmation before it joins the shelves.
public struct DraftLine: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var quantity: Double
    public var unit: UnitOfMeasure
    public var location: StorageLocation
    public var bestBy: Date?
    public var source: PantrySource

    /// Creates a line; the defaults describe one blank piece kept in the pantry.
    public init(
        id: UUID = UUID(),
        name: String = "",
        quantity: Double = 1,
        unit: UnitOfMeasure = .piece,
        location: StorageLocation = .pantry,
        bestBy: Date? = nil,
        source: PantrySource = .manual
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.location = location
        self.bestBy = bestBy
        self.source = source
    }

    /// Creates a line from the assistant's reading of free text or a receipt, keeping any best-by date it found.
    public init(parsed line: ParsedPantryLine, source: PantrySource = .naturalLanguage) {
        self.init(
            name: line.name,
            quantity: line.quantity ?? 1,
            unit: line.unit ?? .piece,
            location: line.location ?? .pantry,
            bestBy: line.bestBy,
            source: source
        )
    }

    /// Whether the line has a name and a positive, finite quantity.
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && quantity.isFinite && quantity > 0
    }
}

/// A common food offered as a one-tap chip in Add food, with a typical amount and where it is kept.
public struct Staple: Identifiable, Hashable, Sendable {
    public let name: String
    public let quantity: Double
    public let unit: UnitOfMeasure
    public let location: StorageLocation

    public var id: String { name }

    /// The pending line this staple adds.
    public var line: DraftLine {
        DraftLine(name: name, quantity: quantity, unit: unit, location: location, source: .manual)
    }
}

/// The last removed item, kept briefly so the removal can be reversed.
public struct UndoAction: Identifiable, Hashable, Sendable {
    /// How the item left the shelves.
    public enum Kind: Hashable, Sendable {
        case eaten, letGo
    }

    /// How long the undo stays on offer.
    public static let lifetime: Duration = .seconds(5)

    public let id = UUID()
    public let item: PantryItem
    public let kind: Kind

    /// Creates an undo for a removed item.
    public init(item: PantryItem, kind: Kind) {
        self.item = item
        self.kind = kind
    }
}
