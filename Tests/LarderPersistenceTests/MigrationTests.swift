import Foundation
import GRDB
import LarderCore
import Testing
@testable import LarderPersistence

struct MigrationTests {
    @Test func migrationsCreateEveryTableOnAnEmptyDatabase() async throws {
        let database = try LarderDatabase.inMemory()
        let tables = try await database.writer.read { db in
            try [
                "food", "recipe", "ingredient", "pantryItem", "mealPlan", "plannedMeal",
                "profile", "dietaryConstraint", "nutrientTarget", "recipe_ft", "food_ft",
            ].filter { try db.tableExists($0) }
        }
        #expect(tables.count == 11)
        let applied = try await database.writer.read { db in try Migrations.migrator.appliedIdentifiers(db) }
        #expect(applied == ["v1-schema"])
    }

    @Test func migratingAgainIsANoOp() async throws {
        let database = try LarderDatabase.inMemory()
        try await GRDBFoodRepository(database: database).upsert([Fixtures.food("Rice")])
        try Migrations.migrator.migrate(database.writer)
        let applied = try await database.writer.read { db in try Migrations.migrator.appliedIdentifiers(db) }
        #expect(applied == ["v1-schema"])
        #expect(try await Fixtures.count("food", in: database) == 1)
    }

    @Test func eraseAllEmptiesEveryTableAndKeepsTheSchema() async throws {
        let database = try LarderDatabase.inMemory()
        let food = Fixtures.food("Rice")
        let recipe = Fixtures.recipe("Rice bowl")
        try await GRDBFoodRepository(database: database).upsert([food])
        try await GRDBRecipeRepository(database: database)
            .save(recipe, ingredients: [Fixtures.ingredient("1 cup rice", recipeID: recipe.id, foodID: food.id)])
        try await GRDBPantryRepository(database: database)
            .upsert(Fixtures.pantryItem("Rice", foodID: food.id, grams: 500, bestBy: nil))

        try await database.eraseAll()

        for table in ["food", "recipe", "ingredient", "pantryItem"] {
            #expect(try await Fixtures.count(table, in: database) == 0)
        }
        let applied = try await database.writer.read { db in try Migrations.migrator.appliedIdentifiers(db) }
        #expect(applied == ["v1-schema"])
        #expect(try await GRDBRecipeRepository(database: database).search(text: "rice", limit: 5).isEmpty)
        try await GRDBFoodRepository(database: database).upsert([food])
        #expect(try await GRDBFoodRepository(database: database).food(by: food.id) == food)
    }

    @Test func eraseAllOnAnEmptyDatabaseLeavesItUsable() async throws {
        let database = try LarderDatabase.inMemory()
        try await database.eraseAll()
        try await database.eraseAll()
        #expect(try await GRDBProfileRepository(database: database).profile() == nil)
        #expect(try await Fixtures.count("food", in: database) == 0)
    }

    @Test func requestedIndexesExist() async throws {
        let database = try LarderDatabase.inMemory()
        let indexedColumns = try await database.writer.read { db in
            try ["plannedMeal", "pantryItem", "ingredient"].map { table in
                try db.indexes(on: table).map(\.columns)
            }
        }
        #expect(indexedColumns[0].contains(["planID", "date"]))
        #expect(indexedColumns[1].contains(["bestBy"]))
        #expect(indexedColumns[2].contains(["recipeID"]))
    }

    @Test func identifiersAreStoredAsUppercaseText() async throws {
        let database = try LarderDatabase.inMemory()
        let food = Fixtures.food("Rice")
        let recipe = Fixtures.recipe("Rice bowl")
        try await GRDBFoodRepository(database: database).upsert([food])
        try await GRDBRecipeRepository(database: database)
            .save(recipe, ingredients: [Fixtures.ingredient("1 cup rice", recipeID: recipe.id, foodID: food.id)])
        let columns = try await database.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT typeof(id), typeof(foodID), foodID FROM ingredient").map {
                [$0[0] as String, $0[1] as String, $0[2] as String]
            }
        }
        #expect(columns == ["text", "text", food.id.rawValue.uuidString])
    }

    @Test func foreignKeysAreEnforced() async throws {
        let database = try LarderDatabase.inMemory()
        let recipe = Fixtures.recipe("Toast")
        let unknownFood = FoodID()
        await #expect {
            try await GRDBRecipeRepository(database: database)
                .save(recipe, ingredients: [Fixtures.ingredient("bread", recipeID: recipe.id, foodID: unknownFood)])
        } throws: { error in
            guard case LarderPersistence.PersistenceError.database(let databaseError) = error else { return false }
            return databaseError.resultCode == .SQLITE_CONSTRAINT
        }
        #expect(try await GRDBRecipeRepository(database: database).recipe(by: recipe.id) == nil)
    }

    @Test func persistenceErrorsMapToLarderErrors() {
        #expect(LarderPersistence.PersistenceError.database(DatabaseError(resultCode: .SQLITE_FULL)).larderError == .storageFailure)
        #expect(LarderPersistence.PersistenceError.encoding(InvalidStoredValue(column: "seed", value: "x")).larderError == .storageFailure)
        #expect(LarderPersistence.PersistenceError.notFound.larderError == .notFound)
        #expect(LarderPersistence.PersistenceError.wrapping(CancellationError()) is CancellationError)
    }
}
