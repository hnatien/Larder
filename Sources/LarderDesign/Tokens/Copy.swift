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
        public static var ledger: String { String(localized: "Ledger", bundle: .module) }
        public static var shelves: String { String(localized: "Shelves", bundle: .module) }
        public static var recipes: String { String(localized: "Recipes", bundle: .module) }
        public static var grocery: String { String(localized: "Grocery", bundle: .module) }
        public static var account: String { String(localized: "Account", bundle: .module) }
    }

    /// Button and menu labels.
    public enum Action {
        public static var swap: String { String(localized: "Swap", bundle: .module) }
        public static var skip: String { String(localized: "Skip", bundle: .module) }
        public static var markCooked: String { String(localized: "Mark cooked", bundle: .module) }
        public static var letItGo: String { String(localized: "Let it go", bundle: .module) }
        public static var eatIt: String { String(localized: "Eat it", bundle: .module) }
        public static var notNow: String { String(localized: "Not now", bundle: .module) }
        public static var addWhatYouHave: String { String(localized: "Add what you have", bundle: .module) }
        public static var planMyWeek: String { String(localized: "Plan my week", bundle: .module) }
        public static var pickForMe: String { String(localized: "Pick for me", bundle: .module) }
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
                localized: "Planning one week is free. Larder Plus plans the month and watches your shelf.",
                bundle: .module
            )
        }
        public static var subscribe: String { String(localized: "Get Larder Plus", bundle: .module) }
        public static var restore: String { String(localized: "Restore purchases", bundle: .module) }
    }

    /// The Today widget.
    public enum Widget {
        public static var description: String { String(localized: "Tonight's dinner from your Ledger.", bundle: .module) }
        public static var nothingPlanned: String { String(localized: "Nothing planned", bundle: .module) }
        public static var openForIdeas: String { String(localized: "Open Larder for three ideas.", bundle: .module) }
    }

    /// Microcopy for empty states, plans, expiry and errors.
    public enum Voice {
        public static var emptyPantry: String {
            String(localized: "Nothing on the shelves yet. Add what you have and we'll plan around it.", bundle: .module)
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

        public static var offline: String {
            String(
                localized: "Couldn't reach the server. Your plan is saved here and will sync later.",
                bundle: .module
            )
        }
    }
}
