import Foundation
import LarderCore
import LarderDesign

/// Strings the shelves screen owns; shared strings live in `Copy`.
enum ShelvesCopy {
    static var eatFirst: String { String(localized: "Eat first", bundle: Copy.bundle) }
    static var emptyTitle: String { String(localized: "Nothing on the shelves", bundle: Copy.bundle) }
    static var draftPrompt: String { String(localized: "What did you bring home?", bundle: Copy.bundle) }
    static var parse: String { String(localized: "Parse", bundle: Copy.bundle) }
    static var sheetTitle: String { String(localized: "Add to the shelves", bundle: Copy.bundle) }
    static var addByHand: String { String(localized: "Add a line by hand", bundle: Copy.bundle) }
    static var undo: String { String(localized: "Undo", bundle: Copy.bundle) }
    static var dismiss: String { String(localized: "Dismiss", bundle: Copy.bundle) }
    static var removeLine: String { String(localized: "Remove line", bundle: Copy.bundle) }
    static var name: String { String(localized: "Name", bundle: Copy.bundle) }
    static var quantity: String { String(localized: "Quantity", bundle: Copy.bundle) }
    static var unit: String { String(localized: "Unit", bundle: Copy.bundle) }
    static var location: String { String(localized: "Kept in", bundle: Copy.bundle) }
    static var bestBy: String { String(localized: "Best by", bundle: Copy.bundle) }

    static func name(of location: StorageLocation) -> String {
        switch location {
        case .fridge: String(localized: "Fridge", bundle: Copy.bundle)
        case .freezer: String(localized: "Freezer", bundle: Copy.bundle)
        case .pantry: String(localized: "Pantry", bundle: Copy.bundle)
        case .other: String(localized: "Other", bundle: Copy.bundle)
        }
    }

    static func name(of unit: UnitOfMeasure) -> String {
        switch unit {
        case .gram: String(localized: "g", bundle: Copy.bundle)
        case .kilogram: String(localized: "kg", bundle: Copy.bundle)
        case .milligram: String(localized: "mg", bundle: Copy.bundle)
        case .millilitre: String(localized: "ml", bundle: Copy.bundle)
        case .litre: String(localized: "l", bundle: Copy.bundle)
        case .teaspoon: String(localized: "tsp", bundle: Copy.bundle)
        case .tablespoon: String(localized: "tbsp", bundle: Copy.bundle)
        case .cup: String(localized: "cup", bundle: Copy.bundle)
        case .fluidOunce: String(localized: "fl oz", bundle: Copy.bundle)
        case .ounce: String(localized: "oz", bundle: Copy.bundle)
        case .pound: String(localized: "lb", bundle: Copy.bundle)
        case .piece: String(localized: "piece", bundle: Copy.bundle)
        case .pinch: String(localized: "pinch", bundle: Copy.bundle)
        case .clove: String(localized: "clove", bundle: Copy.bundle)
        case .slice: String(localized: "slice", bundle: Copy.bundle)
        }
    }

    static func quantity(grams: Double, locale: Locale = .current) -> String {
        Quantity(value: grams, unit: .gram).formatted(locale: locale)
    }

    static func addItems(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "Add items", bundle: Copy.bundle)
        case 1: String(localized: "Add 1 item", bundle: Copy.bundle)
        default: String(localized: "Add \(count) items", bundle: Copy.bundle)
        }
    }

    static func added(_ count: Int) -> String {
        count == 1
            ? String(localized: "Added 1 item to the shelves", bundle: Copy.bundle)
            : String(localized: "Added \(count) items to the shelves", bundle: Copy.bundle)
    }

    static func removed(_ action: UndoAction) -> String {
        let name = action.item.rawName
        return switch action.kind {
        case .eaten: String(localized: "\(name) eaten", bundle: Copy.bundle)
        case .letGo: String(localized: "\(name) let go", bundle: Copy.bundle)
        }
    }

    static func label(item: String, quantity: String, freshness: String) -> String {
        String(localized: "\(item), \(quantity), \(freshness)", bundle: Copy.bundle)
    }

    static func message(for error: LarderError) -> String {
        switch error {
        case .consentRequired:
            String(localized: "Cloud help is switched off. Turn it on in Account, or add the items by hand.", bundle: Copy.bundle)
        case .assistantUnavailable:
            String(localized: "Couldn't read that just now. Add the items by hand instead.", bundle: Copy.bundle)
        case .quotaExceeded:
            String(localized: "This month's assistant allowance is used up. Add the items by hand.", bundle: Copy.bundle)
        case .invalidResponse:
            String(localized: "That didn't read as food. Try something like 2 onions, a bag of rice.", bundle: Copy.bundle)
        case .declined:
            String(localized: "The assistant couldn't help with that. Add the items by hand.", bundle: Copy.bundle)
        case .plusRequired:
            String(localized: "That needs Larder Plus.", bundle: Copy.bundle)
        case .notFound:
            String(localized: "That item is no longer on the shelves.", bundle: Copy.bundle)
        case .storageFailure:
            String(localized: "Couldn't save to this device. Check your storage and try again.", bundle: Copy.bundle)
        }
    }
}
