import Foundation

extension Nutrients {
    /// Adds two profiles nutrient by nutrient; a nutrient stays `nil` only when both sides are `nil`.
    public static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        var sum = lhs
        for keyPath in fields {
            switch (lhs[keyPath: keyPath], rhs[keyPath: keyPath]) {
            case let (left?, right?): sum[keyPath: keyPath] = left + right
            case let (nil, right?): sum[keyPath: keyPath] = right
            case (_, nil): break
            }
        }
        return sum
    }

    /// Multiplies every known nutrient by `factor`; unknown nutrients stay `nil`.
    public func scaled(by factor: Double) -> Nutrients {
        var result = self
        for keyPath in Self.fields {
            result[keyPath: keyPath] = self[keyPath: keyPath].map { $0 * factor }
        }
        return result
    }

    private static var fields: [WritableKeyPath<Nutrients, Double?>] {
        [
            \.energyKcal, \.proteinG, \.fatG, \.saturatedFatG, \.monounsaturatedFatG, \.polyunsaturatedFatG,
            \.carbohydrateG, \.fiberG, \.totalSugarG, \.addedSugarG, \.sodiumMg, \.potassiumMg, \.calciumMg,
            \.ironMg, \.vitaminDMcg, \.vitaminB12Mcg,
        ]
    }
}
