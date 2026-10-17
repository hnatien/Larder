import GRDB

/// The schema, applied in registration order.
enum Migrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-schema", migrate: createV1Schema)
        migrator.registerMigration("v2-recipe-photo", migrate: addRecipePhoto)
        migrator.registerMigration("v3-pantry-loop", migrate: addPantryLoop)
        return migrator
    }

    /// The log of food leaving the shelves, and the grocery basket and hand-written items, so a relaunch keeps them.
    ///
    /// A basket line's key is its identity kind ("food", "name" or "manual"), the identity's text and the unit of a
    /// line that could not be weighed, empty for a weighed one so the primary key has no NULL.
    private static func addPantryLoop(_ db: Database) throws {
        try db.create(table: "pantryEvent") { t in
            t.primaryKey("id", .text)
            t.column("kind", .text).notNull()
            t.column("foodID", .text)
            t.column("name", .text).notNull()
            t.column("grams", .double).notNull()
            t.column("date", .datetime).notNull()
            t.column("plannedMealID", .text)
        }
        try db.create(indexOn: "pantryEvent", columns: ["date"])

        try db.create(table: "groceryManualItem") { t in
            t.primaryKey("id", .text)
            t.column("position", .integer).notNull()
            t.column("name", .text).notNull()
            t.column("quantity", .text).notNull()
            t.column("aisle", .text).notNull()
        }

        try db.create(table: "groceryBasketLine") { t in
            t.column("identityKind", .text).notNull()
            t.column("identity", .text).notNull()
            t.column("unit", .text).notNull()
            t.column("item", .jsonText)
            t.column("pantryItemID", .text)
            t.column("checkedOn", .datetime).notNull()
            t.primaryKey(["identityKind", "identity", "unit"])
        }
    }

    /// Imported recipes can keep the page's photo; the column holds its file name in the photo store.
    private static func addRecipePhoto(_ db: Database) throws {
        try db.alter(table: "recipe") { t in
            t.add(column: "photoFileName", .text)
        }
    }

    private static func createV1Schema(_ db: Database) throws {
        try db.create(table: "food") { t in
            t.primaryKey("id", .text)
            t.column("name", .text).notNull()
            t.column("source", .text).notNull()
            t.column("fdcID", .integer)
            t.column("gtin", .text)
            t.column("foodGroup", .text).notNull()
            t.column("densityGPerMl", .double)
            t.column("nutrients", .jsonText).notNull()
            t.column("portions", .jsonText).notNull()
            t.column("allergens", .jsonText).notNull()
            t.column("tags", .jsonText).notNull()
        }

        try db.create(table: "recipe") { t in
            t.primaryKey("id", .text)
            t.column("title", .text).notNull()
            t.column("origin", .text).notNull()
            t.column("sourceURL", .text)
            t.column("license", .text)
            t.column("servings", .integer).notNull()
            t.column("prepMinutes", .integer).notNull()
            t.column("cookMinutes", .integer).notNull()
            t.column("steps", .jsonText).notNull()
            t.column("cuisine", .text)
            t.column("mealTypes", .jsonText).notNull()
            t.column("equipment", .jsonText).notNull()
            t.column("dietFlags", .jsonText).notNull()
        }

        try db.create(table: "ingredient") { t in
            t.primaryKey("id", .text)
            t.column("recipeID", .text).notNull().references("recipe", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("rawText", .text).notNull()
            t.column("quantity", .double).notNull()
            t.column("unit", .text).notNull()
            t.column("foodID", .text).references("food", onDelete: .setNull)
            t.column("gramsResolved", .double)
            t.column("matchConfidence", .double).notNull()
            t.column("isOptional", .boolean).notNull()
            t.column("isGarnish", .boolean).notNull()
        }
        try db.create(indexOn: "ingredient", columns: ["recipeID"])

        try db.create(table: "pantryItem") { t in
            t.primaryKey("id", .text)
            t.column("foodID", .text)
            t.column("rawName", .text).notNull()
            t.column("quantityGrams", .double).notNull()
            t.column("location", .text).notNull()
            t.column("bestBy", .datetime)
            t.column("source", .text).notNull()
            t.column("addedOn", .datetime).notNull()
        }
        try db.create(indexOn: "pantryItem", columns: ["bestBy"])

        try db.create(table: "mealPlan") { t in
            t.primaryKey("id", .text)
            t.column("startDate", .datetime).notNull()
            t.column("days", .integer).notNull()
            t.column("constraintsSnapshot", .text).notNull()
            t.column("solverVersion", .text).notNull()
            t.column("seed", .text).notNull()
            t.column("status", .text).notNull()
        }

        try db.create(table: "plannedMeal") { t in
            t.primaryKey("id", .text)
            t.column("planID", .text).notNull().references("mealPlan", onDelete: .cascade)
            t.column("date", .datetime).notNull()
            t.column("slot", .text).notNull()
            t.column("recipeID", .text).notNull()
            t.column("servings", .integer).notNull()
            t.column("leftoverOf", .text)
            t.column("isLocked", .boolean).notNull()
            t.column("status", .text).notNull()
            t.column("reasonCodes", .jsonText).notNull()
            t.column("swapHistory", .jsonText).notNull()
        }
        try db.create(indexOn: "plannedMeal", columns: ["planID", "date"])

        try db.create(table: "profile") { t in
            t.primaryKey("id", .integer).check { $0 == 1 }
            t.column("profile", .jsonText).notNull()
        }

        try db.create(table: "dietaryConstraint") { t in
            t.primaryKey("id", .text)
            t.column("position", .integer).notNull()
            t.column("axis", .text).notNull()
            t.column("kind", .jsonText).notNull()
            t.column("strictness", .text).notNull()
            t.column("source", .text).notNull()
            t.column("lastConfirmed", .datetime).notNull()
        }

        try db.create(table: "nutrientTarget") { t in
            t.primaryKey("position", .integer)
            t.column("nutrient", .text).notNull()
            t.column("basis", .text).notNull()
            t.column("min", .double)
            t.column("target", .double)
            t.column("max", .double)
            t.column("priority", .integer).notNull()
            t.column("source", .text).notNull()
        }

        try createSearchIndexes(db)
    }

    /// `food_ft` follows `food` through GRDB's synchronization triggers. `recipe_ft` indexes a view that
    /// joins each recipe title to its ingredient text; it is kept current by
    /// `GRDBRecipeRepository.refreshSearchIndex(for:in:)` rather than triggers, because one recipe save
    /// rewrites many ingredient rows and per-row triggers would reindex the recipe once per row while the
    /// view is half updated.
    private static func createSearchIndexes(_ db: Database) throws {
        try db.create(virtualTable: "food_ft", using: FTS5()) { t in
            t.synchronize(withTable: "food")
            t.tokenizer = .unicode61(diacritics: .remove)
            t.column("name")
        }

        try db.execute(sql: """
            CREATE VIEW recipe_search AS
            SELECT recipe.rowid AS recipeRowID,
                   recipe.title AS title,
                   COALESCE(
                       (SELECT group_concat(ingredient.rawText, ' ' ORDER BY ingredient.position)
                        FROM ingredient WHERE ingredient.recipeID = recipe.id),
                       '') AS ingredients
            FROM recipe
            """)
        try db.create(virtualTable: "recipe_ft", using: FTS5()) { t in
            t.content = "recipe_search"
            t.contentRowID = "recipeRowID"
            t.tokenizer = .unicode61(diacritics: .remove)
            t.column("title")
            t.column("ingredients")
        }
    }
}
