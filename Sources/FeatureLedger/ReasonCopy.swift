import Foundation
import LarderCore
import LarderDesign

/// Turns reason codes into the one-line reasons shown on cards and in the ledger. Pure, so it is testable without SwiftUI.
nonisolated enum ReasonCopy {
    /// What a reason needs to name things: food names, the dates of source meals, and how to print a weekday.
    struct Lookup {
        var foodNames: [FoodID: String] = [:]
        var mealDates: [PlannedMealID: Date] = [:]
        var locale: Locale = .current
        var calendar: Calendar = .current
    }

    /// One line per code, in order, at most `limit`.
    static func lines(for codes: [ReasonCode], lookup: Lookup, limit: Int = .max) -> [String] {
        Array(codes.prefix(max(limit, 0)).map { line(for: $0, lookup: lookup) })
    }

    /// The line for one code.
    static func line(for code: ReasonCode, lookup: Lookup) -> String {
        switch code {
        case .usesExpiring(let food, let bestBy):
            let dayName = weekday(bestBy, lookup: lookup)
            guard let name = lookup.foodNames[food].map(displayName), !name.isEmpty else {
                return String(localized: "Uses what's best by \(dayName)", bundle: Copy.bundle)
            }
            return String(localized: "Uses the \(name) before \(dayName)", bundle: Copy.bundle)
        case .pantryOverlap(let count):
            return String(localized: "Uses \(count) things you have", bundle: Copy.bundle)
        case .quick(let minutes):
            return String(localized: "On the table in \(minutes) minutes", bundle: Copy.bundle)
        case .varietyCuisine:
            return String(localized: "Something different from this week", bundle: Copy.bundle)
        case .leftoverOf(let meal):
            guard let date = lookup.mealDates[meal] else { return String(localized: "Leftovers from earlier this week", bundle: Copy.bundle) }
            let dayName = weekday(date, lookup: lookup)
            return String(localized: "Leftovers from \(dayName)", bundle: Copy.bundle)
        case .underBudget:
            return String(localized: "Easy on the budget", bundle: Copy.bundle)
        case .fibreGap:
            return String(localized: "Adds the fibre this week is short of", bundle: Copy.bundle)
        case .cooksOften(let cuisine):
            return String(localized: "You cook a lot of \(cuisine) food", bundle: Copy.bundle)
        case .cooksOftenWith(let food):
            guard let name = lookup.foodNames[food].map(displayName), !name.isEmpty else {
                return String(localized: "Like what you cook most", bundle: Copy.bundle)
            }
            return String(localized: "You cook a lot with \(name)", bundle: Copy.bundle)
        }
    }

    /// "Spinach, raw" reads as "spinach".
    static func displayName(_ name: String) -> String {
        let head = name.split(separator: ",", maxSplits: 1).first.map(String.init) ?? name
        return head.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: nil)
    }

    private static func weekday(_ date: Date, lookup: Lookup) -> String {
        date.formatted(
            Date.FormatStyle(locale: lookup.locale, calendar: lookup.calendar, timeZone: lookup.calendar.timeZone).weekday(.wide)
        )
    }
}
