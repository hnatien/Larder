import Foundation
import LarderCore
import LarderDesign

/// Strings the grocery screen owns; shared strings live in `Copy`.
nonisolated enum GroceryCopy {
    static var itemToBuy: String { String(localized: "Item to buy", bundle: Copy.bundle) }
    static var addAnItem: String { String(localized: "Add an item", bundle: Copy.bundle) }
    static var add: String { String(localized: "Add", bundle: Copy.bundle) }
    static var emptyTitle: String { String(localized: "Nothing to buy", bundle: Copy.bundle) }
    static var emptyMessage: String { String(localized: "Plan a week or add items by hand.", bundle: Copy.bundle) }
    static var clearBasket: String { String(localized: "Clear basket", bundle: Copy.bundle) }
    static var inTheBasket: String { String(localized: "In the basket", bundle: Copy.bundle) }
    static var bought: String { String(localized: "bought", bundle: Copy.bundle) }
    static var toBuy: String { String(localized: "to buy", bundle: Copy.bundle) }
    static var haveSome: String { String(localized: "You have some already.", bundle: Copy.bundle) }

    static func markBought(_ name: String) -> String {
        String(localized: "Mark bought: \(name)", bundle: Copy.bundle)
    }

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
        case .loadFailed: String(localized: "Couldn't load the list. Pull to try again later.", bundle: Copy.bundle)
        case .pantryUpdateFailed: String(localized: "Couldn't update the shelves. The item is unchanged.", bundle: Copy.bundle)
        }
    }
}
