import Foundation

extension StorageLocation {
    /// Where an item named `name` is usually kept, for when the user did not say.
    ///
    /// The item's own words decide first, then the matched food's name ("tuna" matched to "Tuna, canned"), then the
    /// food's tags and group; anything still unknown goes in the cupboard. Within each name, frozen beats shelf-stable
    /// beats chilled, so "frozen prawns", "coconut milk" and "chicken stock" land where they belong.
    public static func usual(forItemNamed name: String, food: Food?) -> StorageLocation {
        for text in [name, food?.name].compactMap(\.self) {
            let words = TermMatcher.words(text)
            for (location, terms) in nameTerms where terms.contains(where: { TermMatcher.contains($0, in: words) }) {
                return location
            }
        }
        guard let food else { return .pantry }
        if !food.tags.isDisjoint(with: [.meat, .pork, .beef, .poultry, .fish, .shellfish, .rawFish, .egg, .dairy]) {
            return .fridge
        }
        return food.foodGroup == .dairy ? .fridge : .pantry
    }

    private static let nameTerms: [(StorageLocation, [String])] = [
        (.freezer, ["frozen", "ice cream"]),
        (.pantry, [
            "canned", "tinned", "jarred", "dried", "uht", "stock", "broth", "peanut butter", "nut butter",
            "butter beans", "coconut milk", "chocolate", "black pepper", "powder", "flakes",
        ]),
        (.fridge, [
            "chicken", "beef", "pork", "lamb", "mince", "turkey", "duck", "bacon", "ham", "sausage", "steak", "chorizo",
            "fish", "salmon", "cod", "haddock", "prawn", "shrimp", "mussel", "egg", "milk", "cheese", "cheddar", "feta",
            "mozzarella", "parmesan", "halloumi", "yoghurt", "yogurt", "butter", "cream", "tofu", "tempeh", "hummus",
            "spinach", "lettuce", "salad", "rocket", "kale", "broccoli", "carrot", "celery", "courgette", "cucumber",
            "mushroom", "leek", "spring onion", "bell pepper", "asparagus", "green beans", "berry", "blueberry",
            "strawberry", "raspberry", "grape", "parsley", "coriander", "basil", "mint", "chive",
        ]),
    ]
}
