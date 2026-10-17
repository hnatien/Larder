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

    @Test func consumeReturnsTheItemsItTouchedAsTheyWereBefore() async throws {
        let older = Fixtures.pantryItem("Flour (open)", foodID: flour, grams: 200, bestBy: Fixtures.date(2026, 11, 1))
        let newer = Fixtures.pantryItem("Flour (new)", foodID: flour, grams: 1000, bestBy: Fixtures.date(2027, 6, 1))
        let untouched = Fixtures.pantryItem("Flour (spare)", foodID: flour, grams: 500, bestBy: nil)
        for item in [untouched, newer, older] {
            try await pantry.upsert(item)
        }
        let touched = try await pantry.consume(foodID: flour, grams: 350)
        #expect(touched == [older, newer])

        for item in touched {
            try await pantry.upsert(item)
        }
        #expect(Set(try await pantry.items()) == [older, newer, untouched])
    }

    @Test func consumingAFoodThatIsNotOnTheShelvesTouchesNothing() async throws {
        #expect(try await pantry.consume(foodID: flour, grams: 100).isEmpty)
    }

    @Test func eventsRoundTripAndReadByHalfOpenDateRangeOldestFirst() async throws {
        let mealID = PlannedMealID()
        let cooked = PantryEvent(kind: .cooked, foodID: flour, name: "Flour", grams: 250, date: Fixtures.date(2026, 10, 17, hour: 19), plannedMealID: mealID)
        let eaten = PantryEvent(kind: .eaten, foodID: nil, name: "Apple", grams: 180, date: Fixtures.date(2026, 10, 16, hour: 12))
        let expired = PantryEvent(kind: .expired, foodID: nil, name: "Milk", grams: 1000, date: Fixtures.date(2026, 10, 18))
        let earlier = PantryEvent(kind: .letGo, foodID: nil, name: "Kale", grams: 100, date: Fixtures.date(2026, 10, 15, hour: 23))
        try await pantry.record([cooked, eaten, expired, earlier])

        let week = try await pantry.events(from: Fixtures.date(2026, 10, 16), to: Fixtures.date(2026, 10, 18))
        #expect(week == [eaten, cooked])
        #expect(try await pantry.events(from: Fixtures.date(2026, 10, 18), to: Fixtures.date(2026, 10, 16)).isEmpty)
        #expect(try await pantry.events(from: Fixtures.date(2026, 10, 1), to: Fixtures.date(2026, 11, 1)) == [earlier, eaten, cooked, expired])
    }

    @Test func removeEventsDeletesOnlyThoseEvents() async throws {
        let kept = PantryEvent(kind: .eaten, foodID: nil, name: "Apple", grams: 180, date: Fixtures.date(2026, 10, 16))
        let undone = PantryEvent(kind: .letGo, foodID: nil, name: "Kale", grams: 100, date: Fixtures.date(2026, 10, 16))
        try await pantry.record([kept, undone])
        try await pantry.removeEvents([undone.id, PantryEventID()])
        try await pantry.removeEvents([])
        #expect(try await pantry.events(from: .distantPast, to: .distantFuture) == [kept])
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
