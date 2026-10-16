import Foundation
import GRDB
import LarderCore
@testable import LarderPersistence

enum Fixtures {
    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) else {
            preconditionFailure("Invalid fixture date \(year)-\(month)-\(day)")
        }
        return date
    }

    static func food(_ name: String, id: FoodID = FoodID()) -> Food {
        Food(id: id, name: name, source: .seedApproximate, foodGroup: .other)
    }

    static let fullFood = Food(
        name: "Chickpeas, canned, drained",
        source: .srLegacy,
        fdcID: 173757,
        gtin: "0012345678905",
        nutrientsPer100g: Nutrients(
            energyKcal: 139, proteinG: 7.05, fatG: 2.77, saturatedFatG: 0.29, monounsaturatedFatG: 0.62,
            polyunsaturatedFatG: 1.2, carbohydrateG: 22.5, fiberG: 7.6, totalSugarG: 0.4, addedSugarG: 0,
            sodiumMg: 246, potassiumMg: 172, calciumMg: 45, ironMg: 1.3, vitaminDMcg: 0, vitaminB12Mcg: 0
        ),
        portions: [Portion(label: "1 cup", grams: 152), Portion(label: "1 can", grams: 240)],
        foodGroup: .legumes,
        allergens: AllergenTags([.sesame: .verifiedFree, .wheat: .mayContain, .soy: .contains, .milk: .unknown])
    )

    static func recipe(_ title: String, id: RecipeID = RecipeID()) -> Recipe {
        Recipe(id: id, title: title, origin: .userImport, servings: 2, prepMinutes: 5, cookMinutes: 10)
    }

    static func ingredient(_ text: String, recipeID: RecipeID, foodID: FoodID? = nil) -> Ingredient {
        Ingredient(recipeID: recipeID, rawText: text, quantity: 1, unit: .piece, foodID: foodID)
    }

    static func pantryItem(
        _ name: String,
        foodID: FoodID?,
        grams: Double,
        bestBy: Date?,
        addedOn: Date = date(2026, 10, 1)
    ) -> PantryItem {
        PantryItem(foodID: foodID, rawName: name, quantityGrams: grams, location: .pantry, bestBy: bestBy, source: .manual, addedOn: addedOn)
    }

    static func plan(start: Date, status: PlanStatus) -> MealPlan {
        MealPlan(startDate: start, days: 7, constraintsSnapshot: "c", solverVersion: "1", seed: 7, status: status)
    }

    static func meal(planID: MealPlanID, date: Date, slot: MealType, recipeID: RecipeID = RecipeID()) -> PlannedMeal {
        PlannedMeal(planID: planID, date: date, slot: slot, recipeID: recipeID, servings: 2)
    }

    static let profile = UserProfile(
        birthYear: 1988,
        sex: .female,
        heightCm: 168.5,
        weightKg: 61.2,
        activityLevel: .moderate,
        goal: .lessWaste,
        householdSize: 3,
        weeklyBudget: Decimal(string: "85.50"),
        currencyCode: "EUR",
        maxCookMinutes: 35,
        equipment: [.oven, .stovetop, .airFryer],
        showsNumbers: true,
        consents: Consents(aiProcessing: true, cloudSync: false)
    )

    static let allReasonCodes: [ReasonCode] = [
        .usesExpiring(food: FoodID(), bestBy: date(2026, 10, 18)),
        .pantryOverlap(count: 4),
        .quick(minutes: 20),
        .fibreGap(gramsShort: 6.5),
        .varietyCuisine(cuisine: "Korean"),
        .leftoverOf(meal: PlannedMealID()),
        .underBudget,
    ]

    static let allConstraintKinds: [ConstraintKind] = [
        .allergen(.sesame),
        .intolerance("lactose"),
        .diet(.vegetarian),
        .medical(.hypertension),
        .dislike(.food(FoodID())),
        .dislike(.name("coriander")),
        .religious(.halal),
    ]

    static func seedFile(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureMissing(name: name)
        }
        return url
    }

    static func count(_ table: String, in database: LarderDatabase) async throws -> Int {
        try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
        }
    }

    /// Runs FTS5's integrity check, which for external-content tables compares the index with its content.
    static func checkSearchIndexes(in database: LarderDatabase) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "INSERT INTO recipe_ft(recipe_ft, rank) VALUES('integrity-check', 1)")
            try db.execute(sql: "INSERT INTO food_ft(food_ft, rank) VALUES('integrity-check', 1)")
        }
    }
}

struct FixtureMissing: Error {
    let name: String
}
