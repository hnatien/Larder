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
        String(localized: "Unlocked dinners are chosen again from what you have. Locked and cooked ones stay where they are.", bundle: Copy.bundle)
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
    static var nothingFitsTitle: String { String(localized: "Nothing fits tonight", bundle: Copy.bundle) }
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
    static var tryAgain: String { String(localized: "Try again", bundle: Copy.bundle) }
    static var emptyShelvesTitle: String { String(localized: "Nothing to cook from yet", bundle: Copy.bundle) }
    static var tonightLoadFailed: String {
        String(localized: "Couldn't load tonight's ideas. Your pantry and plan are safe.", bundle: Copy.bundle)
    }
    static var noOtherIdeas: String {
        String(localized: "Nothing else in your pantry fits tonight.", bundle: Copy.bundle)
    }
    static var noRulesReminder: String {
        String(localized: "Nothing is left out yet. Add allergies or a diet in Settings and every idea leaves them out.", bundle: Copy.bundle)
    }
    static var markPlanned: String { String(localized: "Put back on the plan", bundle: Copy.bundle) }
    static var weekOver: String {
        String(localized: "This week has ended. Plan the next seven days when you're ready.", bundle: Copy.bundle)
    }
    static var cookedTonight: String { String(localized: "Cooked", bundle: Copy.bundle) }
    static var replaceKeep: String { String(localized: "Keep it", bundle: Copy.bundle) }
    static var noPlanTitle: String { String(localized: "No plan yet", bundle: Copy.bundle) }
    static var noPlanMessage: String {
        String(localized: "Larder picks seven dinners from what you have and writes the grocery list. You can swap, skip or move any of them.", bundle: Copy.bundle)
    }
    static var shelfHeading: String { String(localized: "Nutrition balance", bundle: Copy.bundle) }
    static var perDayHeading: String { String(localized: "Per day on average", bundle: Copy.bundle) }
    static var noSwaps: String { String(localized: "Nothing else fits this slot right now.", bundle: Copy.bundle) }
    static var planning: String { String(localized: "Planning the week", bundle: Copy.bundle) }
    static var explaining: String { String(localized: "Working out the reasons", bundle: Copy.bundle) }
    static var shown: String { String(localized: "Shown", bundle: Copy.bundle) }
    static var hidden: String { String(localized: "Hidden", bundle: Copy.bundle) }
    static var daysRotor: String { String(localized: "Days", bundle: Copy.bundle) }

    static var adjustTitle: String { String(localized: "Adjust this week", bundle: Copy.bundle) }
    static var adjustPrompt: String { String(localized: "Vegetarian Tuesday, quicker dinners, use the rice", bundle: Copy.bundle) }
    static var adjustHint: String {
        String(localized: "The assistant turns this into changes for this week. Your settings stay as they are.", bundle: Copy.bundle)
    }
    static var adjustAsk: String { String(localized: "Ask", bundle: Copy.bundle) }
    static var adjusting: String { String(localized: "Reading your request", bundle: Copy.bundle) }
    static var proposalTitle: String { String(localized: "Changes for this week", bundle: Copy.bundle) }
    static var applyAndReplan: String { String(localized: "Apply and replan", bundle: Copy.bundle) }
    static var adjustNeedsConsent: String {
        String(localized: "Adjusting the week uses AI help, which is off.", bundle: Copy.bundle)
    }
    static var openSettings: String { String(localized: "Open Settings", bundle: Copy.bundle) }
    static var assistantAsks: String { String(localized: "The assistant asks", bundle: Copy.bundle) }
    static var adjustComposerPrompt: String { String(localized: "Ask for a change", bundle: Copy.bundle) }
    static var adjustEmptyTitle: String { String(localized: "What should change this week?", bundle: Copy.bundle) }
    /// Requests the empty chat offers to send with one tap.
    static var adjustSuggestions: [String] {
        [
            String(localized: "Vegetarian on Tuesday", bundle: Copy.bundle),
            String(localized: "Dinners under 30 minutes", bundle: Copy.bundle),
            String(localized: "More protein this week", bundle: Copy.bundle),
            String(localized: "No fish this week", bundle: Copy.bundle),
        ]
    }
    static var newChat: String { String(localized: "New chat", bundle: Copy.bundle) }
    static var proposalApplied: String { String(localized: "Applied", bundle: Copy.bundle) }
    static var proposalDismissed: String { String(localized: "Not applied", bundle: Copy.bundle) }
    static var proposalSuperseded: String { String(localized: "Updated below", bundle: Copy.bundle) }
    static var weekReplanned: String { String(localized: "The week is replanned with these changes.", bundle: Copy.bundle) }
    static var seeTheWeek: String { String(localized: "See the week", bundle: Copy.bundle) }

    static var repairTitle: String { String(localized: "Changes for the rest of the week", bundle: Copy.bundle) }
    static var applyRepair: String { String(localized: "Make these changes", bundle: Copy.bundle) }
    static var repairApplied: String { String(localized: "The rest of the week is updated.", bundle: Copy.bundle) }
    static var undo: String { String(localized: "Undo", bundle: Copy.bundle) }

    /// What a repair does to one meal, prefixed by its day; `title` names recipes and `dayName` names days.
    static func describe(_ change: PlanChange, title: (RecipeID) -> String, dayName: (Date) -> String) -> String {
        let dish = title(change.recipeID)
        let text: String
        switch change.action {
        case .moved(let from):
            let earlier = dayName(from)
            text = String(localized: "\(dish), moved from \(earlier)", bundle: Copy.bundle)
        case .replaced(let previous):
            let before = title(previous)
            text = String(localized: "\(dish) instead of \(before)", bundle: Copy.bundle)
        case .removed:
            text = String(localized: "\(dish) comes off the plan", bundle: Copy.bundle)
        }
        return dayNote(day: dayName(change.date), text: text)
    }

    /// Why a repair changes one meal.
    static func reason(for change: PlanChange, lookup: ReasonCopy.Lookup) -> String {
        switch (change.action, change.cause) {
        case (.moved, _):
            String(localized: "Not marked as cooked", bundle: Copy.bundle)
        case (.removed, .skipped):
            String(localized: "The meal it came from was skipped", bundle: Copy.bundle)
        case (.removed, .notCooked):
            String(localized: "Not cooked, and no day is free for it", bundle: Copy.bundle)
        default:
            ReasonCopy.line(for: change.cause, lookup: lookup)
        }
    }

    /// The note under a proposal when some changes were left for Settings.
    static func setAside(_ count: Int) -> String {
        count == 1
            ? String(localized: "One change was left out. Allergies, health, faith and the diets you've set are changed in Settings.", bundle: Copy.bundle)
            : String(localized: "\(count) changes were left out. Allergies, health, faith and the diets you've set are changed in Settings.", bundle: Copy.bundle)
    }

    /// One proposed change in plain words; `dayName` names the day of a change limited to one day.
    static func describe(_ item: WeekAdjustment.Item, dayName: (Int) -> String) -> String {
        switch item {
        case .diet(let pattern, nil):
            let diet = name(of: pattern)
            return String(localized: "\(diet) all week", bundle: Copy.bundle)
        case .diet(let pattern, let offset?):
            let diet = name(of: pattern)
            let weekday = dayName(offset)
            return String(localized: "\(diet) on \(weekday)", bundle: Copy.bundle)
        case .maxMinutes(let minutes, nil):
            return String(localized: "Dinners in \(minutes) minutes or less", bundle: Copy.bundle)
        case .maxMinutes(let minutes, let offset?):
            let weekday = dayName(offset)
            return String(localized: "Dinner on \(weekday) in \(minutes) minutes or less", bundle: Copy.bundle)
        case .avoid(let food):
            return String(localized: "No \(food) this week", bundle: Copy.bundle)
        case .useUp(let food):
            return String(localized: "Use up the \(food)", bundle: Copy.bundle)
        case .goal(let goal):
            return weekGoal(goal)
        }
    }

    private static func weekGoal(_ goal: Goal) -> String {
        switch goal {
        case .eatBetter: String(localized: "Eat a bit better this week", bundle: Copy.bundle)
        case .moreVariety: String(localized: "More variety this week", bundle: Copy.bundle)
        case .lessWaste: String(localized: "Waste less food this week", bundle: Copy.bundle)
        case .saveMoney: String(localized: "Spend less this week", bundle: Copy.bundle)
        case .moreProtein: String(localized: "More protein this week", bundle: Copy.bundle)
        case .maintain: String(localized: "Plan as usual this week", bundle: Copy.bundle)
        }
    }

    /// The notice after an adjusted replan when some days' changes could not be met.
    static func unmetDays(_ dayNames: String) -> String {
        String(localized: "Nothing in your recipes fits the change for \(dayNames), so it keeps its dinner.", bundle: Copy.bundle)
    }

    static func name(of diet: DietPattern) -> String {
        switch diet {
        case .vegetarian: String(localized: "Vegetarian", bundle: Copy.bundle)
        case .vegan: String(localized: "Vegan", bundle: Copy.bundle)
        case .pescatarian: String(localized: "Pescatarian", bundle: Copy.bundle)
        case .mediterranean: String(localized: "Mediterranean", bundle: Copy.bundle)
        case .dash: String(localized: "DASH", bundle: Copy.bundle)
        }
    }

    static func adjustMessage(for error: LarderError) -> String {
        switch error {
        case .notFound:
            String(localized: "Finish setting up your profile, then plan the week.", bundle: Copy.bundle)
        case .storageFailure:
            String(localized: "Couldn't save to this device. Check your storage and try again.", bundle: Copy.bundle)
        case .assistantUnavailable:
            String(localized: "Couldn't reach the assistant. Your plan hasn't changed.", bundle: Copy.bundle)
        case .quotaExceeded:
            String(localized: "This month's assistant allowance is used up. You can still swap any dinner.", bundle: Copy.bundle)
        case .invalidResponse:
            String(localized: "Larder couldn't turn that into a change. Try saying it another way.", bundle: Copy.bundle)
        case .declined:
            String(localized: "The assistant would not make that change.", bundle: Copy.bundle)
        case .consentRequired:
            adjustNeedsConsent
        case .plusRequired:
            String(localized: "Adjusting the week needs Larder Plus.", bundle: Copy.bundle)
        }
    }

    /// A reason under "Why this week?", prefixed by its day.
    static func dayNote(day dayName: String, text: String) -> String {
        String(localized: "\(dayName): \(text)", bundle: Copy.bundle)
    }

    static func useRecipe(_ title: String) -> String {
        String(localized: "Use \(title)", bundle: Copy.bundle)
    }

    /// The question before an idea replaces the dinner already planned for tonight.
    static func replaceTonight(_ planned: String) -> String {
        String(localized: "\(planned) is on for tonight. Cook this instead?", bundle: Copy.bundle)
    }

    static func cookInstead(_ title: String) -> String {
        String(localized: "Cook \(title) instead", bundle: Copy.bundle)
    }

    /// The pill on tonight's dinner when it is a leftover: the weekday the dish was cooked.
    static func leftoversFrom(_ dayName: String) -> String {
        String(localized: "Leftovers from \(dayName)", bundle: Copy.bundle)
    }

    /// The toast after a skip or a move, which offers Undo.
    static func changed(_ undo: MealChangeUndo, dayName: (Date) -> String) -> String {
        let dish = undo.title
        switch undo.kind {
        case .skipped:
            return String(localized: "\(dish) skipped", bundle: Copy.bundle)
        case .moved(let date, nil):
            let weekday = dayName(date)
            return String(localized: "\(dish) moved to \(weekday)", bundle: Copy.bundle)
        case .moved(let date, let other?):
            let weekday = dayName(date)
            return String(localized: "\(dish) moved to \(weekday). \(other) takes its place.", bundle: Copy.bundle)
        }
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
            String(localized: "AI help is off. The reasons are under each meal.", bundle: Copy.bundle)
        case .plusRequired:
            String(localized: "That needs Larder Plus.", bundle: Copy.bundle)
        }
    }
}
