import Foundation
import LarderCore

/// A reason code as the proxy receives it: the case name plus flat parameters, with no raw identifiers.
public struct ReasonCodeWire: Codable, Hashable, Sendable {
    public var code: String
    public var params: [String: Param]

    /// A JSON scalar parameter value.
    public enum Param: Codable, Hashable, Sendable {
        case string(String)
        case number(Double)
        case bool(Bool)

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else {
                self = .string(try container.decode(String.self))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            }
        }
    }

    /// Creates a wire value from its parts.
    public init(code: String, params: [String: Param] = [:]) {
        self.code = code
        self.params = params
    }

    /// Encodes `reasonCode`, replacing food identifiers with names from `foodNames` and omitting any it cannot name.
    public init(_ reasonCode: ReasonCode, foodNames: [FoodID: String]) {
        switch reasonCode {
        case .usesExpiring(let food, let bestBy):
            var params: [String: Param] = ["bestBy": .string(WireDate.string(from: bestBy))]
            if let name = foodNames[food] {
                params["food"] = .string(PromptSanitizer().scrub(name, limit: 80))
            }
            self.init(code: "usesExpiring", params: params)
        case .pantryOverlap(let count):
            self.init(code: "pantryOverlap", params: ["count": .number(Double(count))])
        case .quick(let minutes):
            self.init(code: "quick", params: ["minutes": .number(Double(minutes))])
        case .fibreGap(let gramsShort):
            self.init(code: "fibreGap", params: ["gramsShort": .number(gramsShort)])
        case .varietyCuisine(let cuisine):
            self.init(code: "varietyCuisine", params: ["cuisine": .string(PromptSanitizer().scrub(cuisine, limit: 80))])
        case .leftoverOf:
            self.init(code: "leftoverOf")
        case .underBudget:
            self.init(code: "underBudget")
        case .cooksOften(let cuisine):
            self.init(code: "cooksOften", params: ["cuisine": .string(PromptSanitizer().scrub(cuisine, limit: 80))])
        case .cooksOftenWith(let food):
            var params: [String: Param] = [:]
            if let name = foodNames[food] {
                params["food"] = .string(PromptSanitizer().scrub(name, limit: 80))
            }
            self.init(code: "cooksOftenWith", params: params)
        case .movedFrom(let date):
            self.init(code: "movedFrom", params: ["date": .string(WireDate.string(from: date))])
        case .replacedBecause(let cause):
            var params: [String: Param] = ["cause": .string(cause.wireName)]
            if let food = cause.food, let name = foodNames[food] {
                params["food"] = .string(PromptSanitizer().scrub(name, limit: 80))
            }
            self.init(code: "replacedBecause", params: params)
        }
    }
}

extension RepairCause {
    /// The cause's name on the wire, without its food.
    fileprivate var wireName: String {
        switch self {
        case .skipped: "skipped"
        case .notCooked: "notCooked"
        case .outOfStock: "outOfStock"
        case .expired: "expired"
        case .balance: "balance"
        }
    }

    fileprivate var food: FoodID? {
        switch self {
        case .outOfStock(let food), .expired(let food): food
        case .skipped, .notCooked, .balance: nil
        }
    }
}

/// Calendar dates on the wire: "YYYY-MM-DD" in UTC.
enum WireDate {
    private static let secondsPerDay: TimeInterval = 86_400

    static func string(from date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day())
    }

    static func string(dayOffset: Int, from start: Date) -> String {
        string(from: start.addingTimeInterval(Double(dayOffset) * secondsPerDay))
    }
}
