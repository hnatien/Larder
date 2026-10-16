import Foundation
import LarderCore

/// Words used by the recipes screens that the shared design copy does not cover.
nonisolated enum RecipesCopy {
    static var searchPrompt: String { String(localized: "Search recipes") }
    static var importRecipe: String { String(localized: "Import a recipe") }
    static var loading: String { String(localized: "Loading recipes") }
    static var clearFilters: String { String(localized: "Clear filters") }
    static var quickFilter: String { String(localized: "30 min or less") }

    static var emptyLibraryTitle: String { String(localized: "No recipes yet") }
    static var emptyLibraryMessage: String {
        String(localized: "Import one from a web page and it will wait here, ready to cook.")
    }
    static var noResultsTitle: String { String(localized: "No matches") }
    static var noResultsMessage: String {
        String(localized: "Nothing fits those words and filters. Clear a filter or try another word.")
    }

    static func resultCount(_ count: Int) -> String {
        String(localized: "\(count) recipes")
    }

    static func name(of mealType: MealType) -> String {
        switch mealType {
        case .breakfast: String(localized: "Breakfast")
        case .lunch: String(localized: "Lunch")
        case .dinner: String(localized: "Dinner")
        case .snack: String(localized: "Snack")
        }
    }

    static func name(of diet: DietPattern) -> String {
        switch diet {
        case .vegetarian: String(localized: "Vegetarian")
        case .vegan: String(localized: "Vegan")
        case .pescatarian: String(localized: "Pescatarian")
        case .mediterranean: String(localized: "Mediterranean")
        case .dash: String(localized: "DASH")
        }
    }

    static func message(for error: RecipesError) -> String {
        switch error {
        case .loadFailed: String(localized: "Couldn't read your recipes. Pull down to try again.")
        case .saveFailed: String(localized: "Couldn't save that recipe. Try again.")
        case .deleteFailed: String(localized: "Couldn't delete that recipe. Try again.")
        case .notDeletable: String(localized: "Only recipes you imported can be deleted.")
        }
    }

    static var ok: String { String(localized: "OK") }

    static var servings: String { String(localized: "Servings") }
    static func spokenServings(_ count: Int) -> String {
        String(localized: "\(count) servings")
    }
    static func servingsStamp(_ count: Int) -> String {
        String(localized: "Serves \(count)")
    }
    static var ingredients: String { String(localized: "Ingredients") }
    static var method: String { String(localized: "Method") }
    static var optional: String { String(localized: "optional") }
    static var startCooking: String { String(localized: "Start cooking") }
    static var addToLedger: String { String(localized: "Add to Ledger") }
    static var deleteRecipe: String { String(localized: "Delete recipe") }
    static var deleteQuestion: String { String(localized: "Delete this recipe?") }
    static var deleteMessage: String { String(localized: "It will be removed from this device.") }
    static func source(_ host: String) -> String {
        String(localized: "From \(host)")
    }
    static var detailFailed: String { String(localized: "Couldn't read this recipe. Try again.") }
    static var retry: String { String(localized: "Try again") }

    static var excludedTitle: String { String(localized: "Excluded for you") }
    static var uncertainTitle: String { String(localized: "Not sure about this one") }

    static var perServing: String { String(localized: "Per serving") }
    static var energy: String { String(localized: "Energy") }
    static var protein: String { String(localized: "Protein") }
    static var fibre: String { String(localized: "Fibre") }
    static var sodium: String { String(localized: "Sodium") }
    static var partialNutrition: String {
        String(localized: "Counts only the ingredients Larder recognises.")
    }

    static func stepPosition(_ number: Int, of count: Int) -> String {
        String(localized: "Step \(number) of \(count)")
    }
    static func stepTimerName(_ number: Int) -> String {
        String(localized: "Step \(number) timer")
    }
    static var back: String { String(localized: "Back") }
    static var next: String { String(localized: "Next") }
    static var finish: String { String(localized: "Finish") }
    static var close: String { String(localized: "Close") }
    static var noSteps: String { String(localized: "This recipe has no steps to follow.") }
    static var stepsRotor: String { String(localized: "Steps") }
    static var start: String { String(localized: "Start") }
    static var pause: String { String(localized: "Pause") }
    static var resume: String { String(localized: "Resume") }
    static var reset: String { String(localized: "Reset") }
    static var timerDone: String { String(localized: "Timer done") }
    static var timerPaused: String { String(localized: "Paused") }

    static var importTitle: String { String(localized: "Import a recipe") }
    static var address: String { String(localized: "Web address") }
    static var readPage: String { String(localized: "Read the page") }
    static var readingPage: String { String(localized: "Reading the page") }
    static var save: String { String(localized: "Save recipe") }
    static var startOver: String { String(localized: "Start over") }
    static var cancel: String { String(localized: "Cancel") }
    static var assistantNote: String {
        String(localized: "The assistant read this page. Check the amounts before you cook.")
    }
    static func found(_ title: String) -> String {
        String(localized: "Found \(title)")
    }

    static func message(for error: ImportError) -> String {
        switch error {
        case .invalidURL:
            String(localized: "That does not look like a web address. Check it and try again.")
        case .fetchFailed:
            String(localized: "Couldn't load that page. Check the address and your connection.")
        case .notAWebPage:
            String(localized: "That address is not a web page Larder can read.")
        case .noStructuredRecipe:
            String(localized: "This page has no recipe Larder can read on its own. You can paste the recipe in yourself, or Larder Plus can read pages without structured data.")
        case .saveFailed:
            String(localized: "Couldn't save that recipe. Try again.")
        case .assistantFailed(.plusRequired):
            String(localized: "Reading this page needs Larder Plus.")
        case .assistantFailed(.consentRequired):
            String(localized: "Allow AI processing before the assistant reads a page.")
        case .assistantFailed(.declined):
            String(localized: "The assistant would not read this page.")
        case .assistantFailed:
            String(localized: "The assistant couldn't read this page. Try again later.")
        }
    }
}
