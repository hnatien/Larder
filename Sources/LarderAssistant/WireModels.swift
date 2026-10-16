import Foundation
import LarderCore

struct SessionRequestBody: Encodable, Sendable {
    var attestation: Attestation

    struct Attestation: Encodable, Sendable {
        var kind: String
        var clientSecret: String
    }
}

struct SessionResponseBody: Decodable, Sendable {
    var token: String
    var expiresAt: String
}

struct ErrorBody: Decodable, Sendable {
    var error: String
    var category: String?
}

struct PlanWire: Codable, Hashable, Sendable {
    var days: [Day]

    struct Day: Codable, Hashable, Sendable {
        var date: String
        var meals: [Meal]
    }

    struct Meal: Codable, Hashable, Sendable {
        var slot: MealType
        var recipeTitle: String
        var minutes: Int
        var reasonCodes: [ReasonCodeWire]
    }
}

struct ExplainRequestBody: Encodable, Sendable {
    var plan: PlanWire
    var shelfBalance: ShelfBalance
    var profileSummary: ProfileSummary

    struct ShelfBalance: Encodable, Sendable {
        var groupsLight: [FoodGroup]
        var groupsHeavy: [FoodGroup]
    }
}

struct ExplainResponseBody: Decodable, Sendable {
    var headline: String
    var perDay: [DaySentence]
    var swapsOffered: [Swap]

    struct DaySentence: Decodable, Sendable {
        var date: String
        var sentence: String
    }

    struct Swap: Decodable, Sendable {
        var date: String
        var slot: MealType
        var alternativeTitle: String
        var reason: String
    }
}

struct ParsePantryRequestBody: Encodable, Sendable {
    var text: String
}

struct ParsePantryResponseBody: Decodable, Sendable {
    var lines: [Line]

    struct Line: Decodable, Sendable {
        var rawName: String
        var quantity: Double?
        var unit: String?
        var location: StorageLocation?
        var bestByHint: String?
    }
}

struct ParseRecipeRequestBody: Encodable, Sendable {
    var text: String?
    var imageBase64: String?
    var imageMediaType: String?
}

struct ParseRecipeResponseBody: Decodable, Sendable {
    var title: String
    var servings: Int?
    var prepMinutes: Int?
    var cookMinutes: Int?
    var ingredients: [Ingredient]
    var steps: [Step]

    struct Ingredient: Decodable, Sendable {
        var rawText: String
        var quantity: Double?
        var unit: String?
        var name: String
        var optional: Bool
    }

    struct Step: Decodable, Sendable {
        var text: String
        var timerSeconds: Int?
    }
}

struct ConstraintWire: Codable, Hashable, Sendable {
    var axis: String
    var kind: String
    var strictness: String
}

struct AdjustRequestBody: Encodable, Sendable {
    var instruction: String
    var currentConstraints: [ConstraintWire]
    var planContext: PlanWire
}

struct AdjustResponseBody: Decodable, Sendable {
    var edits: [Edit]
    var clarifyingQuestion: String?

    struct Edit: Decodable, Sendable {
        var op: String
        var constraint: ConstraintWire
        var scope: Scope
    }

    struct Scope: Decodable, Sendable {
        var dates: [String]?
        var slots: [MealType]?
    }
}
