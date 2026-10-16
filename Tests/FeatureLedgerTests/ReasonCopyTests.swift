import Foundation
import LarderCore
import Testing
@testable import FeatureLedger

@Suite struct ReasonCopyTests {
    let lookup = ReasonCopy.Lookup(
        foodNames: [Fixtures.spinach.id: Fixtures.spinach.name],
        locale: Fixtures.locale,
        calendar: Fixtures.calendar
    )
    /// Thursday 22 October 2026.
    let thursday = Fixtures.date(2026, 10, 22, hour: 9)

    @Test func usesExpiringNamesTheFoodAndTheWeekday() {
        let line = ReasonCopy.line(for: .usesExpiring(food: Fixtures.spinach.id, bestBy: thursday), lookup: lookup)
        #expect(line == "Uses the spinach before Thursday")
    }

    @Test func usesExpiringWithoutAKnownFoodStillGivesTheDay() {
        let line = ReasonCopy.line(for: .usesExpiring(food: FoodID(), bestBy: thursday), lookup: lookup)
        #expect(line == "Uses what's best by Thursday")
    }

    @Test func usesExpiringWithABlankNameFallsBack() {
        var blank = lookup
        blank.foodNames = [Fixtures.spinach.id: "  "]
        let line = ReasonCopy.line(for: .usesExpiring(food: Fixtures.spinach.id, bestBy: thursday), lookup: blank)
        #expect(line == "Uses what's best by Thursday")
    }

    @Test func pantryOverlapCountsThings() {
        #expect(ReasonCopy.line(for: .pantryOverlap(count: 4), lookup: lookup) == "Uses 4 things you have")
    }

    @Test func quickGivesMinutes() {
        #expect(ReasonCopy.line(for: .quick(minutes: 20), lookup: lookup) == "On the table in 20 minutes")
    }

    @Test func varietyCuisine() {
        #expect(ReasonCopy.line(for: .varietyCuisine(cuisine: "Korean"), lookup: lookup) == "Something different from this week")
    }

    @Test func leftoverOfNamesTheCookDay() {
        let source = PlannedMealID()
        var withMeal = lookup
        withMeal.mealDates = [source: Fixtures.date(2026, 10, 20)]
        #expect(ReasonCopy.line(for: .leftoverOf(meal: source), lookup: withMeal) == "Leftovers from Tuesday")
    }

    @Test func leftoverOfAnUnknownMealStaysVague() {
        #expect(ReasonCopy.line(for: .leftoverOf(meal: PlannedMealID()), lookup: lookup) == "Leftovers from earlier this week")
    }

    @Test func underBudget() {
        #expect(ReasonCopy.line(for: .underBudget, lookup: lookup) == "Easy on the budget")
    }

    @Test func fibreGap() {
        #expect(ReasonCopy.line(for: .fibreGap(gramsShort: 12), lookup: lookup) == "Adds the fibre this week is short of")
    }

    @Test func linesKeepOrderAndRespectTheLimit() {
        let codes: [ReasonCode] = [.quick(minutes: 15), .underBudget, .pantryOverlap(count: 3)]
        #expect(ReasonCopy.lines(for: codes, lookup: lookup, limit: 2) == ["On the table in 15 minutes", "Easy on the budget"])
        #expect(ReasonCopy.lines(for: codes, lookup: lookup, limit: 0).isEmpty)
        #expect(ReasonCopy.lines(for: [], lookup: lookup).isEmpty)
    }

    @Test func displayNameDropsTheDescriptor() {
        #expect(ReasonCopy.displayName("Spinach, raw") == "spinach")
        #expect(ReasonCopy.displayName("Olive oil") == "olive oil")
    }
}

@Suite struct BalanceCopyTests {
    @Test func lightGroupLeadsTheSentence() {
        let balance = ShelfBalance(levels: [.produce: .light, .dairy: .heavy, .grains: .comfortable])
        #expect(LedgerCopy.balanceSentence(for: balance) == "Light on produce this week. A handful in two dinners would do it.")
    }

    @Test func heavyGroupWhenNothingIsLight() {
        let balance = ShelfBalance(levels: [.produce: .comfortable, .dairy: .heavy])
        #expect(LedgerCopy.balanceSentence(for: balance) == "Plenty of dairy this week. A swap or two would even it out.")
    }

    @Test func noSentenceWhenEverythingIsComfortable() {
        let balance = ShelfBalance(levels: [.produce: .comfortable, .grains: .comfortable])
        #expect(LedgerCopy.balanceSentence(for: balance) == nil)
        #expect(LedgerCopy.balanceSentence(for: ShelfBalance(levels: [:])) == nil)
    }

    @Test func averagesOnlyForTheFourShownNutrients() {
        let energy = NutrientNote(nutrient: .energy, totalPerDay: 2040.4, min: nil, max: nil, status: .within)
        let iron = NutrientNote(nutrient: .iron, totalPerDay: 9, min: nil, max: nil, status: .within)
        #expect(LedgerCopy.average(energy, locale: Fixtures.locale) == "Energy 2,040 kcal")
        #expect(LedgerCopy.average(iron, locale: Fixtures.locale) == nil)
    }
}
