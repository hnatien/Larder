import Foundation
import GRDB
import LarderCore
import Testing
@testable import LarderPersistence

struct GroceryBasketRepositoryTests {
    let basket: GRDBGroceryBasketRepository
    let database: LarderDatabase

    init() throws {
        database = try LarderDatabase.inMemory()
        basket = GRDBGroceryBasketRepository(database: database)
    }

    static func plannedItem(_ name: String, foodID: FoodID? = FoodID(), grams: Double? = 120, unit: UnitOfMeasure = .gram) -> GroceryItem {
        GroceryItem(
            name: name, foodID: foodID, neededGrams: grams, displayQuantity: Quantity(value: grams ?? 2, unit: unit),
            aisle: .produce, partiallyInPantry: true, forMeals: [PlannedMealID()]
        )
    }

    @Test func manualItemsKeepTheOrderTheyWereAddedInAndAnEditKeepsItsPlace() async throws {
        var lemons = ManualItem(name: "Lemons", quantity: "3", aisle: .produce)
        let candles = ManualItem(name: "Candles")
        try await basket.saveManualItem(lemons)
        try await basket.saveManualItem(candles)
        lemons.quantity = "4"
        try await basket.saveManualItem(lemons)
        #expect(try await basket.manualItems() == [lemons, candles])
    }

    @Test func basketLinesRoundTripEveryKindOfKeyInTickOrder() async throws {
        let weighed = Self.plannedItem("Spinach")
        let unweighed = Self.plannedItem("limes", foodID: nil, grams: nil, unit: .piece)
        let manual = ManualItem(name: "Candles")
        try await basket.saveManualItem(manual)
        let lines = [
            BasketLine(key: GroceryItemKey(weighed), item: weighed, pantryItemID: PantryItemID(), checkedOn: Fixtures.date(2026, 10, 17, hour: 9)),
            BasketLine(key: GroceryItemKey(unweighed), item: unweighed, pantryItemID: nil, checkedOn: Fixtures.date(2026, 10, 17, hour: 8)),
            BasketLine(key: GroceryItemKey(manual), item: nil, pantryItemID: PantryItemID(), checkedOn: Fixtures.date(2026, 10, 17, hour: 10)),
        ]
        for line in lines {
            try await basket.saveBasketLine(line)
        }
        #expect(try await basket.basketLines() == lines)
    }

    @Test func savingALineWithTheSameKeyReplacesItInPlace() async throws {
        let spinach = Self.plannedItem("Spinach")
        let rice = Self.plannedItem("Rice")
        let first = BasketLine(key: GroceryItemKey(spinach), item: spinach, pantryItemID: nil, checkedOn: Fixtures.date(2026, 10, 17))
        try await basket.saveBasketLine(first)
        try await basket.saveBasketLine(BasketLine(key: GroceryItemKey(rice), item: rice, pantryItemID: nil, checkedOn: Fixtures.date(2026, 10, 17)))
        var replaced = first
        replaced.pantryItemID = PantryItemID()
        try await basket.saveBasketLine(replaced)
        #expect(try await basket.basketLines().map(\.pantryItemID) == [replaced.pantryItemID, nil])
    }

    @Test func removingLinesAndManualItems() async throws {
        let spinach = Self.plannedItem("Spinach")
        let manual = ManualItem(name: "Lemons")
        try await basket.saveManualItem(manual)
        try await basket.saveBasketLine(BasketLine(key: GroceryItemKey(spinach), item: spinach, pantryItemID: nil, checkedOn: .distantPast))
        try await basket.saveBasketLine(BasketLine(key: GroceryItemKey(manual), item: nil, pantryItemID: nil, checkedOn: .distantPast))

        try await basket.removeBasketLine(GroceryItemKey(spinach))
        try await basket.removeBasketLine(GroceryItemKey(spinach))
        try await basket.removeManualItem(manual.id)

        #expect(try await basket.basketLines().isEmpty)
        #expect(try await basket.manualItems().isEmpty)
    }

    @Test func clearBasketDropsTheLinesAndOnlyTheTickedManualItems() async throws {
        let spinach = Self.plannedItem("Spinach")
        let lemons = ManualItem(name: "Lemons")
        let candles = ManualItem(name: "Candles")
        try await basket.saveManualItem(lemons)
        try await basket.saveManualItem(candles)
        try await basket.saveBasketLine(BasketLine(key: GroceryItemKey(spinach), item: spinach, pantryItemID: nil, checkedOn: .distantPast))
        try await basket.saveBasketLine(BasketLine(key: GroceryItemKey(lemons), item: nil, pantryItemID: nil, checkedOn: .distantPast))

        try await basket.clearBasket()

        #expect(try await basket.basketLines().isEmpty)
        #expect(try await basket.manualItems() == [candles])
    }

    @Test func aRelaunchOnTheSameFileKeepsTheBasketAndManualItems() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "larder-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(filePath: url.path(percentEncoded: false) + suffix))
            }
        }
        let spinach = Self.plannedItem("Spinach")
        let lemons = ManualItem(name: "Lemons", quantity: "3", aisle: .produce)
        let lines = [
            BasketLine(key: GroceryItemKey(spinach), item: spinach, pantryItemID: PantryItemID(), checkedOn: Fixtures.date(2026, 10, 17)),
            BasketLine(key: GroceryItemKey(lemons), item: nil, pantryItemID: nil, checkedOn: Fixtures.date(2026, 10, 17)),
        ]
        do {
            let first = GRDBGroceryBasketRepository(database: try LarderDatabase.onDisk(at: url))
            try await first.saveManualItem(lemons)
            for line in lines {
                try await first.saveBasketLine(line)
            }
        }

        let relaunched = GRDBGroceryBasketRepository(database: try LarderDatabase.onDisk(at: url))
        #expect(try await relaunched.manualItems() == [lemons])
        #expect(try await relaunched.basketLines() == lines)
    }

    @Test func aStoredLineWithAnUnknownKindIsAnError() async throws {
        try await database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO groceryBasketLine (identityKind, identity, unit, checkedOn) VALUES ('recipe', 'x', '', '2026-10-17 00:00:00.000')
                """)
        }
        await #expect(throws: LarderPersistence.PersistenceError.self) { try await basket.basketLines() }
    }
}
