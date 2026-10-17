import Foundation

/// Default best-by dates for food that arrives without one, such as items bought from the grocery list.
///
/// Days come from a table by food group and storage place, plus a few named foods the group gets badly wrong
/// (eggs, bread, hard cheese, tins). Sources:
/// - USDA FSIS FoodKeeper (foodsafety.gov/keep-food-safe/foodkeeper-app): refrigerator, freezer and pantry times per food.
/// - FDA, "Refrigerator & Freezer Storage Chart": raw poultry, mince and fish 1 to 2 days chilled; eggs in shell 3 to
///   5 weeks; frozen times are for quality only, since food kept at 0 °F stays safe.
/// - USDA FSIS, "Shelf-Stable Food Safety": low-acid tins 2 to 5 years, high-acid tins such as tomatoes 12 to 18 months.
///
/// Each value is rounded towards the short end of the published range for the more perishable common foods of its
/// group, so a guess errs towards the Use soon list rather than past a real date. The user can always edit it.
public enum ShelfLife {
    /// Days an item keeps where it is stored, counted from the day it was added.
    ///
    /// The item's own name decides first, then the matched food's name, then the food's group; an item with no food
    /// counts as `.other`. `StorageLocation.other` keeps like the cupboard.
    public static func days(forItemNamed name: String, food: Food?, in location: StorageLocation) -> Int {
        let place: StorageLocation = location == .other ? .pantry : location
        for text in [name, food?.name].compactMap(\.self) {
            let words = TermMatcher.words(text)
            if let exception = exceptions.first(where: { exception in
                exception.location == place && exception.terms.contains { TermMatcher.contains($0, in: words) }
            }) {
                return exception.days
            }
        }
        return table[food?.foodGroup ?? .other]?[place] ?? fallbackDays
    }

    /// The start of the day `days(forItemNamed:food:in:)` after `addedOn`.
    public static func bestBy(
        forItemNamed name: String,
        food: Food?,
        in location: StorageLocation,
        addedOn: Date,
        calendar: Calendar = .current
    ) -> Date? {
        calendar.date(byAdding: .day, value: days(forItemNamed: name, food: food, in: location), to: calendar.startOfDay(for: addedOn))
    }

    /// Used only if the table misses a group or place, which the tests rule out.
    static let fallbackDays = 7

    /// Days by food group, then by fridge, freezer and cupboard.
    static let table: [FoodGroup: [StorageLocation: Int]] = [
        // Leafy greens and soft fruit 3 to 7 days chilled; onions and potatoes about a month in the cupboard.
        .produce: [.fridge: 5, .freezer: 240, .pantry: 30],
        // Raw poultry, mince and fish 1 to 2 days chilled, 3 to 4 months frozen for mince; tinned fish and meat years.
        .protein: [.fridge: 2, .freezer: 90, .pantry: 365],
        // Milk 7 days, yoghurt 1 to 2 weeks, soft cheese 1 week chilled; UHT milk months unopened.
        .dairy: [.fridge: 7, .freezer: 90, .pantry: 180],
        // Cooked grains 3 to 5 days chilled; flour 6 to 8 months, dried rice and pasta 1 to 2 years in the cupboard.
        .grains: [.fridge: 5, .freezer: 90, .pantry: 180],
        // Opened oils and nut butters a few months; nuts about 6 months in the cupboard.
        .fats: [.fridge: 30, .freezer: 180, .pantry: 180],
        // Tofu, hummus and cooked beans 3 to 5 days chilled; dried and tinned pulses a year or more.
        .legumes: [.fridge: 4, .freezer: 180, .pantry: 365],
        // Sauces and stock once opened about a week chilled; spices and condiments months in the cupboard.
        .other: [.fridge: 7, .freezer: 90, .pantry: 180],
    ]

    /// Named foods whose group's default is far off, by place.
    static let exceptions: [(terms: [String], location: StorageLocation, days: Int)] = [
        // Eggs in shell 3 to 5 weeks chilled.
        (["egg"], .fridge, 21),
        // Hard cheese 3 to 4 weeks once opened; butter 1 to 3 months.
        (["cheddar", "parmesan", "butter"], .fridge, 21),
        // Tofu and tempeh 3 to 5 days once opened.
        (["tofu", "tempeh"], .fridge, 4),
        // Shop bread a few days at room temperature.
        (["bread", "tortilla", "pita"], .pantry, 5),
        // High-acid tins 12 to 18 months, low-acid tins 2 to 5 years.
        (["canned", "tinned"], .pantry, 365),
    ]
}
