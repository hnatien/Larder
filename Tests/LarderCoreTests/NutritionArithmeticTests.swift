import Foundation
import Testing
@testable import LarderCore

struct NutritionArithmeticTests {
    @Test func additionKeepsNilOnlyWhenBothSidesAreNil() {
        let left = Nutrients(energyKcal: 100, proteinG: nil, fatG: 2)
        let right = Nutrients(energyKcal: 50, proteinG: 4, fatG: nil)

        let sum = left + right

        #expect(sum.energyKcal == 150)
        #expect(sum.proteinG == 4)
        #expect(sum.fatG == 2)
        #expect(sum.sodiumMg == nil)
        #expect(sum.vitaminB12Mcg == nil)
    }

    @Test func additionCoversEveryNutrient() {
        let one = Nutrients(
            energyKcal: 1, proteinG: 1, fatG: 1, saturatedFatG: 1, monounsaturatedFatG: 1, polyunsaturatedFatG: 1,
            carbohydrateG: 1, fiberG: 1, totalSugarG: 1, addedSugarG: 1, sodiumMg: 1, potassiumMg: 1, calciumMg: 1,
            ironMg: 1, vitaminDMcg: 1, vitaminB12Mcg: 1
        )
        let two = Nutrients(
            energyKcal: 2, proteinG: 2, fatG: 2, saturatedFatG: 2, monounsaturatedFatG: 2, polyunsaturatedFatG: 2,
            carbohydrateG: 2, fiberG: 2, totalSugarG: 2, addedSugarG: 2, sodiumMg: 2, potassiumMg: 2, calciumMg: 2,
            ironMg: 2, vitaminDMcg: 2, vitaminB12Mcg: 2
        )

        #expect(one + one == two)
        #expect(one.scaled(by: 2) == two)
    }

    @Test func scalingLeavesUnknownsUnknown() {
        let nutrients = Nutrients(energyKcal: 200, sodiumMg: nil)

        let half = nutrients.scaled(by: 0.5)

        #expect(half.energyKcal == 100)
        #expect(half.sodiumMg == nil)
    }
}
