import Foundation
import LarderCore
import Testing
@testable import LarderPersistence

struct ProfileRepositoryTests {
    let database: LarderDatabase
    let profiles: GRDBProfileRepository

    init() throws {
        database = try LarderDatabase.inMemory()
        profiles = GRDBProfileRepository(database: database)
    }

    @Test func profileIsNilBeforeOnboarding() async throws {
        #expect(try await profiles.profile() == nil)
        #expect(try await profiles.constraints().isEmpty)
        #expect(try await profiles.targets().isEmpty)
    }

    @Test func profileRoundTripsEveryField() async throws {
        try await profiles.save(Fixtures.profile)
        #expect(try await profiles.profile() == Fixtures.profile)
    }

    @Test func profileUpsertKeepsASingleRow() async throws {
        try await profiles.save(Fixtures.profile)
        var changed = Fixtures.profile
        changed.weightKg = nil
        changed.weeklyBudget = nil
        changed.equipment = []
        try await profiles.save(changed)
        #expect(try await profiles.profile() == changed)
        #expect(try await Fixtures.count("profile", in: database) == 1)
    }

    @Test func constraintsRoundTripInOrderAndReplace() async throws {
        let constraints = Fixtures.allConstraintKinds.enumerated().map { index, kind in
            DietaryConstraint(
                axis: ConstraintAxis.allCases[index % ConstraintAxis.allCases.count],
                kind: kind,
                strictness: index.isMultiple(of: 2) ? .hard : .soft,
                source: ConstraintSource.allCases[index % ConstraintSource.allCases.count],
                lastConfirmed: Fixtures.date(2026, 10, 1 + index)
            )
        }
        try await profiles.saveConstraints(constraints)
        #expect(try await profiles.constraints() == constraints)

        let replacement = [constraints[3]]
        try await profiles.saveConstraints(replacement)
        #expect(try await profiles.constraints() == replacement)
    }

    @Test func targetsRoundTripInOrderAndReplace() async throws {
        let targets = [
            NutrientTarget(nutrient: .sodium, basis: .perDay, max: 2300, priority: 3, source: .dga2025),
            NutrientTarget(nutrient: .fiber, basis: .per1000kcal, min: 14, target: 14, priority: 2, source: .dga2025),
            NutrientTarget(nutrient: .addedSugar, basis: .percentEnergy, max: 10, priority: 1, source: .who),
            NutrientTarget(nutrient: .protein, basis: .perMeal, min: 25, target: 30, max: 45, priority: 0, source: .clinician),
        ]
        try await profiles.saveTargets(targets)
        #expect(try await profiles.targets() == targets)
        try await profiles.saveTargets([])
        #expect(try await profiles.targets().isEmpty)
    }
}
