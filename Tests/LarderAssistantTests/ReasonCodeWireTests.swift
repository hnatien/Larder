import Foundation
import Testing
import LarderCore
@testable import LarderAssistant

struct ReasonCodeWireTests {
    private static let spinach = FoodID()
    private static let names: [FoodID: String] = [spinach: "spinach"]

    static let cases: [(ReasonCode, ReasonCodeWire)] = [
        (.usesExpiring(food: spinach, bestBy: Fixtures.date(2026, 10, 18)),
         ReasonCodeWire(code: "usesExpiring", params: ["food": .string("spinach"), "bestBy": .string("2026-10-18")])),
        (.pantryOverlap(count: 4), ReasonCodeWire(code: "pantryOverlap", params: ["count": .number(4)])),
        (.quick(minutes: 20), ReasonCodeWire(code: "quick", params: ["minutes": .number(20)])),
        (.fibreGap(gramsShort: 6.5), ReasonCodeWire(code: "fibreGap", params: ["gramsShort": .number(6.5)])),
        (.varietyCuisine(cuisine: "Korean"), ReasonCodeWire(code: "varietyCuisine", params: ["cuisine": .string("Korean")])),
        (.leftoverOf(meal: PlannedMealID()), ReasonCodeWire(code: "leftoverOf")),
        (.underBudget, ReasonCodeWire(code: "underBudget")),
        (.cooksOften(cuisine: "Indian"), ReasonCodeWire(code: "cooksOften", params: ["cuisine": .string("Indian")])),
        (.cooksOftenWith(food: spinach), ReasonCodeWire(code: "cooksOftenWith", params: ["food": .string("spinach")])),
        (.movedFrom(date: Fixtures.date(2026, 10, 19)), ReasonCodeWire(code: "movedFrom", params: ["date": .string("2026-10-19")])),
        (.replacedBecause(cause: .skipped), ReasonCodeWire(code: "replacedBecause", params: ["cause": .string("skipped")])),
        (.replacedBecause(cause: .expired(food: spinach)),
         ReasonCodeWire(code: "replacedBecause", params: ["cause": .string("expired"), "food": .string("spinach")])),
        (.replacedBecause(cause: .outOfStock(food: FoodID())),
         ReasonCodeWire(code: "replacedBecause", params: ["cause": .string("outOfStock")])),
    ]

    @Test(arguments: cases)
    func everyCaseEncodesItsNameAndParams(reasonCode: ReasonCode, expected: ReasonCodeWire) {
        #expect(ReasonCodeWire(reasonCode, foodNames: Self.names) == expected)
    }

    @Test(arguments: cases)
    func everyCaseRoundTripsThroughJSON(reasonCode: ReasonCode, expected: ReasonCodeWire) throws {
        let wire = ReasonCodeWire(reasonCode, foodNames: Self.names)
        let data = try JSONEncoder().encode(wire)
        #expect(try JSONDecoder().decode(ReasonCodeWire.self, from: data) == wire)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["code", "params"])
    }

    @Test func identifiersNeverReachTheWire() throws {
        let meal = PlannedMealID()
        let unnamed = FoodID()
        let codes: [ReasonCode] = [.leftoverOf(meal: meal), .usesExpiring(food: unnamed, bestBy: Fixtures.date(2026, 10, 18))]
        let text = String(decoding: try JSONEncoder().encode(codes.map { ReasonCodeWire($0, foodNames: [:]) }), as: UTF8.self)
        #expect(!text.contains(meal.rawValue.uuidString))
        #expect(!text.contains(unnamed.rawValue.uuidString))
        #expect(ReasonCodeWire(codes[1], foodNames: [:]).params == ["bestBy": .string("2026-10-18")])
    }

    @Test func paramsDecodeEveryScalarType() throws {
        let json = #"{"code":"custom","params":{"flag":true,"count":3,"name":"rice"}}"#
        let wire = try JSONDecoder().decode(ReasonCodeWire.self, from: Data(json.utf8))
        #expect(wire.params == ["flag": .bool(true), "count": .number(3), "name": .string("rice")])
    }
}
