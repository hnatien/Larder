import Foundation
import Testing
@testable import LarderCore

struct AllergenEngineTests {
    let engine = AllergenEngine()

    private func verdict(
        _ lines: [Ingredient],
        foods: [FoodID: Food],
        _ constraints: [DietaryConstraint],
        title: String = "Test dish"
    ) -> AllergenVerdict {
        engine.evaluate(recipe: Kitchen.recipe(title), ingredients: lines, foods: foods, constraints: constraints)
    }

    @Test func unlabeledTahiniIsExcludedThroughLexicon() {
        let tahini = Kitchen.food("Tahini", allergens: [:])
        let line = Kitchen.line("2 tbsp tahini", food: tahini)

        let result = verdict([line], foods: Kitchen.foods(tahini), [Kitchen.constraint(.allergen(.sesame), axis: .medical)])

        #expect(tahini.allergens.presence(of: .sesame) == .unknown)
        #expect(result == .excluded([AllergenReason(allergen: .sesame, ingredientID: line.id, evidence: .lexicon(term: "tahini"))]))
    }

    @Test(arguments: Allergen.allCases)
    func hardAllergenWithUnknownPresenceAndNoLexiconHitIsUncertainNeverClear(allergen: Allergen) {
        let quinoa = Kitchen.food("Quinoa")
        let line = Kitchen.line("1 cup quinoa", food: quinoa)

        let result = verdict([line], foods: Kitchen.foods(quinoa), [Kitchen.constraint(.allergen(allergen))])

        #expect(!engine.textPath([line], foods: Kitchen.foods(quinoa), allergen: allergen))
        #expect(result == .uncertain([AllergenReason(allergen: allergen, ingredientID: line.id, evidence: .dataTag(.unknown))]))
    }

    @Test func mayContainUnderHardConstraintIsUncertain() {
        let granola = Kitchen.food("Granola", allergens: [.peanut: .mayContain])
        let line = Kitchen.line("granola", food: granola)

        let result = verdict([line], foods: Kitchen.foods(granola), [Kitchen.constraint(.allergen(.peanut))])

        #expect(result == .uncertain([AllergenReason(allergen: .peanut, ingredientID: line.id, evidence: .dataTag(.mayContain))]))
    }

    @Test func containsTagWithoutLexiconHitIsExcluded() {
        let sauce = Kitchen.food("House sauce", allergens: [.mustard: .contains])
        let line = Kitchen.line("house sauce", food: sauce)

        let result = verdict([line], foods: Kitchen.foods(sauce), [Kitchen.constraint(.allergen(.mustard))])

        #expect(result == .excluded([AllergenReason(allergen: .mustard, ingredientID: line.id, evidence: .dataTag(.contains))]))
    }

    @Test func softAllergenNeverExcludesOnlyUncertain() {
        let tahini = Kitchen.food("Tahini", allergens: [.sesame: .contains])
        let line = Kitchen.line("tahini", food: tahini)

        let result = verdict([line], foods: Kitchen.foods(tahini), [Kitchen.constraint(.allergen(.sesame), .soft, axis: .preference)])

        #expect(result == .uncertain([AllergenReason(allergen: .sesame, ingredientID: line.id, evidence: .lexicon(term: "tahini"))]))
    }

    @Test func softAllergenVerifiedFreeIsClear() {
        let rice = Kitchen.safeFood("Rice")

        let result = verdict([Kitchen.line("rice", food: rice)], foods: Kitchen.foods(rice), [Kitchen.constraint(.allergen(.sesame), .soft)])

        #expect(result == .clear)
    }

    @Test func verifiedFreeWithoutLexiconHitIsClear() {
        let rice = Kitchen.safeFood("Rice")
        let beans = Kitchen.safeFood("Black beans")
        let lines = [Kitchen.line("rice", food: rice), Kitchen.line("black beans", food: beans)]

        let result = verdict(lines, foods: Kitchen.foods(rice, beans), Allergen.allCases.map { Kitchen.constraint(.allergen($0)) })

        #expect(result == .clear)
    }

    @Test func lexiconHitOverridesVerifiedFreeTag() {
        let mislabelled = Kitchen.safeFood("Sesame paste")
        let line = Kitchen.line("sesame paste", food: mislabelled)

        let result = verdict([line], foods: Kitchen.foods(mislabelled), [Kitchen.constraint(.allergen(.sesame))])

        #expect(result == .excluded([AllergenReason(allergen: .sesame, ingredientID: line.id, evidence: .lexicon(term: "sesame"))]))
    }

    @Test func wholeWordMatchingIgnoresLongerWords() {
        let spread = Kitchen.safeFood("Peanutless spread")
        let line = Kitchen.line("2 tbsp peanutless spread", food: spread)

        let result = verdict([line], foods: Kitchen.foods(spread), [Kitchen.constraint(.allergen(.peanut))])

        #expect(result == .clear)
        #expect(!engine.textPath([line], foods: Kitchen.foods(spread), allergen: .peanut))
    }

    @Test func guessedMatchTaggedFreeIsUncertainNeverClear() {
        let chicken = Kitchen.safeFood("Chicken, raw")
        var line = Kitchen.line("400 g chicken nuggets", food: chicken)
        line.matchConfidence = 0.5

        let result = verdict([line], foods: Kitchen.foods(chicken), [Kitchen.constraint(.allergen(.wheat))])

        #expect(engine.dataPath([line], foods: Kitchen.foods(chicken), allergen: .wheat) == .unknown)
        #expect(result == .uncertain([AllergenReason(allergen: .wheat, ingredientID: line.id, evidence: .dataTag(.unknown))]))
    }

    @Test func guessedMatchStillExcludesOnAContainsTag() {
        let sauce = Kitchen.food("House sauce", allergens: [.mustard: .contains])
        var line = Kitchen.line("house sauce, to serve", food: sauce)
        line.matchConfidence = 0.5

        let result = verdict([line], foods: Kitchen.foods(sauce), [Kitchen.constraint(.allergen(.mustard))])

        #expect(result == .excluded([AllergenReason(allergen: .mustard, ingredientID: line.id, evidence: .dataTag(.contains))]))
    }

    @Test func missingFoodRecordIsUnknown() {
        let ghost = Kitchen.food("Not in the database")
        let line = Kitchen.line("mystery mix", food: ghost)

        #expect(engine.dataPath([line], foods: [:], allergen: .egg) == .unknown)
        #expect(verdict([line], foods: [:], [Kitchen.constraint(.allergen(.egg))])
            == .uncertain([AllergenReason(allergen: .egg, ingredientID: line.id, evidence: .dataTag(.unknown))]))
    }

    @Test func unmatchedTextIsStillCheckedByLexicon() {
        let line = Kitchen.line("1 tbsp toasted sesame seeds")

        let result = verdict([line], foods: [:], [Kitchen.constraint(.allergen(.sesame))])

        #expect(result == .excluded([AllergenReason(allergen: .sesame, ingredientID: line.id, evidence: .lexicon(term: "sesame"))]))
    }

    @Test func emptyRecipeIsUncertainNotClear() {
        let result = verdict([], foods: [:], [Kitchen.constraint(.allergen(.milk))])

        #expect(engine.dataPath([], foods: [:], allergen: .milk) == .unknown)
        #expect(result == .uncertain([AllergenReason(allergen: .milk, ingredientID: nil, evidence: .dataTag(.unknown))]))
    }

    @Test func dataPathReturnsWorstPresence() {
        let free = Kitchen.food("A", allergens: [.soy: .verifiedFree])
        let may = Kitchen.food("B", allergens: [.soy: .mayContain])
        let contains = Kitchen.food("C", allergens: [.soy: .contains])
        let foods = Kitchen.foods(free, may, contains)

        #expect(engine.dataPath([Kitchen.line("a", food: free)], foods: foods, allergen: .soy) == .verifiedFree)
        #expect(engine.dataPath([Kitchen.line("a", food: free), Kitchen.line("b", food: may)], foods: foods, allergen: .soy) == .mayContain)
        #expect(engine.dataPath(
            [Kitchen.line("a", food: free), Kitchen.line("c", food: contains), Kitchen.line("b", food: may)], foods: foods, allergen: .soy
        ) == .contains)
    }

    @Test func textPathChecksFoodNameAsWellAsRawText() {
        let paste = Kitchen.safeFood("Miso paste")
        let line = Kitchen.line("2 tbsp paste", food: paste)

        #expect(engine.textPath([line], foods: Kitchen.foods(paste), allergen: .soy))
        #expect(!engine.textPath([line], foods: [:], allergen: .soy))
    }

    @Test func garnishIsChecked() {
        let line = Kitchen.line("sesame seeds to serve", 5, garnish: true)

        let result = verdict([line], foods: [:], [Kitchen.constraint(.allergen(.sesame))])

        #expect(result == .excluded([AllergenReason(allergen: .sesame, ingredientID: line.id, evidence: .lexicon(term: "sesame"))]))
    }

    @Test func recipeTitleIsCheckedByLexicon() {
        let noodles = Kitchen.safeFood("Rice noodles")

        let result = verdict([Kitchen.line("noodles", food: noodles)], foods: Kitchen.foods(noodles), [Kitchen.constraint(.allergen(.peanut))], title: "Chicken satay")

        #expect(result == .excluded([AllergenReason(allergen: .peanut, ingredientID: nil, evidence: .lexicon(term: "satay"))]))
    }

    @Test func hardWinsWhenAllergenIsListedHardAndSoft() {
        let line = Kitchen.line("tahini")

        let result = verdict([line], foods: [:], [
            Kitchen.constraint(.allergen(.sesame), .soft),
            Kitchen.constraint(.allergen(.sesame), .hard),
        ])

        #expect(result == .excluded([AllergenReason(allergen: .sesame, ingredientID: line.id, evidence: .lexicon(term: "tahini"))]))
    }

    @Test func nonAllergenConstraintsAreIgnoredByEngine() {
        let result = verdict([Kitchen.line("bacon")], foods: [:], [Kitchen.constraint(.diet(.vegan))])

        #expect(result == .clear)
    }

    @Test func coconutMilkAndWholeMilkHitsMilkOnce() {
        let line = Kitchen.line("coconut milk, whole milk")

        let result = verdict([line], foods: [:], [Kitchen.constraint(.allergen(.milk))])

        #expect(result == .excluded([AllergenReason(allergen: .milk, ingredientID: line.id, evidence: .lexicon(term: "milk"))]))
    }

    @Test func exceptionsDoNotClearTheDataPath() {
        let coconutMilk = Kitchen.food("Coconut milk", allergens: [.milk: .contains])
        let line = Kitchen.line("coconut milk", food: coconutMilk)

        let result = verdict([line], foods: Kitchen.foods(coconutMilk), [Kitchen.constraint(.allergen(.milk))])

        #expect(!engine.textPath([line], foods: Kitchen.foods(coconutMilk), allergen: .milk))
        #expect(engine.dataPath([line], foods: Kitchen.foods(coconutMilk), allergen: .milk) == .contains)
        #expect(result == .excluded([AllergenReason(allergen: .milk, ingredientID: line.id, evidence: .dataTag(.contains))]))
    }

    @Test func exceptionInTheTitleIsClearWhenTheDataIsClear() {
        let coconutMilk = Kitchen.safeFood("Coconut milk")
        let line = Kitchen.line("400 ml coconut milk", food: coconutMilk)

        let result = verdict([line], foods: Kitchen.foods(coconutMilk), [Kitchen.constraint(.allergen(.milk))], title: "Coconut milk dal")

        #expect(result == .clear)
    }
}
