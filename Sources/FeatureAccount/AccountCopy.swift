import Foundation
import LarderCore
import LarderDesign

/// User-facing strings for onboarding, the paywall and settings. Dry, plain, no exclamation marks.
nonisolated enum AccountCopy {
    static var back: String { String(localized: "Back", bundle: Copy.bundle) }
    static var next: String { String(localized: "Next", bundle: Copy.bundle) }
    static var finish: String { String(localized: "Finish", bundle: Copy.bundle) }
    static var skip: String { String(localized: "Skip", bundle: Copy.bundle) }
    static var preferNotToSay: String { String(localized: "Prefer not to say", bundle: Copy.bundle) }
    static var cancel: String { String(localized: "Cancel", bundle: Copy.bundle) }
    static var tryAgain: String { String(localized: "Try again", bundle: Copy.bundle) }

    static func showAll(_ count: Int) -> String { String(localized: "Show all \(count)", bundle: Copy.bundle) }
    static func showFewer() -> String { String(localized: "Show fewer", bundle: Copy.bundle) }
    static func progress(step: Int, of total: Int) -> String { String(localized: "\(step) of \(total)", bundle: Copy.bundle) }
    static func spokenProgress(step: Int, of total: Int) -> String { String(localized: "Step \(step) of \(total)", bundle: Copy.bundle) }
    static func remove(_ name: String) -> String { String(localized: "Remove \(name)", bundle: Copy.bundle) }

    /// Onboarding questions and explanations.
    enum Onboarding {
        static var welcomeTitle: String { String(localized: "Welcome to Larder", bundle: Copy.bundle) }
        static var welcomeLines: [String] {
            [
                String(localized: "Larder plans meals around what is already on your shelves.", bundle: Copy.bundle),
                String(localized: "It writes the grocery list and moves what you buy onto the shelves.", bundle: Copy.bundle),
                String(localized: "It keeps what you can't eat out of every plan.", bundle: Copy.bundle),
            ]
        }
        static var consentLabel: String { String(localized: "Allow AI help", bundle: Copy.bundle) }
        static var consentExplanation: String {
            String(
                localized: "When this is on, Larder sends recipe text and plain settings such as cook time and diet type to its server and the AI model behind it, to explain plans and answer requests. Medical and religious details never leave this device. It stays off unless you turn it on.",
                bundle: Copy.bundle
            )
        }
        static var leaveOutTitle: String { String(localized: "What should we always leave out?", bundle: Copy.bundle) }
        static var intoleranceLabel: String { String(localized: "Anything else to leave out", bundle: Copy.bundle) }
        static var intolerancePrompt: String { String(localized: "For example lactose, separated by commas", bundle: Copy.bundle) }
        static var eatByTitle: String { String(localized: "Anything we eat by?", bundle: Copy.bundle) }
        static var carefulTitle: String { String(localized: "Anything we should be careful with?", bundle: Copy.bundle) }
        static var goalTitle: String { String(localized: "What matters most?", bundle: Copy.bundle) }
        static var householdTitle: String { String(localized: "Who's eating?", bundle: Copy.bundle) }
        static func household(_ count: Int) -> String { String(localized: "\(count) at the table", bundle: Copy.bundle) }
        static var cookTimeLabel: String { String(localized: "Longest time to cook on a weeknight", bundle: Copy.bundle) }
        static var birthYearLabel: String { String(localized: "Year you were born", bundle: Copy.bundle) }
        static var birthYearExplanation: String {
            String(localized: "Used only for nutrient ranges on this device.", bundle: Copy.bundle)
        }
        static var equipmentTitle: String { String(localized: "What do you cook with?", bundle: Copy.bundle) }
        static var easierTitle: String { String(localized: "Make Larder easier to use", bundle: Copy.bundle) }
        static var largerTextLabel: String { String(localized: "Larger text", bundle: Copy.bundle) }
        static var largerTextHint: String {
            String(localized: "Larder follows the text size set in Settings, under Accessibility, Display and Text Size.", bundle: Copy.bundle)
        }
        static var simpleLayoutLabel: String { String(localized: "Simpler layout", bundle: Copy.bundle) }
        static var simpleLayoutHint: String { String(localized: "Fewer choices on each screen.", bundle: Copy.bundle) }
        static var timersLabel: String { String(localized: "Timers flash and vibrate", bundle: Copy.bundle) }
        static var timersHint: String { String(localized: "Every timer sound also flashes the screen and vibrates.", bundle: Copy.bundle) }
        static var saveFailed: String { String(localized: "Couldn't save your answers. Try again.", bundle: Copy.bundle) }
    }

    /// The "Show numbers" switch, shared by onboarding and settings.
    enum Numbers {
        static var label: String { String(localized: "Show numbers", bundle: Copy.bundle) }
        static var hint: String {
            String(localized: "Calories and nutrient amounts stay hidden unless this is on. Shelf balance uses words either way.", bundle: Copy.bundle)
        }
    }

    /// The paywall.
    enum Paywall {
        static var features: [String] {
            [
                String(localized: "Plan my week fills the whole week and replans when things change, with a reason for each meal.", bundle: Copy.bundle),
                String(localized: "Household profiles give each person their own swaps on one shared plate.", bundle: Copy.bundle),
                String(localized: "Leftovers and batch cooking are scheduled for you.", bundle: Copy.bundle),
                String(localized: "Shelf balance shows each food group across the week, with numbers only if you want them.", bundle: Copy.bundle),
                String(localized: "Photos and receipts update the shelves.", bundle: Copy.bundle),
                String(localized: "The assistant takes requests such as a vegetarian Tuesday under 30 minutes.", bundle: Copy.bundle),
            ]
        }
        static var staysFree: String {
            String(localized: "Allergen filters, recipes, shelves, grocery lists and export stay free.", bundle: Copy.bundle)
        }
        static var renews: String {
            String(localized: "Subscriptions renew automatically until cancelled in your App Store account settings.", bundle: Copy.bundle)
        }
        static var terms: String { String(localized: "Terms of use", bundle: Copy.bundle) }
        static var privacy: String { String(localized: "Privacy policy", bundle: Copy.bundle) }
        static var pending: String { String(localized: "Waiting for approval. Plus starts once the purchase is approved.", bundle: Copy.bundle) }

        static func price(_ product: StoreProduct) -> String {
            let price = product.displayPrice
            guard let period = product.period else { return price }
            let count = period.value
            let unit = unitName(period.unit, value: count)
            let renewal = switch (period.unit, count) {
            case (.day, 1): String(localized: "\(price) a day", bundle: Copy.bundle)
            case (.week, 1): String(localized: "\(price) a week", bundle: Copy.bundle)
            case (.month, 1): String(localized: "\(price) a month", bundle: Copy.bundle)
            case (.year, 1): String(localized: "\(price) a year", bundle: Copy.bundle)
            default: String(localized: "\(price) every \(count) \(unit)", bundle: Copy.bundle)
            }
            guard let trial = product.freeTrial else { return renewal }
            return freeTrial(count: trial.value, unit: unitName(trial.unit, value: trial.value), then: renewal)
        }

        private static func freeTrial(count: Int, unit: String, then renewal: String) -> String {
            String(localized: "\(count) \(unit) free, then \(renewal)", bundle: Copy.bundle)
        }

        private static func unitName(_ unit: BillingPeriod.Unit, value: Int) -> String {
            switch unit {
            case .day: value == 1 ? String(localized: "day", bundle: Copy.bundle) : String(localized: "days", bundle: Copy.bundle)
            case .week: value == 1 ? String(localized: "week", bundle: Copy.bundle) : String(localized: "weeks", bundle: Copy.bundle)
            case .month: value == 1 ? String(localized: "month", bundle: Copy.bundle) : String(localized: "months", bundle: Copy.bundle)
            case .year: value == 1 ? String(localized: "year", bundle: Copy.bundle) : String(localized: "years", bundle: Copy.bundle)
            }
        }
    }

    /// Store failures.
    static func message(for error: EntitlementError) -> String {
        switch error {
        case .productsUnavailable: String(localized: "Couldn't load prices. Check the connection and try again.", bundle: Copy.bundle)
        case .purchaseFailed: String(localized: "The purchase didn't go through. Try again in a moment.", bundle: Copy.bundle)
        case .verificationFailed: String(localized: "The App Store couldn't confirm this purchase. Try Restore purchases.", bundle: Copy.bundle)
        case .restoreFailed: String(localized: "Couldn't restore purchases. Try again in a moment.", bundle: Copy.bundle)
        }
    }

    /// Settings.
    enum Settings {
        static var title: String { String(localized: "Settings", bundle: Copy.bundle) }
        static var profile: String { String(localized: "Profile", bundle: Copy.bundle) }
        static var goal: String { String(localized: "What matters most", bundle: Copy.bundle) }
        static var equipment: String { String(localized: "Equipment", bundle: Copy.bundle) }
        static var leaveOut: String { String(localized: "What we leave out", bundle: Copy.bundle) }
        static var nothingLeftOut: String { String(localized: "Nothing yet.", bundle: Copy.bundle) }
        static var add: String { String(localized: "Add", bundle: Copy.bundle) }
        static var removeShort: String { String(localized: "Remove", bundle: Copy.bundle) }
        static var addIntolerance: String { String(localized: "Add something else to leave out", bundle: Copy.bundle) }
        static var addDislike: String { String(localized: "Add a food you'd rather skip", bundle: Copy.bundle) }
        static func removeTitle(_ name: String) -> String { String(localized: "Stop leaving out \(name)?", bundle: Copy.bundle) }
        static var removeMessage: String { String(localized: "Plans will be able to include it again.", bundle: Copy.bundle) }
        static var removeConfirm: String { String(localized: "Stop leaving it out", bundle: Copy.bundle) }
        static var keep: String { String(localized: "Keep it", bundle: Copy.bundle) }
        static var plus: String { String(localized: "Larder Plus", bundle: Copy.bundle) }
        static func plusUntil(_ date: String) -> String { String(localized: "Plus until \(date)", bundle: Copy.bundle) }
        static var plusActive: String { String(localized: "Plus", bundle: Copy.bundle) }
        static var free: String { String(localized: "Free", bundle: Copy.bundle) }
        static var manage: String { String(localized: "Manage subscription", bundle: Copy.bundle) }
        static var seePlus: String { String(localized: "See Larder Plus", bundle: Copy.bundle) }
        static var data: String { String(localized: "Data", bundle: Copy.bundle) }
        static var export: String { String(localized: "Export everything", bundle: Copy.bundle) }
        static var exportHint: String {
            String(localized: "A JSON file with your profile, what we leave out, targets, recipes, shelves and plans.", bundle: Copy.bundle)
        }
        static var exportName: String { String(localized: "Larder export", bundle: Copy.bundle) }
        static var delete: String { String(localized: "Delete all data", bundle: Copy.bundle) }
        static var deleteTitle: String { String(localized: "Delete everything on this device?", bundle: Copy.bundle) }
        static var deleteMessage: String {
            String(localized: "Your profile, recipes, shelves and plans are removed and can't be recovered. A subscription is managed by the App Store and is not cancelled.", bundle: Copy.bundle)
        }
        static var deleteConfirm: String { String(localized: "Delete everything", bundle: Copy.bundle) }
        static var about: String { String(localized: "About", bundle: Copy.bundle) }
        static func version(_ version: String) -> String { String(localized: "Version \(version)", bundle: Copy.bundle) }
        static var grdbLicence: String { String(localized: "GRDB, MIT License", bundle: Copy.bundle) }
        static var fontLicence: String { String(localized: "Fraunces and Commit Mono, SIL Open Font License", bundle: Copy.bundle) }
        static var usdaAttribution: String { String(localized: "Contains data from USDA FoodData Central.", bundle: Copy.bundle) }
    }

    /// Settings failures.
    static func message(for error: SettingsError) -> String {
        switch error {
        case .loadFailed: String(localized: "Couldn't load your settings. Try again.", bundle: Copy.bundle)
        case .saveFailed: String(localized: "Couldn't save that change. Try again.", bundle: Copy.bundle)
        case .deleteFailed: String(localized: "Couldn't delete your data. Try again.", bundle: Copy.bundle)
        }
    }

    /// Headings for the constraint axes the user can edit.
    static func name(of axis: ConstraintAxis) -> String {
        switch axis {
        case .medical: String(localized: "Allergies and health", bundle: Copy.bundle)
        case .religious: String(localized: "Faith", bundle: Copy.bundle)
        case .ethical: String(localized: "Diet", bundle: Copy.bundle)
        case .preference: String(localized: "Dislikes", bundle: Copy.bundle)
        case .goal: String(localized: "Goals", bundle: Copy.bundle)
        }
    }

    static func name(of kind: ConstraintKind) -> String {
        switch kind {
        case .allergen(let allergen): name(of: allergen)
        case .intolerance(let text): text
        case .diet(let diet): name(of: diet)
        case .medical(let flag): name(of: flag)
        case .religious(let rule): name(of: rule)
        case .dislike(.name(let text)): text
        case .dislike(.food): String(localized: "A food you dislike", bundle: Copy.bundle)
        }
    }

    static func name(of allergen: Allergen) -> String {
        switch allergen {
        case .milk: String(localized: "Milk", bundle: Copy.bundle)
        case .egg: String(localized: "Eggs", bundle: Copy.bundle)
        case .fish: String(localized: "Fish", bundle: Copy.bundle)
        case .crustacean: String(localized: "Shellfish such as prawns and crab", bundle: Copy.bundle)
        case .mollusc: String(localized: "Molluscs such as mussels and squid", bundle: Copy.bundle)
        case .treeNut: String(localized: "Tree nuts", bundle: Copy.bundle)
        case .peanut: String(localized: "Peanuts", bundle: Copy.bundle)
        case .wheat: String(localized: "Wheat", bundle: Copy.bundle)
        case .gluten: String(localized: "Gluten", bundle: Copy.bundle)
        case .soy: String(localized: "Soy", bundle: Copy.bundle)
        case .sesame: String(localized: "Sesame", bundle: Copy.bundle)
        case .celery: String(localized: "Celery", bundle: Copy.bundle)
        case .mustard: String(localized: "Mustard", bundle: Copy.bundle)
        case .lupin: String(localized: "Lupin", bundle: Copy.bundle)
        case .sulphites: String(localized: "Sulphites", bundle: Copy.bundle)
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

    static func name(of rule: ReligiousRule) -> String {
        switch rule {
        case .halal: String(localized: "Halal", bundle: Copy.bundle)
        case .kosher: String(localized: "Kosher", bundle: Copy.bundle)
        case .noPork: String(localized: "No pork", bundle: Copy.bundle)
        case .noBeef: String(localized: "No beef", bundle: Copy.bundle)
        case .noAlcohol: String(localized: "No alcohol", bundle: Copy.bundle)
        case .jain: String(localized: "Jain", bundle: Copy.bundle)
        }
    }

    static func name(of flag: MedicalFlag) -> String {
        switch flag {
        case .coeliacDisease: String(localized: "Coeliac disease", bundle: Copy.bundle)
        case .hypertension: String(localized: "High blood pressure", bundle: Copy.bundle)
        case .type1Diabetes: String(localized: "Type 1 diabetes", bundle: Copy.bundle)
        case .type2Diabetes: String(localized: "Type 2 diabetes", bundle: Copy.bundle)
        case .chronicKidneyDisease: String(localized: "Kidney disease", bundle: Copy.bundle)
        case .pregnancy: String(localized: "Pregnancy", bundle: Copy.bundle)
        case .eatingDisorderHistory: String(localized: "Eating disorder history", bundle: Copy.bundle)
        }
    }

    static func name(of goal: Goal) -> String {
        switch goal {
        case .eatBetter: String(localized: "Eat a bit better", bundle: Copy.bundle)
        case .moreVariety: String(localized: "More variety", bundle: Copy.bundle)
        case .lessWaste: String(localized: "Waste less food", bundle: Copy.bundle)
        case .saveMoney: String(localized: "Spend less", bundle: Copy.bundle)
        case .moreProtein: String(localized: "More protein", bundle: Copy.bundle)
        case .maintain: String(localized: "Keep things as they are", bundle: Copy.bundle)
        }
    }

    static func name(of equipment: Equipment) -> String {
        switch equipment {
        case .oven: String(localized: "Oven", bundle: Copy.bundle)
        case .stovetop: String(localized: "Stovetop", bundle: Copy.bundle)
        case .microwave: String(localized: "Microwave", bundle: Copy.bundle)
        case .airFryer: String(localized: "Air fryer", bundle: Copy.bundle)
        case .slowCooker: String(localized: "Slow cooker", bundle: Copy.bundle)
        case .pressureCooker: String(localized: "Pressure cooker", bundle: Copy.bundle)
        case .blender: String(localized: "Blender", bundle: Copy.bundle)
        case .foodProcessor: String(localized: "Food processor", bundle: Copy.bundle)
        case .grill: String(localized: "Grill", bundle: Copy.bundle)
        }
    }
}
