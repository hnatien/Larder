import Foundation
import LarderCore
import LarderDesign

/// Strings the shelves screen owns; shared strings live in `Copy`.
enum ShelvesCopy {
    static var eatFirst: String { String(localized: "Use soon", bundle: Copy.bundle) }
    static var eatFirstDetail: String { String(localized: "Tonight's ideas use these first.", bundle: Copy.bundle) }
    static var subtitle: String { String(localized: "What you have at home", bundle: Copy.bundle) }
    static var emptyTitle: String { String(localized: "Your pantry is empty", bundle: Copy.bundle) }
    static var draftPrompt: String { String(localized: "For example: 6 eggs, a bag of rice, 2 onions", bundle: Copy.bundle) }
    static var draftLabel: String { String(localized: "What did you bring home?", bundle: Copy.bundle) }
    static var draftHint: String {
        String(localized: "Type it the way you'd say it. You can check every line before it's added.", bundle: Copy.bundle)
    }
    static var parse: String { String(localized: "Read the list", bundle: Copy.bundle) }
    static var sheetTitle: String { String(localized: "Add food", bundle: Copy.bundle) }
    static var addByHand: String { String(localized: "Add one by hand", bundle: Copy.bundle) }
    static var staplesTitle: String { String(localized: "Quick add", bundle: Copy.bundle) }
    static var checkTitle: String { String(localized: "Check before adding", bundle: Copy.bundle) }
    static var searchPrompt: String { String(localized: "Search your pantry", bundle: Copy.bundle) }
    static var noMatches: String { String(localized: "Nothing in your pantry matches.", bundle: Copy.bundle) }
    static var editTitle: String { String(localized: "Edit item", bundle: Copy.bundle) }
    static var save: String { String(localized: "Save", bundle: Copy.bundle) }
    static var cancel: String { String(localized: "Cancel", bundle: Copy.bundle) }
    static var amountGrams: String { String(localized: "Amount in grams", bundle: Copy.bundle) }
    static var hasBestBy: String { String(localized: "Has a best-by date", bundle: Copy.bundle) }
    static var undo: String { String(localized: "Undo", bundle: Copy.bundle) }
    static var dismiss: String { String(localized: "Dismiss", bundle: Copy.bundle) }
    static var removeLine: String { String(localized: "Remove line", bundle: Copy.bundle) }
    static var name: String { String(localized: "Name", bundle: Copy.bundle) }
    static var quantity: String { String(localized: "Quantity", bundle: Copy.bundle) }
    static var unit: String { String(localized: "Unit", bundle: Copy.bundle) }
    static var location: String { String(localized: "Kept in", bundle: Copy.bundle) }
    static var bestBy: String { String(localized: "Best by", bundle: Copy.bundle) }

    /// Common foods for the Quick add chips.
    static var staples: [Staple] {
        [
            Staple(name: String(localized: "Eggs", bundle: Copy.bundle), quantity: 6, unit: .piece, location: .fridge),
            Staple(name: String(localized: "Milk", bundle: Copy.bundle), quantity: 1, unit: .litre, location: .fridge),
            Staple(name: String(localized: "Butter", bundle: Copy.bundle), quantity: 250, unit: .gram, location: .fridge),
            Staple(name: String(localized: "Onions", bundle: Copy.bundle), quantity: 3, unit: .piece, location: .pantry),
            Staple(name: String(localized: "Garlic", bundle: Copy.bundle), quantity: 1, unit: .piece, location: .pantry),
            Staple(name: String(localized: "Rice", bundle: Copy.bundle), quantity: 1, unit: .kilogram, location: .pantry),
            Staple(name: String(localized: "Pasta", bundle: Copy.bundle), quantity: 500, unit: .gram, location: .pantry),
            Staple(name: String(localized: "Chopped tomatoes", bundle: Copy.bundle), quantity: 800, unit: .gram, location: .pantry),
            Staple(name: String(localized: "Potatoes", bundle: Copy.bundle), quantity: 1, unit: .kilogram, location: .pantry),
            Staple(name: String(localized: "Olive oil", bundle: Copy.bundle), quantity: 500, unit: .millilitre, location: .pantry),
            Staple(name: String(localized: "Chicken thighs", bundle: Copy.bundle), quantity: 500, unit: .gram, location: .fridge),
            Staple(name: String(localized: "Spinach", bundle: Copy.bundle), quantity: 200, unit: .gram, location: .fridge),
        ]
    }

    static func name(of location: StorageLocation) -> String {
        switch location {
        case .fridge: String(localized: "Fridge", bundle: Copy.bundle)
        case .freezer: String(localized: "Freezer", bundle: Copy.bundle)
        case .pantry: String(localized: "Cupboard", bundle: Copy.bundle)
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

    /// Portion words that measure an amount rather than count things, so they are never used for a count.
    static let measureWords: Set<String> = ["cup", "tbsp", "tsp", "handful", "splash", "serving", "pinch", "ml", "g", "oz"]
    /// Words that qualify a portion's noun, so the noun before them takes the plural.
    static let qualifierWords: Set<String> = ["drained", "dry", "chopped", "sliced", "juice", "whole", "raw", "cooked", "peeled"]

    /// The amount as a count of things, such as "6 eggs", when a countable portion divides it within a fifth;
    /// otherwise grams or kilograms.
    static func quantity(grams: Double, portions: [Portion], locale: Locale = .current) -> String {
        let countable = portions
            .filter { $0.grams > 0 && Set($0.label.lowercased().split(separator: " ").map(String.init)).isDisjoint(with: measureWords) }
            .sorted { $0.grams > $1.grams }
        for portion in countable {
            let exact = grams / portion.grams
            let count = exact.rounded()
            if count >= 1, count <= 99, abs(exact - count) / count <= 0.2 {
                let number = Int(count)
                let label = number == 1 ? portion.label : plural(portion.label)
                return String(localized: "\(number) \(label)", bundle: Copy.bundle)
            }
        }
        return quantity(grams: grams, locale: locale)
    }

    /// An English portion label with its noun made plural: "medium onion" to "medium onions", "can drained" to "cans drained".
    static func plural(_ label: String) -> String {
        var words = label.split(separator: " ").map(String.init)
        guard let index = words.lastIndex(where: { !qualifierWords.contains($0.lowercased()) }) else { return label }
        let word = words[index]
        let lowered = word.lowercased()
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        if lowered.hasSuffix("s") || lowered.hasSuffix("x") || lowered.hasSuffix("ch") || lowered.hasSuffix("sh") {
            words[index] = word + "es"
        } else if lowered.hasSuffix("y"), let before = lowered.dropLast().last, !vowels.contains(before) {
            words[index] = word.dropLast() + "ies"
        } else {
            words[index] = word + "s"
        }
        return words.joined(separator: " ")
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
            ? String(localized: "Added 1 item to your pantry", bundle: Copy.bundle)
            : String(localized: "Added \(count) items to your pantry", bundle: Copy.bundle)
    }

    static func removed(_ action: UndoAction) -> String {
        let name = action.item.rawName
        return switch action.kind {
        case .eaten: String(localized: "\(name) used up", bundle: Copy.bundle)
        case .letGo: String(localized: "\(name) thrown away", bundle: Copy.bundle)
        }
    }

    static func label(item: String, quantity: String, freshness: String) -> String {
        String(localized: "\(item), \(quantity), \(freshness)", bundle: Copy.bundle)
    }

    static func message(for error: LarderError) -> String {
        switch error {
        case .consentRequired:
            String(localized: "Cloud help is switched off. Turn it on in Settings, or add the items by hand.", bundle: Copy.bundle)
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
            String(localized: "That item is no longer in your pantry.", bundle: Copy.bundle)
        case .storageFailure:
            String(localized: "Couldn't save to this device. Check your storage and try again.", bundle: Copy.bundle)
        }
    }
}
