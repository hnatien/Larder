import Foundation

/// A store section; case order is the store-walk order.
public enum Aisle: String, CaseIterable, Hashable, Codable, Sendable {
    case produce
    case bakery
    case meatAndFish
    case dairyAndEggs
    case pantryDry
    case cannedAndJarred
    case frozen
    case spicesAndOils
    case other

    /// The aisle for an item named `name`, from name words first, then food tags, then food group.
    static func forItem(named name: String, food: Food?) -> Aisle {
        let words = TermMatcher.words(name)
        for (aisle, terms) in nameTerms where terms.contains(where: { TermMatcher.contains($0, in: words) }) {
            return aisle
        }
        guard let food else { return .other }
        if !food.tags.isDisjoint(with: [.meat, .pork, .beef, .poultry, .fish, .shellfish, .rawFish]) { return .meatAndFish }
        if !food.tags.isDisjoint(with: [.dairy, .egg]) { return .dairyAndEggs }
        switch food.foodGroup {
        case .produce: return .produce
        case .grains, .legumes: return .pantryDry
        case .dairy: return .dairyAndEggs
        case .fats: return .spicesAndOils
        case .protein, .other: return .other
        }
    }

    private static let nameTerms: [(Aisle, [String])] = [
        (.frozen, ["frozen"]),
        (.cannedAndJarred, ["canned", "tinned", "jarred", "passata", "stock", "broth"]),
        (.spicesAndOils, [
            "salt", "oil", "vinegar", "spice", "black pepper", "peppercorn", "cumin", "paprika", "turmeric",
            "cinnamon", "oregano", "chilli flakes", "garam masala", "curry powder", "cayenne",
        ]),
        (.bakery, ["bread", "baguette", "tortilla", "pitta", "pita", "naan", "bagel", "croissant", "bun"]),
    ]
}
