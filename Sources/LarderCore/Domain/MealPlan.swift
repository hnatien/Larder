import Foundation

/// A generated or manual plan covering consecutive days.
public struct MealPlan: Identifiable, Hashable, Codable, Sendable {
    public var id: MealPlanID
    public var startDate: Date
    public var days: Int
    /// Hash of the constraints the plan was solved against.
    public var constraintsSnapshot: String
    public var solverVersion: String
    public var seed: UInt64
    public var status: PlanStatus

    /// Creates a meal plan.
    public init(
        id: MealPlanID = MealPlanID(),
        startDate: Date,
        days: Int,
        constraintsSnapshot: String,
        solverVersion: String,
        seed: UInt64,
        status: PlanStatus
    ) {
        self.id = id
        self.startDate = startDate
        self.days = days
        self.constraintsSnapshot = constraintsSnapshot
        self.solverVersion = solverVersion
        self.seed = seed
        self.status = status
    }
}

/// Lifecycle of a meal plan.
public enum PlanStatus: String, CaseIterable, Hashable, Codable, Sendable {
    case draft
    case active
    case archived
}
