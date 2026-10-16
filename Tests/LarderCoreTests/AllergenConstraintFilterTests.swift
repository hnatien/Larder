import Foundation
import Testing
@testable import LarderCore

struct AllergenConstraintFilterTests {
    let filter = ConstraintFilter()

    private func verdict(_ foods: [Food], _ constraints: [DietaryConstraint], extraLines: [Ingredient] = []) -> FilterVerdict {
        let lines = foods.map { Kitchen.line($0.name.lowercased(), food: $0) } + extraLines
        let foodMap = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
        return filter.verdict(recipe: Kitchen.recipe("Test dish"), ingredients: lines, foods: foodMap, constraints: constraints)
    }

    private func isExcluded(_ verdict: FilterVerdict) -> Bool {
        if case .excluded = verdict { true } else { false }
    }

    @Test(arguments: [
        (DietPattern.vegan, FoodTag.honey, true),
        (.vegan, .dairy, true),
        (.vegan, .egg, true),
        (.vegetarian, .fish, true),
        (.vegetarian, .poultry, true),
        (.vegetarian, .egg, false),
        (.vegetarian, .dairy, false),
        (.pescatarian, .poultry, true),
        (.pescatarian, .beef, true),
        (.pescatarian, .fish, false),
        (.pescatarian, .shellfish, false),
        (.mediterranean, .pork, false),
        (.dash, .beef, false),
    ])
    func dietPatternsExcludeTheirTags(pattern: DietPattern, tag: FoodTag, excluded: Bool) {
        let food = Kitchen.safeFood("Item", tags: [tag])

        let result = verdict([food], [Kitchen.constraint(.diet(pattern), axis: .ethical)])

        #expect(isExcluded(result) == excluded)
        if !excluded { #expect(result == .pass(softPenalties: [])) }
    }

    @Test(arguments: [
        (ReligiousRule.halal, FoodTag.pork, true),
        (.halal, .alcohol, true),
        (.halal, .beef, false),
        (.kosher, .pork, true),
        (.kosher, .shellfish, true),
        (.kosher, .fish, false),
        (.noPork, .pork, true),
        (.noPork, .alcohol, false),
        (.noBeef, .beef, true),
        (.noBeef, .pork, false),
        (.noAlcohol, .alcohol, true),
        (.noAlcohol, .pork, false),
        (.jain, .egg, true),
        (.jain, .fish, true),
        (.jain, .meat, true),
        (.jain, .dairy, false),
    ])
    func religiousRulesExcludeTheirTags(rule: ReligiousRule, tag: FoodTag, excluded: Bool) {
        let food = Kitchen.safeFood("Item", tags: [tag])

        let result = verdict([food], [Kitchen.constraint(.religious(rule), axis: .religious)])

        #expect(isExcluded(result) == excluded)
    }

    @Test func excludedReasonNamesRuleTagAndFood() {
        let bacon = Kitchen.safeFood("Smoked bacon", tags: [.pork, .meat])

        let result = verdict([bacon], [Kitchen.constraint(.religious(.halal), axis: .religious)])

        #expect(result == .excluded(reasons: ["Halal: contains pork (Smoked bacon)"]))
    }

    @Test(arguments: ["Onion", "Garlic", "Potato", "Carrots", "Red onions"])
    func jainExcludesRootVegetablesByName(name: String) {
        let vegetable = Kitchen.safeFood(name, group: .produce)

        let result = verdict([vegetable], [Kitchen.constraint(.religious(.jain), axis: .religious)])

        #expect(isExcluded(result))
    }

    @Test func jainPassesNonRootProduce() {
        let spinach = Kitchen.safeFood("Spinach", group: .produce)

        #expect(verdict([spinach], [Kitchen.constraint(.religious(.jain), axis: .religious)]) == .pass(softPenalties: []))
    }

    @Test func softDietRuleAddsPenaltyInsteadOfExcluding() {
        let chicken = Kitchen.safeFood("Chicken thigh", tags: [.poultry, .meat])

        let result = verdict([chicken], [Kitchen.constraint(.diet(.vegetarian), .soft, axis: .preference)])

        #expect(result == .pass(softPenalties: [
            "Vegetarian: contains meat (Chicken thigh)", "Vegetarian: contains poultry (Chicken thigh)",
        ]))
    }

    @Test func hardDietWithUnmatchedIngredientIsUncertain() {
        let result = verdict([], [Kitchen.constraint(.diet(.vegan), axis: .ethical)], extraLines: [Kitchen.line("stock cube")])

        #expect(result == .uncertain(reasons: ["Vegan: no food data for stock cube"]))
    }

    @Test func intoleranceMatchesRelatedLexiconTerms() {
        let cream = Kitchen.safeFood("Double cream")

        #expect(verdict([cream], [Kitchen.constraint(.intolerance("lactose"))])
            == .excluded(reasons: ["Contains cream (lactose intolerance)"]))
        #expect(verdict([cream], [Kitchen.constraint(.intolerance("lactose"), .soft)])
            == .pass(softPenalties: ["Contains cream (lactose intolerance)"]))
    }

    @Test func intoleranceMatchesItsOwnWordOnly() {
        let shallot = Kitchen.safeFood("Shallots")
        let garlic = Kitchen.safeFood("Garlic")

        #expect(isExcluded(verdict([garlic], [Kitchen.constraint(.intolerance("garlic"))])))
        #expect(verdict([shallot], [Kitchen.constraint(.intolerance("garlic"))]) == .pass(softPenalties: []))
    }

    @Test func dislikedFoodByIdentifierExcludesWhenHardPenalisesWhenSoft() {
        let coriander = Kitchen.safeFood("Coriander")

        #expect(verdict([coriander], [Kitchen.constraint(.dislike(.food(coriander.id)), axis: .preference)])
            == .excluded(reasons: ["Contains a disliked food (Coriander)"]))
        #expect(verdict([coriander], [Kitchen.constraint(.dislike(.food(coriander.id)), .soft, axis: .preference)])
            == .pass(softPenalties: ["Contains a disliked food (Coriander)"]))
    }

    @Test func dislikedNameMatchesWholeWords() {
        let olives = Kitchen.safeFood("Black olives")
        let oil = Kitchen.safeFood("Olive oil")
        let constraint = Kitchen.constraint(.dislike(.name("olive")), axis: .preference)

        #expect(isExcluded(verdict([olives], [constraint])))
        #expect(isExcluded(verdict([oil], [constraint])))
        #expect(verdict([Kitchen.safeFood("Oliver's bread")], [constraint]) == .pass(softPenalties: []))
    }

    @Test func coeliacActsAsHardGlutenAndWheatAllergen() {
        let seitan = Kitchen.food("Seitan", allergens: [.gluten: .unknown, .wheat: .unknown])
        let unlabelled = Kitchen.food("Stock powder")
        let rice = Kitchen.food("Rice", allergens: [.gluten: .verifiedFree, .wheat: .verifiedFree])
        let coeliac = Kitchen.constraint(.medical(.coeliacDisease), .soft)

        #expect(verdict([seitan], [coeliac]) == .excluded(reasons: ["Contains wheat (seitan)", "Contains gluten (seitan)"]))
        #expect(verdict([unlabelled], [coeliac]) == .uncertain(reasons: ["No wheat data (Stock powder)", "No gluten data (Stock powder)"]))
        #expect(verdict([rice], [coeliac]) == .pass(softPenalties: []))
    }

    @Test func allergenReasonsAreReadable() {
        let granola = Kitchen.food("Granola", allergens: [.peanut: .mayContain])

        #expect(verdict([granola], [Kitchen.constraint(.allergen(.peanut))]) == .uncertain(reasons: ["May contain peanuts (Granola)"]))
        #expect(verdict([], [Kitchen.constraint(.allergen(.sesame))], extraLines: [Kitchen.line("tahini dressing")])
            == .excluded(reasons: ["Contains sesame (tahini)"]))
    }

    @Test func pregnancyMarksRawFishAndUnpasteurisedUncertain() {
        let sashimi = Kitchen.safeFood("Salmon sashimi", tags: [.fish, .rawFish])
        let brie = Kitchen.safeFood("Raw milk brie", tags: [.dairy, .unpasteurised])

        let result = verdict([sashimi, brie], [Kitchen.constraint(.medical(.pregnancy))])

        #expect(result == .uncertain(reasons: [
            "Contains raw fish (Salmon sashimi), flagged for pregnancy",
            "Contains unpasteurised food (Raw milk brie), flagged for pregnancy",
        ]))
    }

    @Test func hypertensionAddsSoftPenaltyForHighSodium() {
        let soySauce = Kitchen.safeFood("Light sauce", tags: [.highSodium])
        let rice = Kitchen.safeFood("Rice")

        #expect(verdict([soySauce, rice], [Kitchen.constraint(.medical(.hypertension))])
            == .pass(softPenalties: ["High in sodium (Light sauce)"]))
        #expect(verdict([rice], [Kitchen.constraint(.medical(.hypertension))]) == .pass(softPenalties: []))
    }

    @Test func exclusionWinsOverUncertaintyAndPenalties() {
        let pork = Kitchen.safeFood("Pork belly", tags: [.pork])
        let raw = Kitchen.safeFood("Tuna tartare", tags: [.rawFish])

        let result = verdict([pork, raw], [
            Kitchen.constraint(.religious(.noPork), axis: .religious),
            Kitchen.constraint(.medical(.pregnancy)),
        ])

        #expect(result == .excluded(reasons: ["No pork: contains pork (Pork belly)"]))
    }

    @Test func reasonsHaveNoExclamationMarks() {
        let foods = [
            Kitchen.food("Tahini", allergens: [.sesame: .contains]),
            Kitchen.safeFood("Bacon", tags: [.pork, .meat, .highSodium]),
            Kitchen.safeFood("Oysters", tags: [.shellfish, .rawFish]),
        ]
        let constraints = [
            Kitchen.constraint(.allergen(.sesame), .soft),
            Kitchen.constraint(.diet(.vegan), .soft),
            Kitchen.constraint(.medical(.pregnancy)),
            Kitchen.constraint(.medical(.hypertension)),
        ]

        let texts: [String] = switch verdict(foods, constraints) {
        case .pass(let penalties): penalties
        case .excluded(let reasons), .uncertain(let reasons): reasons
        }

        #expect(!texts.isEmpty)
        #expect(texts.allSatisfy { !$0.contains("!") })
    }
}
