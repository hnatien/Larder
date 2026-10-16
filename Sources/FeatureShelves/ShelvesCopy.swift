import Foundation
import LarderCore

/// Strings the shelves screen owns; shared strings live in `Copy`.
enum ShelvesCopy {
    static var eatFirst: String { String(localized: "Eat first") }
    static var emptyTitle: String { String(localized: "Nothing on the shelves") }
    static var draftPrompt: String { String(localized: "What did you bring home?") }
    static var parse: String { String(localized: "Parse") }
    static var sheetTitle: String { String(localized: "Add to the shelves") }
    static var addByHand: String { String(localized: "Add a line by hand") }
    static var undo: String { String(localized: "Undo") }
    static var dismiss: String { String(localized: "Dismiss") }
    static var removeLine: String { String(localized: "Remove line") }
    static var name: String { String(localized: "Name") }
    static var quantity: String { String(localized: "Quantity") }
    static var unit: String { String(localized: "Unit") }
    static var location: String { String(localized: "Kept in") }
    static var bestBy: String { String(localized: "Best by") }

    static func name(of location: StorageLocation) -> String {
        switch location {
        case .fridge: String(localized: "Fridge")
        case .freezer: String(localized: "Freezer")
        case .pantry: String(localized: "Pantry")
        case .other: String(localized: "Other")
        }
    }

    static func name(of unit: UnitOfMeasure) -> String {
        switch unit {
        case .gram: String(localized: "g")
        case .kilogram: String(localized: "kg")
        case .milligram: String(localized: "mg")
        case .millilitre: String(localized: "ml")
        case .litre: String(localized: "l")
        case .teaspoon: String(localized: "tsp")
        case .tablespoon: String(localized: "tbsp")
        case .cup: String(localized: "cup")
        case .fluidOunce: String(localized: "fl oz")
        case .ounce: String(localized: "oz")
        case .pound: String(localized: "lb")
        case .piece: String(localized: "piece")
        case .pinch: String(localized: "pinch")
        case .clove: String(localized: "clove")
        case .slice: String(localized: "slice")
        }
    }

    static func quantity(grams: Double, locale: Locale = .current) -> String {
        Quantity(value: grams, unit: .gram).formatted(locale: locale)
    }

    static func addItems(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "Add items")
        case 1: String(localized: "Add 1 item")
        default: String(localized: "Add \(count) items")
        }
    }

    static func added(_ count: Int) -> String {
        count == 1
            ? String(localized: "Added 1 item to the shelves")
            : String(localized: "Added \(count) items to the shelves")
    }

    static func removed(_ action: UndoAction) -> String {
        switch action.kind {
        case .eaten: String(localized: "\(action.item.rawName) eaten")
        case .letGo: String(localized: "\(action.item.rawName) let go")
        }
    }

    static func label(item: String, quantity: String, freshness: String) -> String {
        String(localized: "\(item), \(quantity), \(freshness)")
    }

    static func message(for error: LarderError) -> String {
        switch error {
        case .consentRequired:
            String(localized: "Cloud help is switched off. Turn it on in Account, or add the items by hand.")
        case .assistantUnavailable:
            String(localized: "Couldn't read that just now. Add the items by hand instead.")
        case .quotaExceeded:
            String(localized: "This month's assistant allowance is used up. Add the items by hand.")
        case .invalidResponse:
            String(localized: "That didn't read as food. Try something like 2 onions, a bag of rice.")
        case .declined:
            String(localized: "The assistant couldn't help with that. Add the items by hand.")
        case .plusRequired:
            String(localized: "That needs Larder Plus.")
        case .notFound:
            String(localized: "That item is no longer on the shelves.")
        case .storageFailure:
            String(localized: "Couldn't save to this device. Check your storage and try again.")
        }
    }
}
