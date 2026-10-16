import Foundation
import GRDB
import LarderCore

/// `PlanRepository` backed by the Larder SQLite store; throws `PersistenceError`.
public struct GRDBPlanRepository: PlanRepository {
    private let database: LarderDatabase

    /// Creates a repository over `database`.
    public init(database: LarderDatabase) {
        self.database = database
    }

    /// The active plan with the latest start date, if any.
    public func currentPlan() async throws -> MealPlan? {
        try await database.read { db in
            try MealPlanRecord
                .filter(Column("status") == PlanStatus.active.rawValue)
                .order(Column("startDate").desc)
                .fetchOne(db)?
                .plan()
        }
    }

    /// Every plan, latest start date first.
    public func plans() async throws -> [MealPlan] {
        try await database.read { db in
            try MealPlanRecord.order(Column("startDate").desc).fetchAll(db).map { try $0.plan() }
        }
    }

    /// Upserts the plan and replaces all of its meals in one transaction.
    public func save(_ plan: MealPlan, meals: [PlannedMeal]) async throws {
        try await database.write { db in
            try MealPlanRecord(plan).upsert(db)
            try PlannedMealRecord.filter(Column("planID") == plan.id.key).deleteAll(db)
            for meal in meals {
                try PlannedMealRecord(meal).insert(db)
            }
        }
    }

    public func meals(for planID: MealPlanID) async throws -> [PlannedMeal] {
        let meals = try await database.read { db in
            try PlannedMealRecord
                .filter(Column("planID") == planID.key)
                .order(Column("date"), Column("rowid"))
                .fetchAll(db)
                .map(\.meal)
        }
        return meals.enumerated()
            .sorted { lhs, rhs in
                let left = (lhs.element.date, Self.slotOrder(lhs.element.slot), lhs.offset)
                let right = (rhs.element.date, Self.slotOrder(rhs.element.slot), rhs.offset)
                return left < right
            }
            .map(\.element)
    }

    /// Replaces one planned meal; throws `PersistenceError.notFound` when it is not stored.
    public func updateMeal(_ meal: PlannedMeal) async throws {
        try await database.write { db in
            try PlannedMealRecord(meal).update(db)
        }
    }

    private static func slotOrder(_ slot: MealType) -> Int {
        MealType.allCases.firstIndex(of: slot) ?? MealType.allCases.count
    }
}
