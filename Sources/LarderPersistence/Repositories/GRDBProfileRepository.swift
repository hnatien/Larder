import Foundation
import GRDB
import LarderCore

/// `ProfileRepository` backed by the Larder SQLite store; throws `PersistenceError`.
public struct GRDBProfileRepository: ProfileRepository {
    private let database: LarderDatabase

    /// Creates a repository over `database`.
    public init(database: LarderDatabase) {
        self.database = database
    }

    public func profile() async throws -> UserProfile? {
        try await database.read { db in
            try ProfileRecord.fetchOne(db, key: ProfileRecord.singletonID)?.profile
        }
    }

    public func save(_ profile: UserProfile) async throws {
        try await database.write { db in
            try ProfileRecord(profile: profile).upsert(db)
        }
    }

    /// Every dietary constraint, in the order last saved.
    public func constraints() async throws -> [DietaryConstraint] {
        try await database.read { db in
            try DietaryConstraintRecord.order(Column("position")).fetchAll(db).map(\.constraint)
        }
    }

    public func saveConstraints(_ constraints: [DietaryConstraint]) async throws {
        try await database.write { db in
            try DietaryConstraintRecord.deleteAll(db)
            for (position, constraint) in constraints.enumerated() {
                try DietaryConstraintRecord(constraint, position: position).insert(db)
            }
        }
    }

    /// Every nutrient target, in the order last saved.
    public func targets() async throws -> [NutrientTarget] {
        try await database.read { db in
            try NutrientTargetRecord.order(Column("position")).fetchAll(db).map(\.nutrientTarget)
        }
    }

    public func saveTargets(_ targets: [NutrientTarget]) async throws {
        try await database.write { db in
            try NutrientTargetRecord.deleteAll(db)
            for (position, target) in targets.enumerated() {
                try NutrientTargetRecord(target, position: position).insert(db)
            }
        }
    }
}
