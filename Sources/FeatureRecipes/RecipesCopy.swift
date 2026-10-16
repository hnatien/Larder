import Foundation
import LarderCore
import LarderDesign

/// Words used by the recipes screens that the shared design copy does not cover.
nonisolated enum RecipesCopy {
    static var searchPrompt: String { String(localized: "Search recipes", bundle: Copy.bundle) }
    static var subtitle: String { String(localized: "Cook from the library or import your own", bundle: Copy.bundle) }
    static var importRecipe: String { String(localized: "Import a recipe", bundle: Copy.bundle) }
    static var loading: String { String(localized: "Loading recipes", bundle: Copy.bundle) }
    static var clearFilters: String { String(localized: "Clear filters", bundle: Copy.bundle) }
    static var quickFilter: String { String(localized: "30 min or less", bundle: Copy.bundle) }
    static var cuisine: String { String(localized: "Cuisine", bundle: Copy.bundle) }
    static var anyCuisine: String { String(localized: "Any cuisine", bundle: Copy.bundle) }
    static var addToPlan: String { String(localized: "Add to plan", bundle: Copy.bundle) }
    static var addToPlanQuestion: String { String(localized: "Which day?", bundle: Copy.bundle) }
    static func addedTo(_ day: String) -> String { String(localized: "Added to \(day)", bundle: Copy.bundle) }
    static var couldNotAdd: String { String(localized: "Couldn't add that to the plan. Try again.", bundle: Copy.bundle) }
    static var more: String { String(localized: "More", bundle: Copy.bundle) }
    static var ingredientsHint: String { String(localized: "Tap an ingredient to tick it off.", bundle: Copy.bundle) }
    static var today: String { String(localized: "Today", bundle: Copy.bundle) }
    static var tomorrow: String { String(localized: "Tomorrow", bundle: Copy.bundle) }

    static var emptyLibraryTitle: String { String(localized: "No recipes yet", bundle: Copy.bundle) }
    static var emptyLibraryMessage: String {
        String(localized: "Import one from a web page with the + button and it will wait here, ready to cook.", bundle: Copy.bundle)
    }
    static var noResultsTitle: String { String(localized: "No matches", bundle: Copy.bundle) }
    static var noResultsMessage: String {
        String(localized: "Nothing fits those words and filters. Clear a filter or try another word.", bundle: Copy.bundle)
    }

    static func resultCount(_ count: Int) -> String {
        String(localized: "\(count) recipes", bundle: Copy.bundle)
    }

    static func name(of mealType: MealType) -> String {
        switch mealType {
        case .breakfast: String(localized: "Breakfast", bundle: Copy.bundle)
        case .lunch: String(localized: "Lunch", bundle: Copy.bundle)
        case .dinner: String(localized: "Dinner", bundle: Copy.bundle)
        case .snack: String(localized: "Snack", bundle: Copy.bundle)
        }
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

    static func message(for error: RecipesError) -> String {
        switch error {
        case .loadFailed: String(localized: "Couldn't read your recipes. Pull down to try again.", bundle: Copy.bundle)
        case .saveFailed: String(localized: "Couldn't save that recipe. Try again.", bundle: Copy.bundle)
        case .deleteFailed: String(localized: "Couldn't delete that recipe. Try again.", bundle: Copy.bundle)
        case .notDeletable: String(localized: "Only recipes you imported can be deleted.", bundle: Copy.bundle)
        }
    }

    static var ok: String { String(localized: "OK", bundle: Copy.bundle) }

    static var servings: String { String(localized: "Servings", bundle: Copy.bundle) }
    static func spokenServings(_ count: Int) -> String {
        String(localized: "\(count) servings", bundle: Copy.bundle)
    }
    static func servingsStamp(_ count: Int) -> String {
        String(localized: "Serves \(count)", bundle: Copy.bundle)
    }
    static var ingredients: String { String(localized: "Ingredients", bundle: Copy.bundle) }
    static var method: String { String(localized: "Method", bundle: Copy.bundle) }
    static var optional: String { String(localized: "optional", bundle: Copy.bundle) }
    static var startCooking: String { String(localized: "Start cooking", bundle: Copy.bundle) }
    static var deleteRecipe: String { String(localized: "Delete recipe", bundle: Copy.bundle) }
    static var deleteQuestion: String { String(localized: "Delete this recipe?", bundle: Copy.bundle) }
    static var deleteMessage: String { String(localized: "It will be removed from this device.", bundle: Copy.bundle) }
    static func source(_ host: String) -> String {
        String(localized: "From \(host)", bundle: Copy.bundle)
    }
    static var detailFailed: String { String(localized: "Couldn't read this recipe. Try again.", bundle: Copy.bundle) }
    static var retry: String { String(localized: "Try again", bundle: Copy.bundle) }

    static var excludedTitle: String { String(localized: "Excluded for you", bundle: Copy.bundle) }
    static var uncertainTitle: String { String(localized: "Not sure about this one", bundle: Copy.bundle) }

    static var perServing: String { String(localized: "Per serving", bundle: Copy.bundle) }
    static var energy: String { String(localized: "Energy", bundle: Copy.bundle) }
    static var protein: String { String(localized: "Protein", bundle: Copy.bundle) }
    static var fibre: String { String(localized: "Fibre", bundle: Copy.bundle) }
    static var sodium: String { String(localized: "Sodium", bundle: Copy.bundle) }
    static var partialNutrition: String {
        String(localized: "Counts only the ingredients Larder recognises.", bundle: Copy.bundle)
    }

    static func stepPosition(_ number: Int, of count: Int) -> String {
        String(localized: "Step \(number) of \(count)", bundle: Copy.bundle)
    }
    static func stepTimerName(_ number: Int) -> String {
        String(localized: "Step \(number) timer", bundle: Copy.bundle)
    }
    static var back: String { String(localized: "Back", bundle: Copy.bundle) }
    static var next: String { String(localized: "Next", bundle: Copy.bundle) }
    static var finish: String { String(localized: "Finish", bundle: Copy.bundle) }
    static var close: String { String(localized: "Close", bundle: Copy.bundle) }
    static var done: String { String(localized: "Done", bundle: Copy.bundle) }
    static var noSteps: String { String(localized: "This recipe has no steps to follow.", bundle: Copy.bundle) }
    static var stepsRotor: String { String(localized: "Steps", bundle: Copy.bundle) }
    static var start: String { String(localized: "Start", bundle: Copy.bundle) }
    static var pause: String { String(localized: "Pause", bundle: Copy.bundle) }
    static var resume: String { String(localized: "Resume", bundle: Copy.bundle) }
    static var reset: String { String(localized: "Reset", bundle: Copy.bundle) }
    static var timerDone: String { String(localized: "Timer done", bundle: Copy.bundle) }
    static var timerPaused: String { String(localized: "Paused", bundle: Copy.bundle) }
    /// A timer button's spoken name, such as "Start Step 2 timer".
    static func timerAction(_ action: String, name: String) -> String {
        String(localized: "\(action) \(name)", bundle: Copy.bundle)
    }

    static var importTitle: String { String(localized: "Import a recipe", bundle: Copy.bundle) }
    static var address: String { String(localized: "Web address", bundle: Copy.bundle) }
    static var readPage: String { String(localized: "Read the page", bundle: Copy.bundle) }
    static var readingPage: String { String(localized: "Reading the page", bundle: Copy.bundle) }
    static var save: String { String(localized: "Save recipe", bundle: Copy.bundle) }
    static var startOver: String { String(localized: "Start over", bundle: Copy.bundle) }
    static var cancel: String { String(localized: "Cancel", bundle: Copy.bundle) }
    static var assistantNote: String {
        String(localized: "The assistant read this page. Check the amounts before you cook.", bundle: Copy.bundle)
    }
    static func found(_ title: String) -> String {
        String(localized: "Found \(title)", bundle: Copy.bundle)
    }
    static func numberedStep(_ number: Int, text: String) -> String {
        String(localized: "\(number). \(text)", bundle: Copy.bundle)
    }

    static func message(for error: ImportError) -> String {
        switch error {
        case .invalidURL:
            String(localized: "That does not look like a web address. Check it and try again.", bundle: Copy.bundle)
        case .fetchFailed:
            String(localized: "Couldn't load that page. Check the address and your connection.", bundle: Copy.bundle)
        case .notAWebPage:
            String(localized: "That address is not a web page Larder can read.", bundle: Copy.bundle)
        case .noStructuredRecipe:
            String(localized: "This page has no recipe Larder can read on its own. With Larder Plus, the assistant can read pages like this one.", bundle: Copy.bundle)
        case .saveFailed:
            String(localized: "Couldn't save that recipe. Try again.", bundle: Copy.bundle)
        case .assistantFailed(.plusRequired):
            String(localized: "Reading this page needs Larder Plus.", bundle: Copy.bundle)
        case .assistantFailed(.consentRequired):
            String(localized: "Turn on AI help in Settings before the assistant reads a page.", bundle: Copy.bundle)
        case .assistantFailed(.declined):
            String(localized: "The assistant would not read this page.", bundle: Copy.bundle)
        case .assistantFailed:
            String(localized: "The assistant couldn't read this page. Try again later.", bundle: Copy.bundle)
        }
    }
}
