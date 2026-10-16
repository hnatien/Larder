import Foundation
import GRDB
import LarderCore

/// `RecipeRepository` backed by the Larder SQLite store; throws `PersistenceError`.
public struct GRDBRecipeRepository: RecipeRepository {
    private let database: LarderDatabase

    /// Creates a repository over `database`.
    public init(database: LarderDatabase) {
        self.database = database
    }

    /// Every recipe, by title.
    public func all() async throws -> [Recipe] {
        try await database.read { db in
            try RecipeRecord.order(Column("title")).fetchAll(db).map(\.recipe)
        }
    }

    /// Prefix matches on every word of `text` across titles and ingredient lines, best first;
    /// falls back to a title substring match when `text` has no words.
    public func search(text: String, limit: Int) async throws -> [Recipe] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, !text.isEmpty else { return [] }
        return try await database.read { db in
            if let pattern = SearchText.prefixPattern(for: text) {
                return try RecipeRecord.fetchAll(
                    db,
                    sql: """
                        SELECT recipe.* FROM recipe
                        JOIN recipe_ft ON recipe_ft.rowid = recipe.rowid
                        WHERE recipe_ft MATCH ?
                        ORDER BY bm25(recipe_ft), recipe.title
                        LIMIT ?
                        """,
                    arguments: [pattern, limit]
                ).map(\.recipe)
            }
            return try RecipeRecord
                .filter(Column("title").like(SearchText.likePattern(for: text), escape: SearchText.likeEscape))
                .order(Column("title"))
                .limit(limit)
                .fetchAll(db)
                .map(\.recipe)
        }
    }

    public func recipe(by id: RecipeID) async throws -> Recipe? {
        try await database.read { db in
            try RecipeRecord.fetchOne(db, key: id.key)?.recipe
        }
    }

    /// Writes the recipe, replaces its ingredient lines and reindexes it, all in one transaction.
    public func save(_ recipe: Recipe, ingredients: [Ingredient]) async throws {
        try await database.write { db in
            try Self.save(recipe, ingredients: ingredients, in: db)
        }
    }

    public func delete(_ id: RecipeID) async throws {
        try await database.write { db in
            try Self.removeFromSearchIndex(id, in: db)
            try RecipeRecord.deleteOne(db, key: id.key)
        }
    }

    public func ingredients(for recipeID: RecipeID) async throws -> [Ingredient] {
        try await database.read { db in
            try IngredientRecord
                .filter(Column("recipeID") == recipeID.key)
                .order(Column("position"))
                .fetchAll(db)
                .map(\.ingredient)
        }
    }

    /// Saves inside an open transaction; shared with `SeedLoader`.
    static func save(_ recipe: Recipe, ingredients: [Ingredient], in db: Database) throws {
        try removeFromSearchIndex(recipe.id, in: db)
        try RecipeRecord(recipe).upsert(db)
        try IngredientRecord.filter(Column("recipeID") == recipe.id.key).deleteAll(db)
        for (position, ingredient) in ingredients.enumerated() {
            try IngredientRecord(ingredient, position: position).insert(db)
        }
        try refreshSearchIndex(for: recipe.id, in: db)
    }

    /// Indexes the recipe's current title and ingredient text in `recipe_ft`.
    ///
    /// `recipe_ft` is an external-content table over the `recipe_search` view, so it is maintained explicitly in
    /// the same transaction as the write: `removeFromSearchIndex` must run before the recipe or its ingredients
    /// change (FTS5 deletes by the exact values that were indexed), and this runs after.
    static func refreshSearchIndex(for id: RecipeID, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO recipe_ft(rowid, title, ingredients)
                SELECT recipeRowID, title, ingredients FROM recipe_search
                WHERE recipeRowID = (SELECT rowid FROM recipe WHERE id = ?)
                """,
            arguments: [id.key]
        )
    }

    private static func removeFromSearchIndex(_ id: RecipeID, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO recipe_ft(recipe_ft, rowid, title, ingredients)
                SELECT 'delete', recipeRowID, title, ingredients FROM recipe_search
                WHERE recipeRowID = (SELECT rowid FROM recipe WHERE id = ?)
                """,
            arguments: [id.key]
        )
    }
}
