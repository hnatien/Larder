import Foundation
import Testing
@testable import LarderCore

struct NutritionShelfBalanceTests {
    /// A meal of `servings` servings at `kcalPerServing` each.
    private func meal(
        kcalPerServing: Double?,
        servings: Int = 2,
        groups: [FoodGroup: Double]
    ) -> (RecipeNutrition, servings: Int, groups: [FoodGroup: Double]) {
        let perServing = Nutrients(energyKcal: kcalPerServing)
        let nutrition = RecipeNutrition(perServing: perServing, perRecipe: perServing, coverage: 1, unresolved: [])
        return (nutrition, servings: servings, groups: groups)
    }

    @Test(arguments: [
        (FoodGroup.produce, 249.0, 250.0, 500.0, 501.0),
        (.grains, 89, 90, 180, 181),
        (.protein, 69, 70, 160, 161),
        (.dairy, 99, 100, 300, 301),
        (.legumes, 19, 20, 80, 81),
        (.fats, 14, 15, 45, 46),
    ])
    func levelsFollowComfortableRangePerThousandKcal(
        group: FoodGroup, light: Double, lowEdge: Double, highEdge: Double, heavy: Double
    ) {
        // 2 servings * 500 kcal = 1000 kcal, so grams equal grams per 1000 kcal
        func level(_ grams: Double) -> BalanceLevel? {
            ShelfBalanceCalculator.balance(meals: [meal(kcalPerServing: 500, groups: [group: grams])], days: 1).levels[group]
        }

        #expect(level(light) == .light)
        #expect(level(lowEdge) == .comfortable)
        #expect(level(highEdge) == .comfortable)
        #expect(level(heavy) == .heavy)
    }

    @Test func groupsLightAndHeavyListOutOfRangeGroups() {
        let meals = [
            meal(kcalPerServing: 500, groups: [.produce: 600, .grains: 120, .dairy: 50]),
            meal(kcalPerServing: 500, groups: [.produce: 400, .grains: 120, .protein: 200, .legumes: 60, .fats: 40]),
        ]

        // 2000 kcal: produce 500, grains 120, protein 100, dairy 25, legumes 30, fats 20 per 1000 kcal
        let balance = ShelfBalanceCalculator.balance(meals: meals, days: 1)

        #expect(balance.levels[.produce] == .comfortable)
        #expect(balance.levels[.protein] == .comfortable)
        #expect(balance.groupsLight == [.dairy])
        #expect(balance.groupsHeavy == [])
        #expect(balance.levels[.other] == nil)
    }

    @Test func missingGroupIsLight() {
        let balance = ShelfBalanceCalculator.balance(meals: [meal(kcalPerServing: 500, groups: [:])], days: 1)

        #expect(balance.groupsLight == [.produce, .grains, .protein, .dairy, .fats, .legumes])
    }

    @Test func mealsWithoutEnergyAreLeftOutWhenOthersHaveIt() {
        let meals = [
            meal(kcalPerServing: 500, groups: [.produce: 300]),
            meal(kcalPerServing: nil, groups: [.produce: 5000]),
        ]

        let balance = ShelfBalanceCalculator.balance(meals: meals, days: 1)

        #expect(balance.levels[.produce] == .comfortable)
    }

    @Test func noEnergyDataFallsBackToReferenceIntakePerDay() {
        // 3 days * 2000 kcal = 6000 kcal; 1800 g produce = 300 g per 1000 kcal
        let balance = ShelfBalanceCalculator.balance(meals: [meal(kcalPerServing: nil, groups: [.produce: 1800])], days: 3)

        #expect(balance.levels[.produce] == .comfortable)
    }

    @Test func emptyInputsGiveEmptyBalance() {
        #expect(ShelfBalanceCalculator.balance(meals: [], days: 7).levels.isEmpty)
        #expect(ShelfBalanceCalculator.balance(meals: [meal(kcalPerServing: 500, groups: [.produce: 300])], days: 0).levels.isEmpty)
        #expect(ShelfBalanceCalculator.balance(meals: [meal(kcalPerServing: 500, servings: 0, groups: [.produce: 300])], days: 1).levels.isEmpty)
    }
}
