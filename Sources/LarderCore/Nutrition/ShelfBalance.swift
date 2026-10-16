import Foundation

/// Where a food group sits against its comfortable range. Deliberately not a number.
public enum BalanceLevel: String, CaseIterable, Hashable, Codable, Sendable {
    case light
    case comfortable
    case heavy
}

/// Food-group bands for a stretch of meals, without any numeric score.
public struct ShelfBalance: Hashable, Sendable {
    /// Band for each food group that has a comfortable range (every group except `.other`).
    public var levels: [FoodGroup: BalanceLevel]
    /// Groups below their range, in `FoodGroup` order.
    public var groupsLight: [FoodGroup]
    /// Groups above their range, in `FoodGroup` order.
    public var groupsHeavy: [FoodGroup]

    /// Creates a balance from per-group levels.
    public init(levels: [FoodGroup: BalanceLevel]) {
        self.levels = levels
        groupsLight = FoodGroup.allCases.filter { levels[$0] == .light }
        groupsHeavy = FoodGroup.allCases.filter { levels[$0] == .heavy }
    }
}

/// Computes shelf balance from grams per food group per 1,000 kcal.
public enum ShelfBalanceCalculator {
    /// Balance of `meals` over `days` days.
    ///
    /// Meal energy is `perServing.energyKcal` times `servings`. Only meals with known energy are used,
    /// so grams are never divided by energy they did not contribute. When no meal has energy data the
    /// grams of every meal are compared against the 2,000 kcal DGA reference intake for `days` days.
    /// Meals with fewer than one serving are ignored. No meals or no days gives an empty balance.
    public static func balance(
        meals: [(RecipeNutrition, servings: Int, groups: [FoodGroup: Double])],
        days: Int
    ) -> ShelfBalance {
        let eaten = meals.filter { $0.servings > 0 }
        guard !eaten.isEmpty, days > 0 else { return ShelfBalance(levels: [:]) }

        let withEnergy = eaten.compactMap { meal -> (kcal: Double, groups: [FoodGroup: Double])? in
            guard let kcal = meal.0.perServing.energyKcal, kcal.isFinite, kcal > 0 else { return nil }
            return (kcal * Double(meal.servings), meal.groups)
        }
        let counted: [[FoodGroup: Double]]
        let kcal: Double
        if withEnergy.isEmpty {
            counted = eaten.map(\.groups)
            kcal = NutrientTargets.referenceEnergyKcal * Double(days)
        } else {
            counted = withEnergy.map(\.groups)
            kcal = withEnergy.reduce(0) { $0 + $1.kcal }
        }

        var levels: [FoodGroup: BalanceLevel] = [:]
        for group in FoodGroup.allCases {
            guard let range = comfortableRange(for: group) else { continue }
            let grams = counted.reduce(0) { total, groups in
                let value = groups[group] ?? 0
                return value.isFinite && value > 0 ? total + value : total
            }
            let density = grams / (kcal / 1000)
            levels[group] = density < range.lowerBound ? .light : density > range.upperBound ? .heavy : .comfortable
        }
        return ShelfBalance(levels: levels)
    }

    /// Comfortable grams per 1,000 kcal, derived from HEI-2020 full-credit densities
    /// (docs/research/04 section 3); each upper bound is roughly twice the lower.
    ///
    /// - produce: fruit 0.8 + vegetables 1.1 = 1.9 cup-eq; at about 130 g per cup-eq that is 250 g.
    /// - grains: whole 1.5 + refined 1.8 = 3.3 oz-eq; at 28 g dry or bread weight per oz-eq about 90 g.
    /// - protein: total protein foods 2.5 oz-eq at 28 g cooked per oz-eq, 70 g; the 160 g ceiling allows raw weight (about 1.3 times cooked) at twice the floor.
    /// - dairy: 1.3 cup-eq; recipe dairy leans on cheese (1.5 oz = 1 cup-eq), so about 75 g per cup-eq gives 100 g; 300 g is about 1.2 cups of milk.
    /// - legumes: half of the 0.8 oz-eq seafood and plant protein, at 43 g cooked per oz-eq, about 20 g; 80 g is about half a cup cooked.
    /// - fats: the USDA pattern's oil allowance of about 14 g per 1,000 kcal; 45 g keeps added fat near 40 % of energy.
    static func comfortableRange(for group: FoodGroup) -> ClosedRange<Double>? {
        switch group {
        case .produce: 250...500
        case .grains: 90...180
        case .protein: 70...160
        case .dairy: 100...300
        case .legumes: 20...80
        case .fats: 15...45
        case .other: nil
        }
    }
}
