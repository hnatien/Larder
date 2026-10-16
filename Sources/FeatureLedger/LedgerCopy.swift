import Foundation
import LarderCore
import LarderDesign

/// Strings the ledger and Tonight screens own; shared strings live in `Copy`.
nonisolated enum LedgerCopy {
    static var cookThis: String { String(localized: "Cook this") }
    static var seeRecipe: String { String(localized: "See recipe") }
    static var replan: String { String(localized: "Replan") }
    static var whyThisWeek: String { String(localized: "Why this week?") }
    static var whyThis: String { String(localized: "Why this?") }
    static var nothingFits: String { String(localized: "Nothing fits here yet") }
    static var nothingFitsTonight: String {
        String(localized: "Nothing on the shelves fits your settings tonight. Add a few more things and we'll look again.")
    }
    static var pickOne: String { String(localized: "Pick one") }
    static var lock: String { String(localized: "Lock") }
    static var unlock: String { String(localized: "Unlock") }
    static var locked: String { String(localized: "Locked") }
    static var cooked: String { String(localized: "Cooked") }
    static var skipped: String { String(localized: "Skipped") }
    static var moveToAnotherDay: String { String(localized: "Move to another day") }
    static var removeLeftover: String { String(localized: "Remove leftover") }
    static var useThis: String { String(localized: "Use this") }
    static var done: String { String(localized: "Done") }
    static var dismiss: String { String(localized: "Dismiss") }
    static var emptyShelvesTitle: String { String(localized: "Nothing on the shelves") }
    static var noPlanTitle: String { String(localized: "No plan yet") }
    static var noPlanMessage: String {
        String(localized: "Plan the week from what you have. Every meal can be swapped, skipped or moved later.")
    }
    static var shelfHeading: String { String(localized: "This week's shelf") }
    static var perDayHeading: String { String(localized: "Per day on average") }
    static var onForTonight: String { String(localized: "On for tonight") }
    static var picked: String { String(localized: "Picked for you") }
    static var noSwaps: String { String(localized: "Nothing else fits this slot right now.") }
    static var planning: String { String(localized: "Planning the week") }
    static var explaining: String { String(localized: "Working out the reasons") }
    static var shown: String { String(localized: "Shown") }
    static var hidden: String { String(localized: "Hidden") }

    /// A reason under "Why this week?", prefixed by its day.
    static func dayNote(day: String, text: String) -> String {
        String(localized: "\(day): \(text)")
    }

    /// The sentence under the Tonight heading.
    static func tonightContext(count: Int) -> String {
        switch count {
        case 1: String(localized: "One idea from what you have.")
        case 2: String(localized: "Two ideas from what you have.")
        default: String(localized: "Three ideas from what you have.")
        }
    }

    static func useRecipe(_ title: String) -> String {
        String(localized: "Use \(title)")
    }

    static func cookingTonight(_ title: String) -> String {
        String(localized: "\(title) is on for tonight.")
    }

    static func pickedAnnouncement(_ title: String) -> String {
        String(localized: "Picked \(title). Cook this to put it on tonight.")
    }

    static func name(of slot: MealType) -> String {
        switch slot {
        case .breakfast: String(localized: "Breakfast")
        case .lunch: String(localized: "Lunch")
        case .dinner: String(localized: "Dinner")
        case .snack: String(localized: "Snack")
        }
    }

    /// The gap sentence for a week's shelf: the first light group, else the first heavy one, else nothing.
    static func balanceSentence(for balance: ShelfBalance) -> String? {
        if let group = balance.groupsLight.first {
            return Copy.Voice.lightOnGroup(Copy.Shelf.name(of: group).lowercased(with: nil))
        }
        if let group = balance.groupsHeavy.first {
            let name = Copy.Shelf.name(of: group).lowercased(with: nil)
            return String(localized: "Plenty of \(name) this week. A swap or two would even it out.")
        }
        return nil
    }

    /// A short "per day on average" line for one nutrient note, in the nutrient's own unit.
    static func average(_ note: NutrientNote, locale: Locale = .current) -> String? {
        let amount = note.totalPerDay.formatted(.number.precision(.fractionLength(0)).locale(locale))
        switch note.nutrient {
        case .energy: return String(localized: "Energy \(amount) kcal")
        case .protein: return String(localized: "Protein \(amount) g")
        case .fiber: return String(localized: "Fibre \(amount) g")
        case .sodium: return String(localized: "Sodium \(amount) mg")
        default: return nil
        }
    }

    static func message(for error: LarderError) -> String {
        switch error {
        case .notFound:
            String(localized: "Finish setting up your profile, then plan the week.")
        case .storageFailure:
            String(localized: "Couldn't save to this device. Check your storage and try again.")
        case .assistantUnavailable:
            String(localized: "Couldn't reach the assistant. The plan is saved and the reasons are under each meal.")
        case .quotaExceeded:
            String(localized: "This month's assistant allowance is used up. The reasons are under each meal.")
        case .invalidResponse, .declined:
            String(localized: "The assistant couldn't explain this week. The reasons are under each meal.")
        case .consentRequired:
            String(localized: "Cloud help is switched off. The reasons are under each meal.")
        case .plusRequired:
            String(localized: "That needs Larder Plus.")
        }
    }
}
