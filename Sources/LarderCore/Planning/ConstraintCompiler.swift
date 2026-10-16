import Foundation

/// Whether a candidate may be planned.
///
/// Only `.admitted` candidates are ever planned automatically. `.uncertain` candidates are never planned,
/// suggested or offered by the planner, Tonight or swaps; a user can still choose one explicitly, and the
/// plan verifier then reports it.
public enum Admission: Hashable, Sendable {
    case admitted(softPenalties: [String])
    case excluded(reasons: [String])
    /// Not known to be safe; never planned automatically.
    case uncertain(reasons: [String])
}

/// Hard filters and planning inputs compiled from a profile.
public struct CompiledConstraints: Hashable, Sendable {
    public var constraints: [DietaryConstraint]
    public var maxCookMinutes: Int
    /// Equipment the user has; empty means unknown and admits every recipe.
    public var equipment: Set<Equipment>
    public var targets: [NutrientTarget]
    /// People eating each meal; at least one.
    public var householdSize: Int

    /// Creates compiled constraints; a household below one counts as one.
    public init(
        constraints: [DietaryConstraint],
        maxCookMinutes: Int,
        equipment: Set<Equipment>,
        targets: [NutrientTarget],
        householdSize: Int
    ) {
        self.constraints = constraints
        self.maxCookMinutes = maxCookMinutes
        self.equipment = equipment
        self.targets = targets
        self.householdSize = max(householdSize, 1)
    }

    /// Dietary rules, then time (prep plus cook within `maxCookMinutes`), then equipment; any exclusion wins over uncertainty.
    public func admits(_ candidate: RecipeCandidate, foods: [FoodID: Food]) -> Admission {
        var excluded: [String] = []
        var uncertain: [String] = []
        var penalties: [String] = []

        switch ConstraintFilter().verdict(
            recipe: candidate.recipe, ingredients: candidate.ingredients, foods: foods, constraints: constraints
        ) {
        case .pass(let soft): penalties = soft
        case .excluded(let reasons): excluded = reasons
        case .uncertain(let reasons): uncertain = reasons
        }

        if candidate.totalMinutes > maxCookMinutes {
            excluded.append("Takes \(candidate.totalMinutes) minutes, over the \(maxCookMinutes)-minute limit")
        }
        if !equipment.isEmpty {
            for item in Equipment.allCases where candidate.recipe.tags.equipment.contains(item) && !equipment.contains(item) {
                excluded.append("Needs \(item.readableName)")
            }
        }

        if !excluded.isEmpty { return .excluded(reasons: excluded) }
        if !uncertain.isEmpty { return .uncertain(reasons: uncertain) }
        return .admitted(softPenalties: penalties)
    }

    /// Stable FNV-1a 64-bit hex hash of the rules, time cap, equipment and household size, independent of constraint order, ids and dates.
    public var snapshot: String {
        var parts = constraints.map { "\($0.kind.snapshotKey)|\($0.strictness.rawValue)" }.sorted()
        parts.append("maxCookMinutes=\(maxCookMinutes)")
        parts.append("equipment=" + equipment.map(\.rawValue).sorted().joined(separator: ","))
        parts.append("householdSize=\(householdSize)")
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in parts.joined(separator: "\n").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

/// Turns a profile, its constraints and nutrient targets into planner inputs.
public enum ConstraintCompiler {
    /// Compiled constraints for `profile`.
    public static func compile(
        profile: UserProfile,
        constraints: [DietaryConstraint],
        targets: [NutrientTarget]
    ) -> CompiledConstraints {
        CompiledConstraints(
            constraints: constraints,
            maxCookMinutes: profile.maxCookMinutes,
            equipment: profile.equipment,
            targets: targets,
            householdSize: profile.householdSize
        )
    }
}

extension ConstraintKind {
    fileprivate var snapshotKey: String {
        switch self {
        case .allergen(let allergen): "allergen:\(allergen.rawValue)"
        case .intolerance(let name): "intolerance:\(name.lowercased())"
        case .diet(let pattern): "diet:\(pattern.rawValue)"
        case .medical(let flag): "medical:\(flag.rawValue)"
        case .dislike(.food(let id)): "dislikeFood:\(id.rawValue.uuidString)"
        case .dislike(.name(let name)): "dislikeName:\(name.lowercased())"
        case .religious(let rule): "religious:\(rule.rawValue)"
        }
    }
}

extension Equipment {
    fileprivate var readableName: String {
        switch self {
        case .oven: "an oven"
        case .stovetop: "a stovetop"
        case .microwave: "a microwave"
        case .airFryer: "an air fryer"
        case .slowCooker: "a slow cooker"
        case .pressureCooker: "a pressure cooker"
        case .blender: "a blender"
        case .foodProcessor: "a food processor"
        case .grill: "a grill"
        }
    }
}
