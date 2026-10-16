import Foundation
import LarderCore

/// User-facing strings for onboarding, the paywall and settings. Dry, plain, no exclamation marks.
nonisolated enum AccountCopy {
    static var back: String { String(localized: "Back") }
    static var next: String { String(localized: "Next") }
    static var finish: String { String(localized: "Finish") }
    static var skip: String { String(localized: "Skip") }
    static var preferNotToSay: String { String(localized: "Prefer not to say") }
    static var cancel: String { String(localized: "Cancel") }
    static var tryAgain: String { String(localized: "Try again") }

    static func showAll(_ count: Int) -> String { String(localized: "Show all \(count)") }
    static func showFewer() -> String { String(localized: "Show fewer") }
    static func progress(step: Int, of total: Int) -> String { String(localized: "\(step) of \(total)") }
    static func spokenProgress(step: Int, of total: Int) -> String { String(localized: "Step \(step) of \(total)") }
    static func remove(_ name: String) -> String { String(localized: "Remove \(name)") }

    /// Onboarding questions and explanations.
    enum Onboarding {
        static var welcomeTitle: String { String(localized: "Welcome to Larder") }
        static var welcomeLines: [String] {
            [
                String(localized: "Larder plans meals around what is already on your shelves."),
                String(localized: "It writes the grocery list and moves what you buy onto the shelves."),
                String(localized: "It keeps what you can't eat out of every plan."),
            ]
        }
        static var consentLabel: String { String(localized: "Allow AI help") }
        static var consentExplanation: String {
            String(
                localized: "When this is on, Larder sends recipe text and plain settings such as cook time and diet type to its server and the AI model behind it, to explain plans and answer requests. Medical and religious details never leave this device. It stays off unless you turn it on."
            )
        }
        static var leaveOutTitle: String { String(localized: "What should we always leave out?") }
        static var intoleranceLabel: String { String(localized: "Anything else to leave out") }
        static var intolerancePrompt: String { String(localized: "For example lactose, separated by commas") }
        static var eatByTitle: String { String(localized: "Anything we eat by?") }
        static var carefulTitle: String { String(localized: "Anything we should be careful with?") }
        static var goalTitle: String { String(localized: "What matters most?") }
        static var householdTitle: String { String(localized: "Who's eating?") }
        static func household(_ count: Int) -> String { String(localized: "\(count) at the table") }
        static var cookTimeLabel: String { String(localized: "Longest time to cook on a weeknight") }
        static var birthYearLabel: String { String(localized: "Year you were born") }
        static var birthYearExplanation: String {
            String(localized: "Used only for nutrient ranges on this device.")
        }
        static var equipmentTitle: String { String(localized: "What do you cook with?") }
        static var easierTitle: String { String(localized: "Make Larder easier to use") }
        static var largerTextLabel: String { String(localized: "Larger text") }
        static var largerTextHint: String {
            String(localized: "Larder follows the text size set in Settings, under Accessibility, Display and Text Size.")
        }
        static var simpleLayoutLabel: String { String(localized: "Simpler layout") }
        static var simpleLayoutHint: String { String(localized: "Fewer choices on each screen.") }
        static var timersLabel: String { String(localized: "Timers flash and vibrate") }
        static var timersHint: String { String(localized: "Every timer sound also flashes the screen and vibrates.") }
        static var saveFailed: String { String(localized: "Couldn't save your answers. Try again.") }
    }

    /// The "Show numbers" switch, shared by onboarding and settings.
    enum Numbers {
        static var label: String { String(localized: "Show numbers") }
        static var hint: String {
            String(localized: "Calories and nutrient amounts stay hidden unless this is on. Shelf balance uses words either way.")
        }
    }

    /// The paywall.
    enum Paywall {
        static var features: [String] {
            [
                String(localized: "Plan my week fills the whole week and replans when things change, with a reason for each meal."),
                String(localized: "Household profiles give each person their own swaps on one shared plate."),
                String(localized: "Leftovers and batch cooking are scheduled for you."),
                String(localized: "Shelf balance shows each food group across the week, with numbers only if you want them."),
                String(localized: "Photos and receipts update the shelves."),
                String(localized: "The assistant takes requests such as a vegetarian Tuesday under 30 minutes."),
            ]
        }
        static var staysFree: String {
            String(localized: "Allergen filters, recipes, shelves, grocery lists and export stay free.")
        }
        static var renews: String {
            String(localized: "Subscriptions renew automatically until cancelled in your App Store account settings.")
        }
        static var terms: String { String(localized: "Terms of use") }
        static var privacy: String { String(localized: "Privacy policy") }
        static var pending: String { String(localized: "Waiting for approval. Plus starts once the purchase is approved.") }

        static func price(_ product: StoreProduct) -> String {
            guard let period = product.period else { return product.displayPrice }
            let renewal = switch (period.unit, period.value) {
            case (.day, 1): String(localized: "\(product.displayPrice) a day")
            case (.week, 1): String(localized: "\(product.displayPrice) a week")
            case (.month, 1): String(localized: "\(product.displayPrice) a month")
            case (.year, 1): String(localized: "\(product.displayPrice) a year")
            case (_, let value): String(localized: "\(product.displayPrice) every \(value) \(unitName(period.unit, value: value))")
            }
            guard let trial = product.freeTrial else { return renewal }
            return String(localized: "\(trial.value) \(unitName(trial.unit, value: trial.value)) free, then \(renewal)")
        }

        private static func unitName(_ unit: BillingPeriod.Unit, value: Int) -> String {
            switch unit {
            case .day: value == 1 ? String(localized: "day") : String(localized: "days")
            case .week: value == 1 ? String(localized: "week") : String(localized: "weeks")
            case .month: value == 1 ? String(localized: "month") : String(localized: "months")
            case .year: value == 1 ? String(localized: "year") : String(localized: "years")
            }
        }
    }

    /// Store failures.
    static func message(for error: EntitlementError) -> String {
        switch error {
        case .productsUnavailable: String(localized: "Couldn't load prices. Check the connection and try again.")
        case .purchaseFailed: String(localized: "The purchase didn't go through. Try again in a moment.")
        case .verificationFailed: String(localized: "The App Store couldn't confirm this purchase. Try Restore purchases.")
        case .restoreFailed: String(localized: "Couldn't restore purchases. Try again in a moment.")
        }
    }

    /// Settings.
    enum Settings {
        static var title: String { String(localized: "Settings") }
        static var profile: String { String(localized: "Profile") }
        static var goal: String { String(localized: "What matters most") }
        static var equipment: String { String(localized: "Equipment") }
        static var leaveOut: String { String(localized: "What we leave out") }
        static var nothingLeftOut: String { String(localized: "Nothing yet.") }
        static var add: String { String(localized: "Add") }
        static var removeShort: String { String(localized: "Remove") }
        static var addIntolerance: String { String(localized: "Add something else to leave out") }
        static var addDislike: String { String(localized: "Add a food you'd rather skip") }
        static func removeTitle(_ name: String) -> String { String(localized: "Stop leaving out \(name)?") }
        static var removeMessage: String { String(localized: "Plans will be able to include it again.") }
        static var removeConfirm: String { String(localized: "Stop leaving it out") }
        static var keep: String { String(localized: "Keep it") }
        static var plus: String { String(localized: "Larder Plus") }
        static func plusUntil(_ date: String) -> String { String(localized: "Plus until \(date)") }
        static var plusActive: String { String(localized: "Plus") }
        static var free: String { String(localized: "Free") }
        static var manage: String { String(localized: "Manage subscription") }
        static var seePlus: String { String(localized: "See Larder Plus") }
        static var data: String { String(localized: "Data") }
        static var export: String { String(localized: "Export everything") }
        static var exportHint: String {
            String(localized: "A JSON file with your profile, what we leave out, targets, recipes, shelves and plans.")
        }
        static var exportName: String { String(localized: "Larder export") }
        static var delete: String { String(localized: "Delete all data") }
        static var deleteTitle: String { String(localized: "Delete everything on this device?") }
        static var deleteMessage: String {
            String(localized: "Your profile, recipes, shelves and plans are removed and can't be recovered. A subscription is managed by the App Store and is not cancelled.")
        }
        static var deleteConfirm: String { String(localized: "Delete everything") }
        static var about: String { String(localized: "About") }
        static func version(_ version: String) -> String { String(localized: "Version \(version)") }
        static var grdbLicence: String { String(localized: "GRDB, MIT License") }
        static var fontLicence: String { String(localized: "Fraunces and Commit Mono, SIL Open Font License") }
        static var usdaAttribution: String { String(localized: "Contains data from USDA FoodData Central.") }
    }

    /// Settings failures.
    static func message(for error: SettingsError) -> String {
        switch error {
        case .loadFailed: String(localized: "Couldn't load your settings. Try again.")
        case .saveFailed: String(localized: "Couldn't save that change. Try again.")
        case .deleteFailed: String(localized: "Couldn't delete your data. Try again.")
        }
    }

    /// Headings for the constraint axes the user can edit.
    static func name(of axis: ConstraintAxis) -> String {
        switch axis {
        case .medical: String(localized: "Allergies and health")
        case .religious: String(localized: "Faith")
        case .ethical: String(localized: "Diet")
        case .preference: String(localized: "Dislikes")
        case .goal: String(localized: "Goals")
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
        case .dislike(.food): String(localized: "A food you dislike")
        }
    }

    static func name(of allergen: Allergen) -> String {
        switch allergen {
        case .milk: String(localized: "Milk")
        case .egg: String(localized: "Eggs")
        case .fish: String(localized: "Fish")
        case .crustacean: String(localized: "Shellfish such as prawns and crab")
        case .mollusc: String(localized: "Molluscs such as mussels and squid")
        case .treeNut: String(localized: "Tree nuts")
        case .peanut: String(localized: "Peanuts")
        case .wheat: String(localized: "Wheat")
        case .gluten: String(localized: "Gluten")
        case .soy: String(localized: "Soy")
        case .sesame: String(localized: "Sesame")
        case .celery: String(localized: "Celery")
        case .mustard: String(localized: "Mustard")
        case .lupin: String(localized: "Lupin")
        case .sulphites: String(localized: "Sulphites")
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

    static func name(of rule: ReligiousRule) -> String {
        switch rule {
        case .halal: String(localized: "Halal")
        case .kosher: String(localized: "Kosher")
        case .noPork: String(localized: "No pork")
        case .noBeef: String(localized: "No beef")
        case .noAlcohol: String(localized: "No alcohol")
        case .jain: String(localized: "Jain")
        }
    }

    static func name(of flag: MedicalFlag) -> String {
        switch flag {
        case .coeliacDisease: String(localized: "Coeliac disease")
        case .hypertension: String(localized: "High blood pressure")
        case .type1Diabetes: String(localized: "Type 1 diabetes")
        case .type2Diabetes: String(localized: "Type 2 diabetes")
        case .chronicKidneyDisease: String(localized: "Kidney disease")
        case .pregnancy: String(localized: "Pregnancy")
        case .eatingDisorderHistory: String(localized: "Eating disorder history")
        }
    }

    static func name(of goal: Goal) -> String {
        switch goal {
        case .eatBetter: String(localized: "Eat a bit better")
        case .moreVariety: String(localized: "More variety")
        case .lessWaste: String(localized: "Waste less food")
        case .saveMoney: String(localized: "Spend less")
        case .moreProtein: String(localized: "More protein")
        case .maintain: String(localized: "Keep things as they are")
        }
    }

    static func name(of equipment: Equipment) -> String {
        switch equipment {
        case .oven: String(localized: "Oven")
        case .stovetop: String(localized: "Stovetop")
        case .microwave: String(localized: "Microwave")
        case .airFryer: String(localized: "Air fryer")
        case .slowCooker: String(localized: "Slow cooker")
        case .pressureCooker: String(localized: "Pressure cooker")
        case .blender: String(localized: "Blender")
        case .foodProcessor: String(localized: "Food processor")
        case .grill: String(localized: "Grill")
        }
    }
}
