import Foundation
@testable import LarderCore

/// Builders for engine tests: foods, ingredient lines, constraints and profiles.
enum Kitchen {
    static func recipe(_ title: String = "Test dish", servings: Int = 2, id: RecipeID = RecipeID()) -> Recipe {
        Recipe(id: id, title: title, origin: .generated, servings: servings, prepMinutes: 10, cookMinutes: 20)
    }

    static func food(
        _ name: String,
        group: FoodGroup = .other,
        nutrients: Nutrients = Nutrients(),
        portions: [Portion] = [],
        allergens: [Allergen: AllergenPresence] = [:],
        density: Double? = nil,
        tags: Set<FoodTag> = []
    ) -> Food {
        Food(
            name: name,
            source: .seedApproximate,
            nutrientsPer100g: nutrients,
            portions: portions,
            foodGroup: group,
            allergens: AllergenTags(allergens),
            densityGPerMl: density,
            tags: tags
        )
    }

    /// A food that is verified free of every allergen.
    static func safeFood(_ name: String, group: FoodGroup = .other, tags: Set<FoodTag> = []) -> Food {
        food(name, group: group, allergens: Dictionary(uniqueKeysWithValues: Allergen.allCases.map { ($0, .verifiedFree) }), tags: tags)
    }

    static func line(
        _ text: String,
        _ quantity: Double = 100,
        _ unit: UnitOfMeasure = .gram,
        food: Food? = nil,
        recipe: RecipeID = RecipeID(),
        grams: Double? = nil,
        optional: Bool = false,
        garnish: Bool = false
    ) -> Ingredient {
        Ingredient(
            recipeID: recipe,
            rawText: text,
            quantity: quantity,
            unit: unit,
            foodID: food?.id,
            gramsResolved: grams,
            isOptional: optional,
            isGarnish: garnish
        )
    }

    static func foods(_ list: Food...) -> [FoodID: Food] {
        Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    static func constraint(_ kind: ConstraintKind, _ strictness: Strictness = .hard, axis: ConstraintAxis = .medical) -> DietaryConstraint {
        DietaryConstraint(axis: axis, kind: kind, strictness: strictness, source: .user, lastConfirmed: Fixtures.date(2026, 10, 1))
    }

    static func profile(
        birthYear: Int = 1986,
        sex: Sex = .unspecified,
        heightCm: Double = 170,
        weightKg: Double? = nil,
        activity: ActivityLevel = .sedentary,
        goal: Goal = .maintain
    ) -> UserProfile {
        UserProfile(
            birthYear: birthYear,
            sex: sex,
            heightCm: heightCm,
            weightKg: weightKg,
            activityLevel: activity,
            goal: goal,
            householdSize: 1,
            currencyCode: "USD",
            maxCookMinutes: 30
        )
    }

    static func isClose(_ value: Double?, _ expected: Double, tolerance: Double = 1e-9) -> Bool {
        guard let value else { return false }
        return abs(value - expected) <= tolerance
    }
}
