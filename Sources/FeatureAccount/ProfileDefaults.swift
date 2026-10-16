import Foundation
import LarderCore

/// Values used when a question is skipped or never asked.
nonisolated enum ProfileDefaults {
    static let heightCm = 170.0
    /// The age assumed for "Prefer not to say".
    static let undisclosedAge = 35
    static let householdSize = 2
    static let householdRange = 1...8
    static let maxCookMinutes = 35
    static let cookMinuteChoices = [15, 25, 35, 45, 60]
    static let equipment: Set<Equipment> = [.oven, .stovetop]
    static let goal: Goal = .maintain
    static let activityLevel: ActivityLevel = .light

    /// The calendar year of `date`.
    static func referenceYear(at date: Date) -> Int {
        Calendar(identifier: .gregorian).component(.year, from: date)
    }

    /// Years of birth offered, newest first.
    static func birthYears(referenceYear: Int) -> [Int] {
        Array((referenceYear - 100)...(referenceYear - 13)).reversed()
    }

    /// The stored year for a chosen year, or for "Prefer not to say" when `year` is `nil` or out of range.
    static func birthYear(_ year: Int?, referenceYear: Int) -> Int {
        guard let year, birthYears(referenceYear: referenceYear).contains(year) else {
            return referenceYear - undisclosedAge
        }
        return year
    }

    /// The nearest offered cook-time choice to `minutes`.
    static func cookMinutes(nearest minutes: Int) -> Int {
        cookMinuteChoices.min { abs($0 - minutes) < abs($1 - minutes) } ?? maxCookMinutes
    }
}

extension ConstraintKind {
    /// The axis a user-chosen constraint of this kind is stored on.
    nonisolated var axis: ConstraintAxis {
        switch self {
        case .allergen, .intolerance, .medical: .medical
        case .diet: .ethical
        case .religious: .religious
        case .dislike: .preference
        }
    }
}

extension DietaryConstraint {
    /// A constraint the user set, on its kind's axis; dislikes are soft, everything else hard.
    nonisolated static func userSet(_ kind: ConstraintKind, at date: Date) -> DietaryConstraint {
        let strictness: Strictness = if case .dislike = kind { .soft } else { .hard }
        return DietaryConstraint(axis: kind.axis, kind: kind, strictness: strictness, source: .user, lastConfirmed: date)
    }
}

extension NutrientTargets {
    /// Fresh defaults for nutrients the user or a clinician has not set, keeping theirs.
    nonisolated static func refreshed(
        _ existing: [NutrientTarget],
        for profile: UserProfile,
        constraints: [DietaryConstraint],
        referenceYear: Int
    ) -> [NutrientTarget] {
        let kept = existing.filter { $0.source == .custom || $0.source == .clinician }
        let keptNutrients = Set(kept.map(\.nutrient))
        let defaults = defaults(for: profile, constraints: constraints, referenceYear: referenceYear)
        return kept + defaults.filter { !keptNutrients.contains($0.nutrient) }
    }
}
