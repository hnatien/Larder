import Foundation

/// Why an allergen check did not come back clear.
public struct AllergenReason: Hashable, Sendable {
    public var allergen: Allergen
    /// The ingredient line, or `nil` when the evidence is the recipe title or the recipe has no ingredients.
    public var ingredientID: IngredientID?
    public var evidence: AllergenEvidence

    /// Creates a reason.
    public init(allergen: Allergen, ingredientID: IngredientID?, evidence: AllergenEvidence) {
        self.allergen = allergen
        self.ingredientID = ingredientID
        self.evidence = evidence
    }
}

/// Which check produced an allergen reason.
public enum AllergenEvidence: Hashable, Sendable {
    /// The food's allergen tag, from the data path.
    case dataTag(AllergenPresence)
    /// A lexicon term in the ingredient text, food name or recipe title, from the text path.
    case lexicon(term: String)
}

/// Outcome of checking a recipe against allergen constraints.
public enum AllergenVerdict: Hashable, Sendable {
    case clear
    case excluded([AllergenReason])
    /// Not known to be safe; never shown as safe.
    case uncertain([AllergenReason])
}

/// Checks recipes for allergens along two independent paths: food allergen tags and a text lexicon.
public struct AllergenEngine: Sendable {
    public var lexicon: AllergenLexicon

    /// The match confidence from which a food's verified-free tag speaks for an ingredient line. Seed recipes name
    /// their foods (1); an imported line's first-word guess (0.5) can be a different product, such as "chicken
    /// nuggets" matched to raw chicken, so its free tags read as unknown while contains and may-contain still count.
    public static let trustedMatchConfidence = 1.0

    /// Creates an engine.
    public init(lexicon: AllergenLexicon = .standard) {
        self.lexicon = lexicon
    }

    /// Worst tagged presence across all ingredients, garnish included; a missing food, a verified-free tag on a match
    /// below `trustedMatchConfidence` or an empty list is `.unknown`.
    public func dataPath(_ ingredients: [Ingredient], foods: [FoodID: Food], allergen: Allergen) -> AllergenPresence {
        guard !ingredients.isEmpty else { return .unknown }
        return ingredients.map { presence(of: allergen, in: $0, foods: foods) }.max { $0.severity < $1.severity } ?? .unknown
    }

    /// Whether any ingredient's text or food name contains a lexicon term for `allergen`.
    public func textPath(_ ingredients: [Ingredient], foods: [FoodID: Food], allergen: Allergen) -> Bool {
        ingredients.contains { lexiconHit(for: allergen, in: $0, foods: foods) != nil }
    }

    /// Verdict for `recipe` against the allergen constraints in `constraints`; other kinds are ignored.
    ///
    /// Hard: a contains tag or a lexicon hit excludes; may-contain or unknown is uncertain; verified-free with
    /// no lexicon hit is clear. Soft constraints turn every exclusion into uncertainty.
    public func evaluate(
        recipe: Recipe,
        ingredients: [Ingredient],
        foods: [FoodID: Food],
        constraints: [DietaryConstraint]
    ) -> AllergenVerdict {
        let requirements = constraints.compactMap { constraint -> (Allergen, Strictness)? in
            if case .allergen(let allergen) = constraint.kind { (allergen, constraint.strictness) } else { nil }
        }
        return evaluate(recipe: recipe, ingredients: ingredients, foods: foods, requirements: requirements)
    }

    /// Verdict against explicit allergen requirements; hard wins when an allergen is listed twice.
    func evaluate(
        recipe: Recipe,
        ingredients: [Ingredient],
        foods: [FoodID: Food],
        requirements: [(Allergen, Strictness)]
    ) -> AllergenVerdict {
        var strictness: [Allergen: Strictness] = [:]
        for (allergen, level) in requirements where strictness[allergen] != .hard {
            strictness[allergen] = level
        }

        var excluded: [AllergenReason] = []
        var uncertain: [AllergenReason] = []
        for allergen in Allergen.allCases {
            guard let level = strictness[allergen] else { continue }
            for (reason, excludes) in findings(for: allergen, recipe: recipe, ingredients: ingredients, foods: foods) {
                if excludes, level == .hard {
                    excluded.append(reason)
                } else {
                    uncertain.append(reason)
                }
            }
        }
        if !excluded.isEmpty { return .excluded(excluded) }
        if !uncertain.isEmpty { return .uncertain(uncertain) }
        return .clear
    }

    /// Every reason `allergen` may be present, flagged with whether it would exclude under a hard constraint.
    private func findings(
        for allergen: Allergen,
        recipe: Recipe,
        ingredients: [Ingredient],
        foods: [FoodID: Food]
    ) -> [(AllergenReason, excludes: Bool)] {
        var results: [(AllergenReason, excludes: Bool)] = []
        if let term = lexicon.match(in: recipe.title, for: allergen) {
            results.append((AllergenReason(allergen: allergen, ingredientID: nil, evidence: .lexicon(term: term)), true))
        }
        if ingredients.isEmpty {
            results.append((AllergenReason(allergen: allergen, ingredientID: nil, evidence: .dataTag(.unknown)), false))
        }
        for ingredient in ingredients {
            if let term = lexiconHit(for: allergen, in: ingredient, foods: foods) {
                results.append((AllergenReason(allergen: allergen, ingredientID: ingredient.id, evidence: .lexicon(term: term)), true))
                continue
            }
            let presence = presence(of: allergen, in: ingredient, foods: foods)
            if presence != .verifiedFree {
                results.append((AllergenReason(allergen: allergen, ingredientID: ingredient.id, evidence: .dataTag(presence)), presence == .contains))
            }
        }
        return results
    }

    private func presence(of allergen: Allergen, in ingredient: Ingredient, foods: [FoodID: Food]) -> AllergenPresence {
        guard let food = ingredient.foodID.flatMap({ foods[$0] }) else { return .unknown }
        let presence = food.allergens.presence(of: allergen)
        if presence == .verifiedFree, ingredient.matchConfidence < Self.trustedMatchConfidence { return .unknown }
        return presence
    }

    private func lexiconHit(for allergen: Allergen, in ingredient: Ingredient, foods: [FoodID: Food]) -> String? {
        if let term = lexicon.match(in: ingredient.rawText, for: allergen) { return term }
        guard let food = ingredient.foodID.flatMap({ foods[$0] }) else { return nil }
        return lexicon.match(in: food.name, for: allergen)
    }
}

extension AllergenPresence {
    fileprivate var severity: Int {
        switch self {
        case .verifiedFree: 0
        case .unknown: 1
        case .mayContain: 2
        case .contains: 3
        }
    }
}
