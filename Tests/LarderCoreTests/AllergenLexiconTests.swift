import Foundation
import Testing
@testable import LarderCore

struct AllergenLexiconTests {
    let lexicon = AllergenLexicon.standard

    @Test func everyAllergenHasTermsAndOnlyNarrowOnesHaveFewerThanFive() {
        for allergen in Allergen.allCases {
            #expect(!(lexicon.terms[allergen] ?? []).isEmpty, "\(allergen) has no terms")
        }
        let short = Allergen.allCases.filter { (lexicon.terms[$0] ?? []).count < 5 }
        #expect(Set(short) == [.celery, .mustard, .lupin])
    }

    @Test(arguments: [
        (Allergen.sesame, "Halva crumble", "halva"),
        (.sesame, "Benne wafers", "benne"),
        (.milk, "1 tbsp ghee", "ghee"),
        (.milk, "Paneer cubes", "paneer"),
        (.milk, "Greek YOGHURT", "yoghurt"),
        (.egg, "Meringue nests", "meringue"),
        (.egg, "Egg albumen", "albumen"),
        (.wheat, "Bulgur wheat salad", "bulgur"),
        (.wheat, "Fine semolina", "semolina"),
        (.gluten, "Pearl barley", "barley"),
        (.gluten, "Malt vinegar", "malt"),
        (.soy, "Silken tofu", "tofu"),
        (.soy, "Shoyu ramen base", "shoyu"),
        (.treeNut, "Brazil nuts, chopped", "brazil nut"),
        (.treeNut, "Marzipan", "marzipan"),
        (.peanut, "Roasted groundnuts", "groundnut"),
        (.fish, "Worcestershire sauce", "worcestershire"),
        (.fish, "2 anchovies", "anchovy"),
        (.crustacean, "King prawns", "prawn"),
        (.crustacean, "Langoustine tails", "langoustine"),
        (.mollusc, "Fresh mussels", "mussel"),
        (.mollusc, "Squid rings", "squid"),
        (.celery, "Celeriac mash", "celeriac"),
        (.mustard, "Dijon", "dijon"),
        (.lupin, "Lupini beans", "lupini"),
        (.sulphites, "Dried apricots", "dried apricot"),
        (.sulphites, "Splash of white wine", "wine"),
        (.sesame, "Za'atar", "zaatar"),
    ])
    func derivativesMatchCaseInsensitively(allergen: Allergen, text: String, term: String) {
        #expect(lexicon.match(in: text, for: allergen) == term)
    }

    @Test(arguments: [
        (Allergen.peanut, "Peanutless spread"),
        (.egg, "Roasted eggplant"),
        (.fish, "Shellfishless broth"),
        (.milk, "Buttercup squash"),
        (.gluten, "Gluten-free pasta"),
        (.treeNut, "Nut free granola"),
        (.wheat, "Buckwheat noodles"),
    ])
    func noMatchInsideLongerWordsOrFreeClaims(allergen: Allergen, text: String) {
        #expect(lexicon.match(in: text, for: allergen) == nil)
    }

    @Test func diacriticsAreFolded() {
        #expect(lexicon.match(in: "Crème fraîche", for: .milk) == "creme fraiche")
    }

    @Test func customLexiconReplacesTerms() {
        let custom = AllergenLexicon(terms: [.sesame: ["gingelly"]])

        #expect(custom.match(in: "gingelly oil", for: .sesame) == "gingelly")
        #expect(custom.match(in: "tahini", for: .sesame) == nil)
        #expect(custom.match(in: "milk", for: .milk) == nil)
    }

    @Test(arguments: [
        (Allergen.milk, "coconut milk"), (.milk, "coconut cream"), (.milk, "coconut butter"), (.milk, "almond milk"),
        (.milk, "oat milk"), (.milk, "rice milk"), (.milk, "cashew milk"), (.milk, "soy milk"), (.milk, "peanut butter"),
        (.milk, "almond butter"), (.milk, "cocoa butter"), (.milk, "shea butter"), (.milk, "butternut"),
        (.milk, "milk thistle"), (.treeNut, "coconut"), (.treeNut, "coconut milk"), (.treeNut, "coconut oil"),
        (.treeNut, "nutmeg"), (.treeNut, "butternut"), (.treeNut, "water chestnut"), (.treeNut, "chestnut mushroom"),
        (.treeNut, "donut"), (.treeNut, "doughnut"), (.treeNut, "peanut"), (.mollusc, "oyster mushroom"),
        (.egg, "eggplant"), (.wheat, "buckwheat"), (.wheat, "wheatgrass"), (.gluten, "buckwheat"), (.gluten, "wheatgrass"),
    ])
    func exceptionPhrasesDoNotHit(allergen: Allergen, phrase: String) {
        #expect(lexicon.exceptions[allergen]?.contains(phrase) == true, "\(phrase) is not listed for \(allergen)")
        #expect(lexicon.match(in: "200 ml \(phrase)", for: allergen) == nil)
    }

    @Test func coconutMilkDoesNotHitMilk() {
        #expect(lexicon.match(in: "1 tin full-fat Coconut Milk", for: .milk) == nil)
        #expect(lexicon.match(in: "1 tin coconut milk", for: .treeNut) == nil)
    }

    @Test(arguments: [
        (Allergen.mollusc, "2 tbsp oyster sauce", "oyster"),
        (.milk, "250 ml buttermilk", "buttermilk"),
        (.egg, "200 g egg noodles", "egg"),
        (.fish, "1 tbsp fish sauce", "fish"),
    ])
    func compoundsThatContainTheAllergenStillHit(allergen: Allergen, text: String, term: String) {
        #expect(lexicon.match(in: text, for: allergen) == term)
    }

    @Test func peanutButterAndMilkHitsMilk() {
        #expect(lexicon.match(in: "peanut butter and milk", for: .milk) == "milk")
        #expect(lexicon.match(in: "peanut butter and butter", for: .milk) == "butter")
    }

    @Test func exceptionPluralsAreSuppressedToo() {
        #expect(lexicon.match(in: "Oyster mushrooms, torn", for: .mollusc) == nil)
        #expect(lexicon.match(in: "Oyster mushrooms and oysters", for: .mollusc) == "oyster")
    }

    @Test func exceptionsOnlyApplyToTheirOwnAllergen() {
        #expect(lexicon.match(in: "peanut butter", for: .peanut) == "peanut")
        #expect(lexicon.match(in: "almond milk", for: .treeNut) == "almond")
        #expect(lexicon.match(in: "soy milk", for: .soy) == "soy")
    }

    @Test func customLexiconUsesOnlyItsOwnExceptions() {
        let custom = AllergenLexicon(terms: [.milk: ["butter"]], exceptions: [.milk: ["apple butter"]])

        #expect(custom.match(in: "apple butter", for: .milk) == nil)
        #expect(custom.match(in: "peanut butter", for: .milk) == "butter")
        #expect(AllergenLexicon(terms: [.milk: ["butter"]]).match(in: "apple butter", for: .milk) == "butter")
    }
}
