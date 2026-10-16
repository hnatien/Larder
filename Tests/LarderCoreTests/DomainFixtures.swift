import Foundation
@testable import LarderCore

enum Fixtures {
    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            preconditionFailure("Invalid fixture date \(year)-\(month)-\(day)")
        }
        return date
    }

    static func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    static let allReasonCodes: [ReasonCode] = [
        .usesExpiring(food: FoodID(), bestBy: date(2026, 10, 18)),
        .pantryOverlap(count: 4),
        .quick(minutes: 20),
        .fibreGap(gramsShort: 6.5),
        .varietyCuisine(cuisine: "Korean"),
        .leftoverOf(meal: PlannedMealID()),
        .underBudget,
    ]

    static let allConstraintKinds: [ConstraintKind] = [
        .allergen(.sesame),
        .intolerance("lactose"),
        .diet(.vegetarian),
        .medical(.hypertension),
        .dislike(.food(FoodID())),
        .dislike(.name("coriander")),
        .religious(.halal),
    ]

    static func caseName(_ code: ReasonCode) -> String {
        switch code {
        case .usesExpiring: "usesExpiring"
        case .pantryOverlap: "pantryOverlap"
        case .quick: "quick"
        case .fibreGap: "fibreGap"
        case .varietyCuisine: "varietyCuisine"
        case .leftoverOf: "leftoverOf"
        case .underBudget: "underBudget"
        }
    }

    static func caseName(_ kind: ConstraintKind) -> String {
        switch kind {
        case .allergen: "allergen"
        case .intolerance: "intolerance"
        case .diet: "diet"
        case .medical: "medical"
        case .dislike(.food): "dislikeFood"
        case .dislike(.name): "dislikeName"
        case .religious: "religious"
        }
    }
}
