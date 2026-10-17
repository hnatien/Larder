import Foundation
import GRDB
import LarderCore

/// `PantryRepository` backed by the Larder SQLite store; throws `PersistenceError`.
public struct GRDBPantryRepository: PantryRepository {
    /// Below this many grams an item counts as used up, so floating-point residue does not leave ghost items.
    static let usedUpGrams = 0.000_001

    private let database: LarderDatabase

    /// Creates a repository over `database`.
    public init(database: LarderDatabase) {
        self.database = database
    }

    /// Every pantry item, earliest best-by first, items without a best-by date last.
    public func items() async throws -> [PantryItem] {
        try await database.read { db in
            try Self.byBestBy(PantryItemRecord.all()).fetchAll(db).map(\.item)
        }
    }

    public func upsert(_ item: PantryItem) async throws {
        try await database.write { db in
            try PantryItemRecord(item).upsert(db)
        }
    }

    public func remove(_ id: PantryItemID) async throws {
        try await database.write { db in
            _ = try PantryItemRecord.deleteOne(db, key: id.key)
        }
    }

    /// Deducts `grams` across items of the food, earliest best-by first, removing items that reach zero, and returns
    /// the items it touched as they were before. Consuming more than is on the shelves empties them; zero, negative or
    /// NaN amounts change nothing.
    @discardableResult
    public func consume(foodID: FoodID, grams: Double) async throws -> [PantryItem] {
        guard grams > 0 else { return [] }
        return try await database.write { db in
            let records = try Self.byBestBy(PantryItemRecord.filter(Column("foodID") == foodID.key)).fetchAll(db)
            var remaining = grams
            var touched: [PantryItem] = []
            for var record in records where remaining > 0 {
                touched.append(record.item)
                let taken = min(record.quantityGrams, remaining)
                remaining -= taken
                record.quantityGrams -= taken
                if record.quantityGrams < Self.usedUpGrams {
                    try record.delete(db)
                } else {
                    try record.update(db)
                }
            }
            return touched
        }
    }

    public func record(_ events: [PantryEvent]) async throws {
        guard !events.isEmpty else { return }
        try await database.write { db in
            for event in events {
                try PantryEventRecord(event).upsert(db)
            }
        }
    }

    public func removeEvents(_ ids: [PantryEventID]) async throws {
        guard !ids.isEmpty else { return }
        try await database.write { db in
            _ = try PantryEventRecord.deleteAll(db, keys: ids.map(\.key))
        }
    }

    /// Events dated from `start` up to but not including `end`, oldest first; an empty or reversed range has none.
    public func events(from start: Date, to end: Date) async throws -> [PantryEvent] {
        guard start < end else { return [] }
        return try await database.read { db in
            try PantryEventRecord
                .filter(Column("date") >= start && Column("date") < end)
                .order(Column("date"), Column.rowID)
                .fetchAll(db)
                .map(\.event)
        }
    }

    private static func byBestBy(_ request: QueryInterfaceRequest<PantryItemRecord>) -> QueryInterfaceRequest<PantryItemRecord> {
        request.order(Column("bestBy").ascNullsLast, Column("addedOn"))
    }
}
