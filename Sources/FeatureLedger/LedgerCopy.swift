import Foundation
import LarderCore
import LarderDesign

/// Strings the ledger and Tonight screens own; shared strings live in `Copy`.
nonisolated enum LedgerCopy {
    static var cookThis: String { String(localized: "Cook this tonight", bundle: Copy.bundle) }
    static var startCooking: String { String(localized: "Start cooking", bundle: Copy.bundle) }
    static var tonightsDinner: String { String(localized: "Tonight's dinner", bundle: Copy.bundle) }
    static var ideasTitle: String { String(localized: "Ideas for tonight", bundle: Copy.bundle) }
    static var otherIdeasTitle: String { String(localized: "Or try something else", bundle: Copy.bundle) }
    static var ideasDetail: String { String(localized: "From what's in your pantry, best match first.", bundle: Copy.bundle) }
    static var browseRecipes: String { String(localized: "Browse recipes", bundle: Copy.bundle) }
    static var planSubtitle: String { String(localized: "Dinners for the next seven days", bundle: Copy.bundle) }
    static var replanQuestion: String { String(localized: "Replan the week?", bundle: Copy.bundle) }
    static var replanMessage: String {
        String(localized: "Unlocked dinners are chosen again from what you have. Locked ones stay where they are.", bundle: Copy.bundle)
    }
    static var moreActions: String { String(localized: "More", bundle: Copy.bundle) }
    static var balanceLegend: String {
        String(localized: "The dotted bracket shows a comfortable amount for the week.", bundle: Copy.bundle)
    }
    static var planSaved: String { String(localized: "Your week is planned", bundle: Copy.bundle) }
    static var seeRecipe: String { String(localized: "See recipe", bundle: Copy.bundle) }
    static var replan: String { String(localized: "Replan week", bundle: Copy.bundle) }
    static var whyThisWeek: String { String(localized: "Why this week?", bundle: Copy.bundle) }
    static var whyThis: String { String(localized: "Why this?", bundle: Copy.bundle) }
    static var nothingFits: String { String(localized: "No dinner planned", bundle: Copy.bundle) }
    static var nothingFitsTonight: String {
        String(localized: "Nothing in your pantry fits your settings tonight. Add a few more things and Larder will look again.", bundle: Copy.bundle)
    }
    static var pickOne: String { String(localized: "Choose a dinner", bundle: Copy.bundle) }
    static var lock: String { String(localized: "Lock", bundle: Copy.bundle) }
    static var unlock: String { String(localized: "Unlock", bundle: Copy.bundle) }
    static var locked: String { String(localized: "Locked", bundle: Copy.bundle) }
    static var cooked: String { String(localized: "Cooked", bundle: Copy.bundle) }
    static var skipped: String { String(localized: "Skipped", bundle: Copy.bundle) }
    static var moveToAnotherDay: String { String(localized: "Move to another day", bundle: Copy.bundle) }
    static var removeLeftover: String { String(localized: "Remove leftover", bundle: Copy.bundle) }
    static var useThis: String { String(localized: "Use this", bundle: Copy.bundle) }
    static var done: String { String(localized: "Done", bundle: Copy.bundle) }
    static var dismiss: String { String(localized: "Dismiss", bundle: Copy.bundle) }
    static var emptyShelvesTitle: String { String(localized: "Your pantry is empty", bundle: Copy.bundle) }
    static var noPlanTitle: String { String(localized: "No plan yet", bundle: Copy.bundle) }
    static var noPlanMessage: String {
        String(localized: "Larder picks seven dinners from what you have and writes the grocery list. You can swap, skip or move any of them.", bundle: Copy.bundle)
    }
    static var shelfHeading: String { String(localized: "Nutrition balance", bundle: Copy.bundle) }
    static var perDayHeading: String { String(localized: "Per day on average", bundle: Copy.bundle) }
    static var onForTonight: String { String(localized: "On for tonight", bundle: Copy.bundle) }
    static var noSwaps: String { String(localized: "Nothing else fits this slot right now.", bundle: Copy.bundle) }
    static var planning: String { String(localized: "Planning the week", bundle: Copy.bundle) }
    static var explaining: String { String(localized: "Working out the reasons", bundle: Copy.bundle) }
    static var shown: String { String(localized: "Shown", bundle: Copy.bundle) }
    static var hidden: String { String(localized: "Hidden", bundle: Copy.bundle) }
    static var daysRotor: String { String(localized: "Days", bundle: Copy.bundle) }

    /// A reason under "Why this week?", prefixed by its day.
    static func dayNote(day dayName: String, text: String) -> String {
        String(localized: "\(dayName): \(text)", bundle: Copy.bundle)
    }

    static func useRecipe(_ title: String) -> String {
        String(localized: "Use \(title)", bundle: Copy.bundle)
    }

    static func cookingTonight(_ title: String) -> String {
        String(localized: "\(title) is on for tonight.", bundle: Copy.bundle)
    }

    static func name(of slot: MealType) -> String {
        switch slot {
        case .breakfast: String(localized: "Breakfast", bundle: Copy.bundle)
        case .lunch: String(localized: "Lunch", bundle: Copy.bundle)
        case .dinner: String(localized: "Dinner", bundle: Copy.bundle)
        case .snack: String(localized: "Snack", bundle: Copy.bundle)
        }
    }

    /// The gap sentence for a week's shelf: the first light group, else the first heavy one, else nothing.
    static func balanceSentence(for balance: ShelfBalance) -> String? {
        if let group = balance.groupsLight.first {
            return Copy.Voice.lightOnGroup(Copy.Shelf.name(of: group).lowercased(with: nil))
        }
        if let group = balance.groupsHeavy.first {
            let name = Copy.Shelf.name(of: group).lowercased(with: nil)
            return String(localized: "Plenty of \(name) this week. A swap or two would even it out.", bundle: Copy.bundle)
        }
        return nil
    }

    /// A short "per day on average" line for one nutrient note, in the nutrient's own unit.
    static func average(_ note: NutrientNote, locale: Locale = .current) -> String? {
        let amount = note.totalPerDay.formatted(.number.precision(.fractionLength(0)).locale(locale))
        switch note.nutrient {
        case .energy: return String(localized: "Energy \(amount) kcal", bundle: Copy.bundle)
        case .protein: return String(localized: "Protein \(amount) g", bundle: Copy.bundle)
        case .fiber: return String(localized: "Fibre \(amount) g", bundle: Copy.bundle)
        case .sodium: return String(localized: "Sodium \(amount) mg", bundle: Copy.bundle)
        default: return nil
        }
    }

    static func message(for error: LarderError) -> String {
        switch error {
        case .notFound:
            String(localized: "Finish setting up your profile, then plan the week.", bundle: Copy.bundle)
        case .storageFailure:
            String(localized: "Couldn't save to this device. Check your storage and try again.", bundle: Copy.bundle)
        case .assistantUnavailable:
            String(localized: "Couldn't reach the assistant. The plan is saved and the reasons are under each meal.", bundle: Copy.bundle)
        case .quotaExceeded:
            String(localized: "This month's assistant allowance is used up. The reasons are under each meal.", bundle: Copy.bundle)
        case .invalidResponse, .declined:
            String(localized: "The assistant couldn't explain this week. The reasons are under each meal.", bundle: Copy.bundle)
        case .consentRequired:
            String(localized: "Cloud help is switched off. The reasons are under each meal.", bundle: Copy.bundle)
        case .plusRequired:
            String(localized: "That needs Larder Plus.", bundle: Copy.bundle)
        }
    }
}
