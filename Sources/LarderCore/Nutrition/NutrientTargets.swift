import Foundation

/// Default nutrient targets from the Dietary Guidelines for Americans 2025-2030 and WHO guidance
/// (docs/research/04-nutrition-and-recommendation-engine.md, section 3).
public enum NutrientTargets {
    /// Targets for `profile` in `referenceYear`, each tagged with its source.
    ///
    /// With an eating-disorder history or a pregnancy there is no energy target at all, so no energy
    /// maximum exists either: research 04 section 3 says to avoid weight-loss targets for pregnancy and
    /// eating-disorder history, and an energy ceiling is one. Kidney disease and under-18s never get
    /// protein raised above the 0.8 g/kg RDA (same section).
    public static func defaults(
        for profile: UserProfile,
        constraints: [DietaryConstraint],
        referenceYear: Int
    ) -> [NutrientTarget] {
        let age = max(referenceYear - profile.birthYear, 0)
        let flags = Set(constraints.compactMap { constraint -> MedicalFlag? in
            if case .medical(let flag) = constraint.kind { flag } else { nil }
        })
        let weightKg = validWeight(profile)

        var targets: [NutrientTarget] = []
        if flags.isDisjoint(with: [.eatingDisorderHistory, .pregnancy]) {
            targets.append(energy(profile: profile, age: age, weightKg: weightKg))
        }
        targets.append(protein(weightKg: weightKg, capped: age < 18 || flags.contains(.chronicKidneyDisease)))
        targets.append(NutrientTarget(nutrient: .fiber, basis: .per1000kcal, target: 14, priority: 2, source: .dga2025))
        targets.append(sodium(age: age, whoLimit: profile.goal == .eatBetter && flags.contains(.hypertension)))
        targets.append(NutrientTarget(nutrient: .saturatedFat, basis: .percentEnergy, max: 10, priority: 2, source: .dga2025))
        // DGA 2025 sets no daily added-sugar amount (only 10 g per meal); the 10 % energy cap is WHO's free-sugars limit.
        targets.append(NutrientTarget(nutrient: .addedSugar, basis: .percentEnergy, max: 10, priority: 2, source: .who))
        targets.append(NutrientTarget(nutrient: .potassium, basis: .perDay, target: potassiumMg(profile.sex), priority: 1, source: .dga2025))
        return targets
    }

    /// Body weight used when the profile has none: 0.8 g/kg of it is the 50 g protein reference.
    static let referenceWeightKg = 62.5
    static let referenceEnergyKcal = 2000.0

    private static func validWeight(_ profile: UserProfile) -> Double? {
        guard let weight = profile.weightKg, weight.isFinite, weight > 0 else { return nil }
        return weight
    }

    /// Mifflin-St Jeor resting energy times the activity factor, within plus or minus 10 %; 2000 kcal without weight or height.
    private static func energy(profile: UserProfile, age: Int, weightKg: Double?) -> NutrientTarget {
        var kcal = referenceEnergyKcal
        if let weightKg, profile.heightCm.isFinite, profile.heightCm > 0 {
            let base = 10 * weightKg + 6.25 * profile.heightCm - 5 * Double(age)
            let sexTerm: Double = switch profile.sex {
            case .male: 5
            case .female: -161
            case .unspecified: (5 - 161) / 2
            }
            kcal = (base + sexTerm) * activityFactor(profile.activityLevel)
        }
        return NutrientTarget(
            nutrient: .energy, basis: .perDay, min: kcal * 0.9, target: kcal, max: kcal * 1.1, priority: 3, source: .dga2025
        )
    }

    private static func activityFactor(_ level: ActivityLevel) -> Double {
        switch level {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }

    /// 0.8 g/kg floor, 1.2 g/kg target and 1.6 g/kg ceiling; capped at 0.8 target and 1.0 ceiling when protein must not be raised.
    private static func protein(weightKg: Double?, capped: Bool) -> NutrientTarget {
        let kg = weightKg ?? referenceWeightKg
        return NutrientTarget(
            nutrient: .protein,
            basis: .perDay,
            min: 0.8 * kg,
            target: (capped ? 0.8 : 1.2) * kg,
            max: (capped ? 1.0 : 1.6) * kg,
            priority: 3,
            source: .dga2025
        )
    }

    /// DGA limits by age (1,200 / 1,500 / 1,800 / 2,300 mg); WHO's 2,000 mg replaces a higher limit when asked for.
    private static func sodium(age: Int, whoLimit: Bool) -> NutrientTarget {
        let dgaMax: Double = switch age {
        case ...3: 1200
        case 4...8: 1500
        case 9...13: 1800
        default: 2300
        }
        if whoLimit, dgaMax > 2000 {
            return NutrientTarget(nutrient: .sodium, basis: .perDay, max: 2000, priority: 4, source: .who)
        }
        return NutrientTarget(nutrient: .sodium, basis: .perDay, max: dgaMax, priority: 4, source: .dga2025)
    }

    private static func potassiumMg(_ sex: Sex) -> Double {
        switch sex {
        case .male: 3400
        case .female: 2600
        case .unspecified: 3000
        }
    }
}
