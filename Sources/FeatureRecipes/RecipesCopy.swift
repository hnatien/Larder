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
        case .notDeletable: String(localized: "Only recipes you imported can be deleted. You can hide this one instead.", bundle: Copy.bundle)
        case .markFailed: String(localized: "Couldn't save that change. Try again.", bundle: Copy.bundle)
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
    static var shown: String { String(localized: "Shown", bundle: Copy.bundle) }
    static var hidden: String { String(localized: "Hidden", bundle: Copy.bundle) }
    static var writeItTitle: String { String(localized: "Write it yourself", bundle: Copy.bundle) }
    static var writeItHint: String {
        String(localized: "Type or paste it: one ingredient per line, one step per line. Free and stays on this iPhone.", bundle: Copy.bundle)
    }
    static var recipeTitle: String { String(localized: "Recipe name", bundle: Copy.bundle) }
    static var ingredientLines: String { String(localized: "Ingredients, one per line", bundle: Copy.bundle) }
    static var stepLines: String { String(localized: "Method, one step per line", bundle: Copy.bundle) }
    static var totalMinutes: String { String(localized: "Minutes in total", bundle: Copy.bundle) }
    static var previewWritten: String { String(localized: "Preview recipe", bundle: Copy.bundle) }
    static var showAllSteps: String { String(localized: "Show every step", bundle: Copy.bundle) }
    static var writtenNote: String { String(localized: "Written by you. Check the amounts before saving.", bundle: Copy.bundle) }

    static var favourites: String { String(localized: "Favourites", bundle: Copy.bundle) }
    static var moreFilters: String { String(localized: "Filters", bundle: Copy.bundle) }
    static var filtersTitle: String { String(localized: "Filters", bundle: Copy.bundle) }
    static var mealFilter: String { String(localized: "Meal", bundle: Copy.bundle) }
    static var dietFilter: String { String(localized: "Diet", bundle: Copy.bundle) }
    static var timeFilter: String { String(localized: "Time", bundle: Copy.bundle) }
    static var sortTitle: String { String(localized: "Sort", bundle: Copy.bundle) }
    static var hiddenTitle: String { String(localized: "Hidden recipes", bundle: Copy.bundle) }
    static var showAgain: String { String(localized: "Show again", bundle: Copy.bundle) }
    static var hiddenEmpty: String { String(localized: "Nothing is hidden.", bundle: Copy.bundle) }
    static var hiddenHint: String {
        String(localized: "Hidden recipes stay out of the library and out of your plans.", bundle: Copy.bundle)
    }

    static func showAgainNamed(_ title: String) -> String {
        String(localized: "Show \(title) again", bundle: Copy.bundle)
    }

    /// The Filters chip with how many filters in the sheet are on.
    static func moreFilters(_ count: Int) -> String {
        String(localized: "Filters, \(count) on", bundle: Copy.bundle)
    }

    /// A time filter: any time, or at most so many minutes.
    static func timeLimit(_ minutes: Int?) -> String {
        guard let minutes else { return String(localized: "Any time", bundle: Copy.bundle) }
        return String(localized: "\(minutes) min or less", bundle: Copy.bundle)
    }

    /// The button that closes Filters, with how many recipes match.
    static func showResults(_ count: Int) -> String {
        count == 1
            ? String(localized: "Show 1 recipe", bundle: Copy.bundle)
            : String(localized: "Show \(count) recipes", bundle: Copy.bundle)
    }

    static func name(of sort: RecipeSort) -> String {
        switch sort {
        case .name: String(localized: "Name", bundle: Copy.bundle)
        case .quickest: String(localized: "Quickest first", bundle: Copy.bundle)
        case .mostInPantry: String(localized: "Most in your pantry", bundle: Copy.bundle)
        }
    }

    /// "You have 6 of 8" under a library row.
    static func youHave(_ coverage: PantryCoverage) -> String {
        let count = coverage.have
        let total = coverage.total
        return String(localized: "You have \(count) of \(total)", bundle: Copy.bundle)
    }

    static var favourite: String { String(localized: "Add to favourites", bundle: Copy.bundle) }
    static var unfavourite: String { String(localized: "Remove from favourites", bundle: Copy.bundle) }
    static var hideRecipe: String { String(localized: "Hide recipe", bundle: Copy.bundle) }
    static var inYourPantry: String { String(localized: "In your pantry", bundle: Copy.bundle) }
    static var toBuy: String { String(localized: "To buy", bundle: Copy.bundle) }
    static var fitsYourSettings: String { String(localized: "Fits your allergies and diet.", bundle: Copy.bundle) }
    static var couldNotAddToGroceries: String {
        String(localized: "Couldn't add those to Groceries. Try again.", bundle: Copy.bundle)
    }

    static func optionalLine(_ text: String) -> String {
        String(localized: "\(text) (optional)", bundle: Copy.bundle)
    }

    /// The button that puts what the pantry lacks on the grocery list.
    static func addMissing(_ count: Int) -> String {
        count == 1
            ? String(localized: "Add 1 missing item to Groceries", bundle: Copy.bundle)
            : String(localized: "Add \(count) missing items to Groceries", bundle: Copy.bundle)
    }

    static func addedToGroceries(_ count: Int) -> String {
        count == 1
            ? String(localized: "Added 1 item to Groceries", bundle: Copy.bundle)
            : String(localized: "Added \(count) items to Groceries", bundle: Copy.bundle)
    }

    /// Under a day in Add to plan that already has a dinner.
    static func replaces(_ title: String) -> String {
        String(localized: "Replaces \(title)", bundle: Copy.bundle)
    }

    static var stopCookingQuestion: String { String(localized: "Stop cooking?", bundle: Copy.bundle) }
    static var stopCookingMessage: String { String(localized: "Your timers stop when you leave.", bundle: Copy.bundle) }
    static var stopCooking: String { String(localized: "Stop cooking", bundle: Copy.bundle) }
    static var keepCooking: String { String(localized: "Keep cooking", bundle: Copy.bundle) }
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
    /// The body of the notification for a timer that ended in the background.
    static func timerEnded(step: Int) -> String {
        String(localized: "Step \(step) timer is done.", bundle: Copy.bundle)
    }
    static var timerNotificationsTitle: String { String(localized: "Timer notifications", bundle: Copy.bundle) }
    /// The one reason given before the system asks to allow notifications.
    static var timerNotificationsReason: String {
        String(localized: "Larder can tell you when a timer ends while you are in another app.", bundle: Copy.bundle)
    }
    static var continueAction: String { String(localized: "Continue", bundle: Copy.bundle) }
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
    static var assistantNote: String {
        String(localized: "The assistant read this page. Check the amounts before you cook.", bundle: Copy.bundle)
    }
    static var fromPhoto: String { String(localized: "From a photo", bundle: Copy.bundle) }
    static var fromPhotoHint: String {
        String(localized: "A recipe card or a cookbook page. Larder reads it on this iPhone when it can.", bundle: Copy.bundle)
    }
    static var takePhoto: String { String(localized: "Take a photo", bundle: Copy.bundle) }
    static var choosePhoto: String { String(localized: "Choose a photo", bundle: Copy.bundle) }
    static var readingPhoto: String { String(localized: "Reading the photo", bundle: Copy.bundle) }
    static var fromAddress: String { String(localized: "From a web page", bundle: Copy.bundle) }
    static var photoNote: String {
        String(localized: "Read from your photo. Check the amounts before you cook.", bundle: Copy.bundle)
    }
    static func found(_ title: String) -> String {
        String(localized: "Found \(title)", bundle: Copy.bundle)
    }
    static func numberedStep(_ number: Int, text: String) -> String {
        String(localized: "\(number). \(text)", bundle: Copy.bundle)
    }

    static func message(for error: ImportError) -> String {
        switch error {
        case .noWrittenRecipe:
            String(localized: "Give the recipe a title and at least one ingredient or step.", bundle: Copy.bundle)
        case .invalidURL:
            String(localized: "That does not look like a web address. Check it and try again.", bundle: Copy.bundle)
        case .fetchFailed:
            String(localized: "Couldn't load that page. Check the address and your connection.", bundle: Copy.bundle)
        case .notAWebPage:
            String(localized: "That address is not a web page Larder can read.", bundle: Copy.bundle)
        case .noStructuredRecipe:
            String(localized: "This page has no recipe Larder can read on its own. Write it out below, or with Larder Plus the assistant can read pages like this one.", bundle: Copy.bundle)
        case .saveFailed:
            String(localized: "Couldn't save that recipe. Try again.", bundle: Copy.bundle)
        case .assistantFailed(.plusRequired):
            String(localized: "Reading this page needs Larder Plus.", bundle: Copy.bundle)
        case .assistantFailed(.consentRequired):
            String(localized: "Reading this page needs AI help, which is off.", bundle: Copy.bundle)
        case .assistantFailed(.declined):
            String(localized: "The assistant would not read this page.", bundle: Copy.bundle)
        case .assistantFailed:
            String(localized: "The assistant couldn't read this page. Try again later.", bundle: Copy.bundle)
        case .photoNeedsPlus:
            String(localized: "Reading a recipe from a photo needs Larder Plus.", bundle: Copy.bundle)
        case .unreadablePhoto:
            String(localized: "Couldn't find a recipe in that photo. Try a sharper photo of the whole page.", bundle: Copy.bundle)
        case .photoAssistantFailed(.consentRequired):
            String(localized: "This iPhone couldn't read the photo on its own. With AI help on, the assistant can read it.", bundle: Copy.bundle)
        case .photoAssistantFailed(.declined):
            String(localized: "The assistant would not read this photo.", bundle: Copy.bundle)
        case .photoAssistantFailed(.quotaExceeded):
            String(localized: "This month's assistant allowance is used up. Try again next month or import from a web address.", bundle: Copy.bundle)
        case .photoAssistantFailed:
            String(localized: "The assistant couldn't read this photo. Try again later.", bundle: Copy.bundle)
        }
    }
}
