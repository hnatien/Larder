import Foundation
import LarderCore
import Testing
@testable import LarderPersistence

struct FoodRepositoryTests {
    let database: LarderDatabase
    let foods: GRDBFoodRepository

    init() throws {
        database = try LarderDatabase.inMemory()
        foods = GRDBFoodRepository(database: database)
    }

    @Test func foodRoundTripsEveryField() async throws {
        try await foods.upsert([Fixtures.fullFood])
        #expect(try await foods.food(by: Fixtures.fullFood.id) == Fixtures.fullFood)
    }

    @Test func upsertReplacesByIdentifierAndReindexes() async throws {
        var food = Fixtures.food("Brown rice")
        try await foods.upsert([food])
        food.name = "Basmati rice"
        try await foods.upsert([food])
        #expect(try await Fixtures.count("food", in: database) == 1)
        #expect(try await foods.search(text: "basmati", limit: 5) == [food])
        #expect(try await foods.search(text: "brown", limit: 5).isEmpty)
        try await Fixtures.checkSearchIndexes(in: database)
    }

    @Test func prefixSearchFindsChicken() async throws {
        try await foods.upsert([Fixtures.food("Chicken breast, raw"), Fixtures.food("Rice, white")])
        let names = try await foods.search(text: "chick", limit: 10).map(\.name)
        #expect(names == ["Chicken breast, raw"])
    }

    @Test(arguments: ["jalapeno", "jalapeño", "JALAP"])
    func searchIgnoresDiacriticsAndCase(query: String) async throws {
        try await foods.upsert([Fixtures.food("Jalapeño pepper"), Fixtures.food("Bell pepper")])
        #expect(try await foods.search(text: query, limit: 10).map(\.name) == ["Jalapeño pepper"])
    }

    @Test func searchRequiresEveryWord() async throws {
        try await foods.upsert([Fixtures.food("Chicken breast, raw"), Fixtures.food("Chicken thigh, roasted")])
        #expect(try await foods.search(text: "chicken ro", limit: 10).map(\.name) == ["Chicken thigh, roasted"])
        #expect(try await foods.search(text: "chicken boiled", limit: 10).isEmpty)
    }

    @Test func searchTreatsQuerySyntaxAsText() async throws {
        try await foods.upsert([Fixtures.food("Peanut butter")])
        #expect(try await foods.search(text: "peanut\" OR NEAR(", limit: 10).isEmpty)
        #expect(try await foods.search(text: "\"peanut*", limit: 10).map(\.name) == ["Peanut butter"])
    }

    @Test func searchWithoutWordsFallsBackToEscapedLike() async throws {
        try await foods.upsert([Fixtures.food("Salt & pepper"), Fixtures.food("Rice 100% whole grain"), Fixtures.food("Oats")])
        #expect(try await foods.search(text: "&", limit: 10).map(\.name) == ["Salt & pepper"])
        #expect(try await foods.search(text: "%", limit: 10).map(\.name) == ["Rice 100% whole grain"])
        #expect(try await foods.search(text: "_", limit: 10).isEmpty)
    }

    @Test func searchHonoursLimitAndRejectsEmptyInput() async throws {
        try await foods.upsert((1...5).map { Fixtures.food("Apple \($0)") })
        #expect(try await foods.search(text: "apple", limit: 3).count == 3)
        #expect(try await foods.search(text: "apple", limit: 0).isEmpty)
        #expect(try await foods.search(text: "   ", limit: 10).isEmpty)
    }

    @Test func foodsByIDsKeepRequestedOrderAndSkipUnknown() async throws {
        let rice = Fixtures.food("Rice")
        let oats = Fixtures.food("Oats")
        try await foods.upsert([rice, oats])
        #expect(try await foods.foods(byIDs: [oats.id, FoodID(), rice.id]) == [oats, rice])
        #expect(try await foods.foods(byIDs: []).isEmpty)
        #expect(try await foods.food(by: FoodID()) == nil)
    }
}
