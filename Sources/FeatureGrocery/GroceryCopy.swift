import Foundation
import LarderCore
import LarderDesign

/// Strings the grocery screen owns; shared strings live in `Copy`.
nonisolated enum GroceryCopy {
    static var itemToBuy: String { String(localized: "Item to buy", bundle: Copy.bundle) }
    static var addAnItem: String { String(localized: "Add something to buy", bundle: Copy.bundle) }
    static var add: String { String(localized: "Add", bundle: Copy.bundle) }
    static var emptyTitle: String { String(localized: "Nothing to buy", bundle: Copy.bundle) }
    static var emptyMessage: String {
        String(localized: "Plan your week and Larder writes the list, leaving out what you already have. You can also add things by hand above.", bundle: Copy.bundle)
    }
    static var openPlan: String { String(localized: "Go to Plan", bundle: Copy.bundle) }
    static var clearBasket: String { String(localized: "Remove bought items", bundle: Copy.bundle) }
    static var inTheBasket: String { String(localized: "Bought", bundle: Copy.bundle) }
    static var tickHint: String { String(localized: "Ticked food goes into your pantry. Untick to take it back out.", bundle: Copy.bundle) }
    static var delete: String { String(localized: "Delete", bundle: Copy.bundle) }
    static var share: String { String(localized: "Share list", bundle: Copy.bundle) }
    static func subtitle(toBuy count: Int) -> String {
        count == 0
            ? String(localized: "Nothing left to buy", bundle: Copy.bundle)
            : String(localized: "\(count) to buy", bundle: Copy.bundle)
    }
    static var bought: String { String(localized: "bought", bundle: Copy.bundle) }
    static var toBuy: String { String(localized: "to buy", bundle: Copy.bundle) }
    static var haveSome: String { String(localized: "You have some already.", bundle: Copy.bundle) }

    /// A food database name as a shopper would write it: the part before the first comma, so "Potato, raw, flesh and
    /// skin" reads "Potato". A name without a comma, or with nothing before it, is kept whole.
    static func shoppingName(_ name: String) -> String {
        let head = name.prefix { $0 != "," }.trimmingCharacters(in: .whitespaces)
        return head.isEmpty ? name : head
    }

    /// The dinner a planned line is for, and how many others need it too.
    static func forMeal(_ dish: String, day weekday: String, more count: Int) -> String {
        count == 0
            ? String(localized: "For \(dish) on \(weekday)", bundle: Copy.bundle)
            : String(localized: "For \(dish) on \(weekday) and \(count) more", bundle: Copy.bundle)
    }

    /// The toast after a tick or a removal.
    static func notice(_ kind: GroceryNotice.Kind) -> String {
        switch kind {
        case .landed(let name):
            return String(localized: "\(name) is in your pantry", bundle: Copy.bundle)
        case .removed(let count):
            return count == 1
                ? String(localized: "Removed from the list", bundle: Copy.bundle)
                : String(localized: "\(count) items removed from the list", bundle: Copy.bundle)
        }
    }

    static var undo: String { String(localized: "Undo", bundle: Copy.bundle) }
    static var tryAgain: String { String(localized: "Try again", bundle: Copy.bundle) }
    static var dismiss: String { String(localized: "Dismiss", bundle: Copy.bundle) }
    static var markBoughtHint: String { String(localized: "Ticking puts it in your pantry", bundle: Copy.bundle) }

    /// The heading shown above an aisle.
    static func name(of aisle: Aisle) -> String {
        switch aisle {
        case .produce: String(localized: "Produce", bundle: Copy.bundle)
        case .bakery: String(localized: "Bakery", bundle: Copy.bundle)
        case .meatAndFish: String(localized: "Meat and fish", bundle: Copy.bundle)
        case .dairyAndEggs: String(localized: "Dairy and eggs", bundle: Copy.bundle)
        case .pantryDry: String(localized: "Dry staples", bundle: Copy.bundle)
        case .cannedAndJarred: String(localized: "Canned and jarred", bundle: Copy.bundle)
        case .frozen: String(localized: "Frozen", bundle: Copy.bundle)
        case .spicesAndOils: String(localized: "Spices and oils", bundle: Copy.bundle)
        case .other: String(localized: "Other", bundle: Copy.bundle)
        }
    }

    static func message(for error: GroceryError) -> String {
        switch error {
        case .loadFailed: String(localized: "Couldn't load the list.", bundle: Copy.bundle)
        case .pantryUpdateFailed: String(localized: "Couldn't update your pantry. The item is unchanged.", bundle: Copy.bundle)
        case .basketUpdateFailed: String(localized: "Couldn't save the list. Try again.", bundle: Copy.bundle)
        }
    }
}
