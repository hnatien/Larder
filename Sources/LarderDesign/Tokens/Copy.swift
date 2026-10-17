import Foundation
import LarderCore

/// Every user-facing string in the design module. Dry, plain, no exclamation marks, no moralising.
public nonisolated enum Copy {
    /// The bundle holding the string catalogue. Feature modules pass it to `String(localized:bundle:)` so every
    /// user-facing string resolves through this one catalogue.
    public static var bundle: Bundle { .module }

    /// Tab bar titles.
    public enum Tab {
        public static var tonight: String { String(localized: "Tonight", bundle: .module) }
        public static var ledger: String { String(localized: "Plan", bundle: .module) }
        public static var shelves: String { String(localized: "Pantry", bundle: .module) }
        public static var recipes: String { String(localized: "Recipes", bundle: .module) }
        public static var grocery: String { String(localized: "Groceries", bundle: .module) }
        public static var account: String { String(localized: "Settings", bundle: .module) }
    }

    /// Button and menu labels.
    public enum Action {
        public static var swap: String { String(localized: "Swap", bundle: .module) }
        public static var skip: String { String(localized: "Skip", bundle: .module) }
        public static var markCooked: String { String(localized: "Mark as cooked", bundle: .module) }
        public static var letItGo: String { String(localized: "Throw away", bundle: .module) }
        public static var eatIt: String { String(localized: "Used up", bundle: .module) }
        public static var notNow: String { String(localized: "Not now", bundle: .module) }
        public static var addWhatYouHave: String { String(localized: "Add what you have", bundle: .module) }
        public static var planMyWeek: String { String(localized: "Plan my week", bundle: .module) }
        public static var otherIdeas: String { String(localized: "Show other ideas", bundle: .module) }
        public static var addFood: String { String(localized: "Add food", bundle: .module) }
        public static var undo: String { String(localized: "Undo", bundle: .module) }
    }

    /// Freshness words; each has an icon in `FreshnessStyle`.
    public enum Freshness {
        public static var fresh: String { String(localized: "Fresh", bundle: .module) }
        public static var soon: String { String(localized: "Use soon", bundle: .module) }
        public static var today: String { String(localized: "Use today", bundle: .module) }
        public static var past: String { String(localized: "Past its best", bundle: .module) }

        /// What VoiceOver reads for a freshness stamp that carries a date.
        public static func spoken(word: String, bestBy date: String) -> String {
            String(localized: "\(word), best by \(date)", bundle: .module)
        }
    }

    /// Shelf balance wording; never a number.
    public enum Shelf {
        public static var light: String { String(localized: "Light", bundle: .module) }
        public static var comfortable: String { String(localized: "Comfortable", bundle: .module) }
        public static var heavy: String { String(localized: "Heavy", bundle: .module) }

        /// The display name of a food group.
        public static func name(of group: FoodGroup) -> String {
            switch group {
            case .produce: String(localized: "Produce", bundle: .module)
            case .grains: String(localized: "Grains", bundle: .module)
            case .protein: String(localized: "Protein", bundle: .module)
            case .dairy: String(localized: "Dairy", bundle: .module)
            case .fats: String(localized: "Fats", bundle: .module)
            case .legumes: String(localized: "Legumes", bundle: .module)
            case .other: String(localized: "Other", bundle: .module)
            }
        }
    }

    /// Words used by the week ledger and meal tags.
    public enum Ledger {
        public static var today: String { String(localized: "Today", bundle: .module) }

        /// Short form for a visible tag.
        public static func minutes(_ count: Int) -> String {
            String(localized: "\(count) min", bundle: .module)
        }

        /// Long form for VoiceOver.
        public static func spokenMinutes(_ count: Int) -> String {
            String(localized: "\(count) minutes", bundle: .module)
        }
    }

    /// Allergen notices. "Unknown" is never shown as safe.
    public enum Allergen {
        public static var checkTheLabel: String {
            String(localized: "Check the label on every product.", bundle: .module)
        }

        public static func excluded(allergen: String, because source: String) -> String {
            String(localized: "Excluded: contains \(allergen) (\(source)).", bundle: .module)
        }

        public static func unsure(about item: String) -> String {
            String(localized: "We're not sure about \(item) here. Check the label.", bundle: .module)
        }
    }

    /// Shown wherever a condition is set up.
    public enum Medical {
        public static var disclaimer: String {
            String(
                localized: "Larder helps you plan meals. It is not medical advice. Talk to your clinician about any condition.",
                bundle: .module
            )
        }
    }

    /// Paywall copy; plain, with "Not now" as an equal-weight button.
    public enum Plus {
        public static var name: String { String(localized: "Larder Plus", bundle: .module) }
        public static var pitch: String {
            String(
                localized: "Planning your first week is free. Larder Plus plans every week and reads recipes and receipts from a photo.",
                bundle: .module
            )
        }
        public static var subscribe: String { String(localized: "Get Larder Plus", bundle: .module) }
        public static var restore: String { String(localized: "Restore purchases", bundle: .module) }
    }

    /// The Today widget.
    public enum Widget {
        public static var description: String { String(localized: "Tonight's dinner from your plan.", bundle: .module) }
        public static var nothingPlanned: String { String(localized: "Nothing planned", bundle: .module) }
        public static var openForIdeas: String { String(localized: "Open Larder for three ideas.", bundle: .module) }
    }

    /// Asking for AI help where it is needed.
    public enum Consent {
        public static var title: String { String(localized: "Allow AI help?", bundle: .module) }
        public static var sends: String {
            String(localized: "Recipe text and plain settings such as cook time and diet type go to Larder's server and the AI model behind it.", bundle: .module)
        }
        public static var stays: String {
            String(localized: "Medical and religious details never leave this iPhone.", bundle: .module)
        }
        public static var change: String { String(localized: "You can turn it off in Settings at any time.", bundle: .module) }
        public static var allow: String { String(localized: "Allow AI help", bundle: .module) }
    }

    /// Strings the app shell shows: launch failures and recipes that cannot be opened.
    public enum App {
        public static var recipeMissing: String { String(localized: "That recipe is no longer in your library.", bundle: .module) }
        public static var recipeUnreadable: String { String(localized: "Couldn't open that recipe. Try again.", bundle: .module) }
        public static var ok: String { String(localized: "OK", bundle: .module) }
        public static var startupFailedTitle: String { String(localized: "Larder couldn't open your data", bundle: .module) }
        public static var startupFailedMessage: String {
            String(localized: "Your data stays on this device. Try again, or close Larder and open it again.", bundle: .module)
        }
        public static var tryAgain: String { String(localized: "Try again", bundle: .module) }
        public static var addedFirstFood: String {
            String(localized: "Your pantry has food in it. Here are tonight's ideas.", bundle: .module)
        }
    }

    /// Microcopy for empty states, plans, expiry and errors.
    public enum Voice {
        public static var emptyPantry: String {
            String(localized: "Add what you have at home and Larder plans dinners around it.", bundle: .module)
        }

        public static func firstPlan(nights: Int, using item: String) -> String {
            String(localized: "Here's your week. \(nights) nights use up the \(item).", bundle: .module)
        }

        public static func expiring(item: String, weekday: String) -> String {
            String(localized: "\(item) is best by \(weekday). Dinner tonight uses it.", bundle: .module)
        }

        public static func expiredToday(item: String) -> String {
            String(localized: "The \(item) is at its limit today. Eat it, or let it go.", bundle: .module)
        }

        /// The masking-tape label, without a full stop.
        public static func leftoverTag(dish: String, day: Int, of total: Int) -> String {
            String(localized: "\(dish), day \(day) of \(total)", bundle: .module)
        }

        public static func lightOnGroup(_ group: String) -> String {
            String(localized: "Light on \(group) this week. A handful in two dinners would do it.", bundle: .module)
        }

        public static var vetoReply: String {
            String(localized: "Fair. Here's another that uses the same ingredients.", bundle: .module)
        }

        public static var planSaved: String { String(localized: "Stamped. The week is yours.", bundle: .module) }

        /// Confirms a cooked dish; `usedPantry` says whether cooking took anything off the shelves.
        public static func cooked(dish: String, usedPantry: Bool) -> String {
            usedPantry
                ? String(localized: "\(dish) cooked. What it used is off your pantry.", bundle: .module)
                : String(localized: "\(dish) marked as cooked", bundle: .module)
        }

        public static var offline: String {
            String(
                localized: "Couldn't reach the server. Your plan is saved here and will sync later.",
                bundle: .module
            )
        }
    }
}
