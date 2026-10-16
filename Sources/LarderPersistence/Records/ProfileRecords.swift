import Foundation
import GRDB
import LarderCore

struct ProfileRecord: LarderRecord {
    static let databaseTableName = "profile"
    /// The profile table holds exactly one row, with this identifier.
    static let singletonID = 1

    var id = singletonID
    var profile: UserProfile
}

struct DietaryConstraintRecord: LarderRecord {
    static let databaseTableName = "dietaryConstraint"

    var id: UUID
    var position: Int
    var axis: ConstraintAxis
    var kind: ConstraintKind
    var strictness: Strictness
    var source: ConstraintSource
    var lastConfirmed: Date

    init(_ constraint: DietaryConstraint, position: Int) {
        id = constraint.id.rawValue
        self.position = position
        axis = constraint.axis
        kind = constraint.kind
        strictness = constraint.strictness
        source = constraint.source
        lastConfirmed = constraint.lastConfirmed
    }

    var constraint: DietaryConstraint {
        DietaryConstraint(
            id: DietaryConstraintID(rawValue: id),
            axis: axis,
            kind: kind,
            strictness: strictness,
            source: source,
            lastConfirmed: lastConfirmed
        )
    }
}

struct NutrientTargetRecord: LarderRecord {
    static let databaseTableName = "nutrientTarget"

    var position: Int
    var nutrient: Nutrient
    var basis: TargetBasis
    var min: Double?
    var target: Double?
    var max: Double?
    var priority: Int
    var source: TargetSource

    init(_ target: NutrientTarget, position: Int) {
        self.position = position
        nutrient = target.nutrient
        basis = target.basis
        min = target.min
        self.target = target.target
        max = target.max
        priority = target.priority
        source = target.source
    }

    var nutrientTarget: NutrientTarget {
        NutrientTarget(
            nutrient: nutrient,
            basis: basis,
            min: min,
            target: target,
            max: max,
            priority: priority,
            source: source
        )
    }
}
