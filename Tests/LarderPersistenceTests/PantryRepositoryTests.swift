import Foundation
import LarderCore
import Testing
@testable import LarderPersistence

struct PantryRepositoryTests {
    let pantry: GRDBPantryRepository
    let flour = FoodID()

    init() throws {
        pantry = GRDBPantryRepository(database: try LarderDatabase.inMemory())
    }

    @Test func pantryItemRoundTripsEveryField() async throws {
        let item = PantryItem(
            foodID: flour,
            rawName: "Plain flour",
            quantityGrams: 987.5,
            location: .freezer,
            bestBy: Fixtures.date(2027, 1, 31),
            source: .receipt,
            addedOn: Fixtures.date(2026, 10, 16, hour: 9)
        )
        try await pantry.upsert(item)
        #expect(try await pantry.items() == [item])
    }

    @Test func itemsListEarliestBestByFirstAndUndatedLast() async throws {
        let undated = Fixtures.pantryItem("Salt", foodID: nil, grams: 500, bestBy: nil)
        let later = Fixtures.pantryItem("Rice", foodID: nil, grams: 500, bestBy: Fixtures.date(2027, 3, 1))
        let sooner = Fixtures.pantryItem("Milk", foodID: nil, grams: 1000, bestBy: Fixtures.date(2026, 10, 20))
        for item in [undated, later, sooner] {
            try await pantry.upsert(item)
        }
        #expect(try await pantry.items().map(\.rawName) == ["Milk", "Rice", "Salt"])
    }

    @Test func consumeTakesFromEarliestBestByAcrossItems() async throws {
        let older = Fixtures.pantryItem("Flour (open)", foodID: flour, grams: 200, bestBy: Fixtures.date(2026, 11, 1))
        let newer = Fixtures.pantryItem("Flour (new)", foodID: flour, grams: 1000, bestBy: Fixtures.date(2027, 6, 1))
        try await pantry.upsert(newer)
        try await pantry.upsert(older)
        try await pantry.consume(foodID: flour, grams: 350)
        let items = try await pantry.items()
        #expect(items.map(\.id) == [newer.id])
        #expect(items.first?.quantityGrams == 850)
    }

    @Test func consumeRemovesItemsThatReachZeroAndLeavesOtherFoods() async throws {
        let sugar = FoodID()
        try await pantry.upsert(Fixtures.pantryItem("Flour", foodID: flour, grams: 0.1 + 0.2, bestBy: nil))
        try await pantry.upsert(Fixtures.pantryItem("Sugar", foodID: sugar, grams: 100, bestBy: nil))
        try await pantry.consume(foodID: flour, grams: 0.3)
        #expect(try await pantry.items().map(\.foodID) == [sugar])
    }

    @Test func consumingMoreThanStockedEmptiesTheShelf() async throws {
        try await pantry.upsert(Fixtures.pantryItem("Flour", foodID: flour, grams: 100, bestBy: nil))
        try await pantry.upsert(Fixtures.pantryItem("Flour", foodID: flour, grams: 50, bestBy: Fixtures.date(2026, 12, 1)))
        try await pantry.consume(foodID: flour, grams: 400)
        #expect(try await pantry.items().isEmpty)
    }

    @Test(arguments: [0, -50, Double.nan])
    func consumingNonPositiveAmountsChangesNothing(grams: Double) async throws {
        let item = Fixtures.pantryItem("Flour", foodID: flour, grams: 100, bestBy: nil)
        try await pantry.upsert(item)
        try await pantry.consume(foodID: flour, grams: grams)
        #expect(try await pantry.items() == [item])
    }

    @Test func upsertReplacesAndRemoveDeletes() async throws {
        var item = Fixtures.pantryItem("Oats", foodID: nil, grams: 500, bestBy: nil)
        try await pantry.upsert(item)
        item.quantityGrams = 250
        try await pantry.upsert(item)
        #expect(try await pantry.items() == [item])
        try await pantry.remove(item.id)
        try await pantry.remove(item.id)
        #expect(try await pantry.items().isEmpty)
    }
}
