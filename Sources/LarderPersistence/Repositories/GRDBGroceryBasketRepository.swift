import Foundation
import GRDB
import LarderCore

/// `GroceryBasketRepository` backed by the Larder SQLite store; throws `PersistenceError`.
public struct GRDBGroceryBasketRepository: GroceryBasketRepository {
    private let database: LarderDatabase

    /// Creates a repository over `database`.
    public init(database: LarderDatabase) {
        self.database = database
    }

    public func manualItems() async throws -> [ManualItem] {
        try await database.read { db in
            try GroceryManualItemRecord.order(Column("position")).fetchAll(db).map(\.item)
        }
    }

    /// A new item goes after the others; an existing one keeps its place.
    public func saveManualItem(_ item: ManualItem) async throws {
        try await database.write { db in
            let position: Int
            if let existing = try GroceryManualItemRecord.fetchOne(db, key: item.id.key) {
                position = existing.position
            } else {
                let last = try Int.fetchOne(db, sql: "SELECT MAX(position) FROM groceryManualItem")
                position = last.map { $0 + 1 } ?? 0
            }
            try GroceryManualItemRecord(item, position: position).upsert(db)
        }
    }

    public func removeManualItem(_ id: ManualItemID) async throws {
        try await database.write { db in
            _ = try GroceryManualItemRecord.deleteOne(db, key: id.key)
            try Self.deleteLine(GroceryItemKey(identity: .manual(id), unit: nil), in: db)
        }
    }

    public func basketLines() async throws -> [BasketLine] {
        try await database.read { db in
            try GroceryBasketLineRecord.order(Column.rowID).fetchAll(db).map { try $0.line() }
        }
    }

    public func saveBasketLine(_ line: BasketLine) async throws {
        try await database.write { db in
            try GroceryBasketLineRecord(line).upsert(db)
        }
    }

    public func removeBasketLine(_ key: GroceryItemKey) async throws {
        try await database.write { db in
            try Self.deleteLine(key, in: db)
        }
    }

    public func clearBasket() async throws {
        try await database.write { db in
            try db.execute(sql: """
                DELETE FROM groceryManualItem
                WHERE id IN (SELECT identity FROM groceryBasketLine WHERE identityKind = 'manual')
                """)
            _ = try GroceryBasketLineRecord.deleteAll(db)
        }
    }

    private static func deleteLine(_ key: GroceryItemKey, in db: Database) throws {
        let columns = GroceryBasketLineRecord.columns(of: key)
        _ = try GroceryBasketLineRecord.deleteOne(db, key: [
            "identityKind": columns.identityKind, "identity": columns.identity, "unit": columns.unit,
        ])
    }
}
