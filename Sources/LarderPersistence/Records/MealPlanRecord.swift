import Foundation
import GRDB
import LarderCore

struct MealPlanRecord: LarderRecord {
    static let databaseTableName = "mealPlan"

    var id: UUID
    var startDate: Date
    var days: Int
    var constraintsSnapshot: String
    var solverVersion: String
    /// Decimal text, because SQLite integers cannot hold the full `UInt64` range.
    var seed: String
    var status: PlanStatus

    init(_ plan: MealPlan) {
        id = plan.id.rawValue
        startDate = plan.startDate
        days = plan.days
        constraintsSnapshot = plan.constraintsSnapshot
        solverVersion = plan.solverVersion
        seed = String(plan.seed)
        status = plan.status
    }

    func plan() throws -> MealPlan {
        guard let seed = UInt64(seed) else {
            throw InvalidStoredValue(column: "seed", value: seed)
        }
        return MealPlan(
            id: MealPlanID(rawValue: id),
            startDate: startDate,
            days: days,
            constraintsSnapshot: constraintsSnapshot,
            solverVersion: solverVersion,
            seed: seed,
            status: status
        )
    }
}

struct PlannedMealRecord: LarderRecord {
    static let databaseTableName = "plannedMeal"

    var id: UUID
    var planID: UUID
    var date: Date
    var slot: MealType
    var recipeID: UUID
    var servings: Int
    var leftoverOf: UUID?
    var isLocked: Bool
    var status: MealStatus
    var reasonCodes: [ReasonCode]
    var swapHistory: [RecipeID]

    init(_ meal: PlannedMeal) {
        id = meal.id.rawValue
        planID = meal.planID.rawValue
        date = meal.date
        slot = meal.slot
        recipeID = meal.recipeID.rawValue
        servings = meal.servings
        leftoverOf = meal.leftoverOf?.rawValue
        isLocked = meal.isLocked
        status = meal.status
        reasonCodes = meal.reasonCodes
        swapHistory = meal.swapHistory
    }

    var meal: PlannedMeal {
        PlannedMeal(
            id: PlannedMealID(rawValue: id),
            planID: MealPlanID(rawValue: planID),
            date: date,
            slot: slot,
            recipeID: RecipeID(rawValue: recipeID),
            servings: servings,
            leftoverOf: leftoverOf.map(PlannedMealID.init(rawValue:)),
            isLocked: isLocked,
            status: status,
            reasonCodes: reasonCodes,
            swapHistory: swapHistory
        )
    }
}
