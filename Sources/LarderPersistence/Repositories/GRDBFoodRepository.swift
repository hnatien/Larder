import Foundation
import GRDB
import LarderCore

/// `FoodRepository` backed by the Larder SQLite store; throws `PersistenceError`.
public struct GRDBFoodRepository: FoodRepository {
    private let database: LarderDatabase

    /// Creates a repository over `database`.
    public init(database: LarderDatabase) {
        self.database = database
    }

    /// Prefix matches on every word of `text`, best first; falls back to a substring match when `text` has no words.
    public func search(text: String, limit: Int) async throws -> [Food] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, !text.isEmpty else { return [] }
        return try await database.read { db in
            let records: [FoodRecord]
            if let pattern = SearchText.prefixPattern(for: text) {
                records = try FoodRecord.fetchAll(
                    db,
                    sql: """
                        SELECT food.* FROM food
                        JOIN food_ft ON food_ft.rowid = food.rowid
                        WHERE food_ft MATCH ?
                        ORDER BY bm25(food_ft), food.name
                        LIMIT ?
                        """,
                    arguments: [pattern, limit]
                )
            } else {
                records = try FoodRecord
                    .filter(Column("name").like(SearchText.likePattern(for: text), escape: SearchText.likeEscape))
                    .order(Column("name"))
                    .limit(limit)
                    .fetchAll(db)
            }
            return try records.map { try $0.food() }
        }
    }

    public func food(by id: FoodID) async throws -> Food? {
        try await database.read { db in
            try FoodRecord.fetchOne(db, key: id.key)?.food()
        }
    }

    /// The foods with the given identifiers, in the order requested; unknown identifiers are skipped.
    public func foods(byIDs ids: [FoodID]) async throws -> [Food] {
        guard !ids.isEmpty else { return [] }
        return try await database.read { db in
            let records = try FoodRecord.fetchAll(db, keys: ids.map(\.key))
            let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            return try ids.compactMap { try byID[$0.rawValue]?.food() }
        }
    }

    public func food(byGTIN gtin: String) async throws -> Food? {
        let spellings = GTIN.spellings(of: gtin)
        guard !spellings.isEmpty else { return nil }
        return try await database.read { db in
            try FoodRecord
                .filter(spellings.contains(Column("gtin")))
                .order(Column("name"))
                .fetchOne(db)?
                .food()
        }
    }

    public func upsert(_ foods: [Food]) async throws {
        try await database.write { db in
            for food in foods {
                try FoodRecord(food).upsert(db)
            }
        }
    }
}
