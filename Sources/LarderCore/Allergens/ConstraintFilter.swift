import Foundation

/// Outcome of checking a recipe against all dietary constraints; reasons are ready to show.
public enum FilterVerdict: Hashable, Sendable {
    case pass(softPenalties: [String])
    case excluded(reasons: [String])
    /// Not known to be safe; never shown as safe.
    case uncertain(reasons: [String])
}

/// Combines the allergen engine with diet, religious, medical, intolerance and dislike rules.
///
/// Hard tag-based rules exclude and soft ones add a penalty. Under a hard diet or religious rule an
/// ingredient without food data is uncertain, because its tags are unknown. Kosher meat-and-dairy
/// separation is not modelled.
public struct ConstraintFilter: Sendable {
    public var allergenEngine: AllergenEngine

    /// Creates a filter.
    public init(allergenEngine: AllergenEngine = AllergenEngine()) {
        self.allergenEngine = allergenEngine
    }

    /// Verdict for `recipe`; any exclusion wins over uncertainty, which wins over a pass.
    public func verdict(
        recipe: Recipe,
        ingredients: [Ingredient],
        foods: [FoodID: Food],
        constraints: [DietaryConstraint]
    ) -> FilterVerdict {
        var findings = Findings()
        var allergenRequirements: [(Allergen, Strictness)] = []
        let lines = ingredients.map { Line(ingredient: $0, food: $0.foodID.flatMap { foods[$0] }) }

        for constraint in constraints {
            let hard = constraint.strictness == .hard
            switch constraint.kind {
            case .allergen(let allergen):
                allergenRequirements.append((allergen, constraint.strictness))
            case .medical(.coeliacDisease):
                allergenRequirements.append((.gluten, .hard))
                allergenRequirements.append((.wheat, .hard))
            case .medical(.pregnancy):
                for (line, tag) in tagged(lines, with: [.rawFish, .unpasteurised]) {
                    findings.uncertain.append("Contains \(tag.readableName) (\(line.name)), flagged for pregnancy")
                }
            case .medical(.hypertension):
                for (line, _) in tagged(lines, with: [.highSodium]) {
                    findings.penalties.append("High in sodium (\(line.name))")
                }
            case .medical:
                break
            case .diet(let pattern):
                applyTagRule(pattern.excludedTags, rule: pattern.readableName, hard: hard, lines: lines, to: &findings)
            case .religious(let rule):
                applyTagRule(rule.excludedTags, rule: rule.readableName, hard: hard, lines: lines, to: &findings)
                if rule == .jain {
                    applyTerms(Self.rootVegetables, label: { "Jain: contains root vegetable \($0)" }, hard: hard, lines: lines, to: &findings)
                }
            case .intolerance(let name):
                applyTerms(intoleranceTerms(name), label: { "Contains \($0) (\(name) intolerance)" }, hard: hard, lines: lines, to: &findings)
            case .dislike(.food(let foodID)):
                for line in lines where line.ingredient.foodID == foodID {
                    findings.add("Contains a disliked food (\(line.name))", hard: hard)
                }
            case .dislike(.name(let name)):
                applyTerms([name], label: { "Contains a disliked food (\($0))" }, hard: hard, lines: lines, to: &findings)
            }
        }

        switch allergenEngine.evaluate(recipe: recipe, ingredients: ingredients, foods: foods, requirements: allergenRequirements) {
        case .clear: break
        case .excluded(let reasons): findings.excluded += reasons.map { describe($0, lines: lines) }
        case .uncertain(let reasons): findings.uncertain += reasons.map { describe($0, lines: lines) }
        }

        if !findings.excluded.isEmpty { return .excluded(reasons: findings.excluded.uniqued()) }
        if !findings.uncertain.isEmpty { return .uncertain(reasons: findings.uncertain.uniqued()) }
        return .pass(softPenalties: findings.penalties.uniqued())
    }

    /// Words that mark a root vegetable for the Jain rule, matched against ingredient text and food names.
    static let rootVegetables = [
        "onion", "garlic", "potato", "carrot", "beetroot", "beet", "radish", "turnip", "ginger", "shallot", "leek",
        "scallion", "yam", "parsnip",
    ]

    private struct Line {
        var ingredient: Ingredient
        var food: Food?
        var name: String { food?.name ?? ingredient.rawText }
    }

    private struct Findings {
        var excluded: [String] = []
        var uncertain: [String] = []
        var penalties: [String] = []

        mutating func add(_ reason: String, hard: Bool) {
            if hard { excluded.append(reason) } else { penalties.append(reason) }
        }
    }

    private func tagged(_ lines: [Line], with tags: [FoodTag]) -> [(Line, FoodTag)] {
        lines.flatMap { line in
            tags.filter { line.food?.tags.contains($0) == true }.map { (line, $0) }
        }
    }

    private func applyTagRule(_ tags: [FoodTag], rule: String, hard: Bool, lines: [Line], to findings: inout Findings) {
        guard !tags.isEmpty else { return }
        for line in lines {
            guard let food = line.food else {
                if hard { findings.uncertain.append("\(rule): no food data for \(line.name)") }
                continue
            }
            for tag in tags where food.tags.contains(tag) {
                findings.add("\(rule): contains \(tag.readableName) (\(line.name))", hard: hard)
            }
        }
    }

    private func applyTerms(
        _ terms: [String],
        label: (String) -> String,
        hard: Bool,
        lines: [Line],
        to findings: inout Findings
    ) {
        for line in lines {
            let texts = [line.ingredient.rawText] + (line.food.map { [$0.name] } ?? [])
            if let term = texts.lazy.compactMap({ TermMatcher.firstMatch(of: terms, in: $0) }).first {
                findings.add(label(term), hard: hard)
            }
        }
    }

    /// The intolerance name plus, when the name is a lexicon term ("lactose"), every term of that allergen.
    private func intoleranceTerms(_ name: String) -> [String] {
        let words = TermMatcher.words(name)
        let related = allergenEngine.lexicon.terms
            .filter { _, terms in terms.contains { TermMatcher.words($0) == words } }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .flatMap(\.value)
        return [name] + related
    }

    private func describe(_ reason: AllergenReason, lines: [Line]) -> String {
        let allergen = reason.allergen.readableName
        let place = reason.ingredientID.flatMap { id in lines.first { $0.ingredient.id == id }?.name } ?? "recipe"
        switch reason.evidence {
        case .lexicon(let term): return "Contains \(allergen) (\(term))"
        case .dataTag(.contains): return "Contains \(allergen) (\(place))"
        case .dataTag(.mayContain): return "May contain \(allergen) (\(place))"
        case .dataTag(.unknown): return "No \(allergen) data (\(place))"
        case .dataTag(.verifiedFree): return "Free of \(allergen) (\(place))"
        }
    }
}

extension DietPattern {
    var excludedTags: [FoodTag] {
        switch self {
        case .vegan: [.meat, .pork, .beef, .poultry, .fish, .shellfish, .egg, .dairy, .honey]
        case .vegetarian: [.meat, .pork, .beef, .poultry, .fish, .shellfish]
        case .pescatarian: [.meat, .pork, .beef, .poultry]
        case .mediterranean, .dash: []
        }
    }

    var readableName: String {
        switch self {
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .pescatarian: "Pescatarian"
        case .mediterranean: "Mediterranean"
        case .dash: "DASH"
        }
    }
}

extension ReligiousRule {
    /// Tags the rule excludes; Jain also excludes honey and alcohol, and root vegetables by name.
    var excludedTags: [FoodTag] {
        switch self {
        case .halal: [.pork, .alcohol]
        case .kosher: [.pork, .shellfish]
        case .noPork: [.pork]
        case .noBeef: [.beef]
        case .noAlcohol: [.alcohol]
        case .jain: [.meat, .pork, .beef, .poultry, .fish, .shellfish, .egg, .honey, .alcohol]
        }
    }

    var readableName: String {
        switch self {
        case .halal: "Halal"
        case .kosher: "Kosher"
        case .noPork: "No pork"
        case .noBeef: "No beef"
        case .noAlcohol: "No alcohol"
        case .jain: "Jain"
        }
    }
}

extension Array where Element: Hashable {
    fileprivate func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
