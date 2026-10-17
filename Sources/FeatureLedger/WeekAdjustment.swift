import Foundation
import LarderCore

/// An assistant edit as it applies to the next plan: it tightens or reprioritises this week only.
///
/// Nothing here changes Settings, and nothing loosens them: dropping a diet or a dislike is set aside for Settings,
/// as are allergen, medical and religious edits, which the proxy backend never passes on in the first place.
public nonisolated struct WeekAdjustment: Hashable, Sendable {
    /// One change, in the order the assistant proposed it.
    public enum Item: Hashable, Sendable {
        /// Follow a diet on one day (offset from today) or, with `nil`, the whole week.
        case diet(DietPattern, dayOffset: Int?)
        /// Dinners within this many minutes on one day or the whole week.
        case maxMinutes(Int, dayOffset: Int?)
        /// Leave out recipes containing this food this week.
        case avoid(String)
        /// Prefer recipes that use this pantry food.
        case useUp(String)
        /// Rank recipes for this goal instead of the profile's.
        case goal(Goal)
    }

    /// What one day of the plan must meet on top of the week's rules.
    struct DayRule: Hashable, Sendable {
        var diets: Set<DietPattern> = []
        var maxCookMinutes: Int?
    }

    public private(set) var items: [Item] = []
    /// Proposed changes left out because only Settings can make them.
    public private(set) var setAsideCount = 0

    /// The changes in `edit` this week can make; removals count as set aside, as do the edits the backend dropped.
    public init(_ edit: ConstraintEdit, days: Int = PlanningService.weekDays) {
        setAsideCount = edit.droppedCount
        for change in edit.changes {
            switch change {
            case .addDiet(let pattern, let offset):
                guard Self.fits(offset, days: days) else { setAsideCount += 1; continue }
                append(.diet(pattern, dayOffset: offset))
            case .setMaxCookMinutes(let minutes, let offset):
                guard minutes > 0, Self.fits(offset, days: days) else { setAsideCount += 1; continue }
                append(.maxMinutes(minutes, dayOffset: offset))
            case .addDislike(let name):
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                append(.avoid(trimmed))
            case .useUp(let name):
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                append(.useUp(trimmed))
            case .setGoal(let goal):
                append(.goal(goal))
            case .removeDiet, .removeDislike:
                setAsideCount += 1
            }
        }
    }

    /// Whether there is nothing to apply.
    public var isEmpty: Bool { items.isEmpty }

    /// These changes followed by `later`'s, each kept once at its latest place so a later time limit or goal wins;
    /// the set-aside count is `later`'s, since it describes the latest answer.
    func adding(_ later: WeekAdjustment) -> WeekAdjustment {
        var combined = self
        for item in later.items {
            combined.items.removeAll { $0 == item }
            combined.items.append(item)
        }
        combined.setAsideCount = later.setAsideCount
        return combined
    }

    /// The week's time limit: the last whole-week one proposed, else `nil` to keep the profile's.
    var maxCookMinutes: Int? {
        items.reversed().lazy.compactMap { item -> Int? in
            if case .maxMinutes(let minutes, nil) = item { minutes } else { nil }
        }.first
    }

    /// The week's goal: the last one proposed, else `nil` to keep the profile's.
    var goal: Goal? {
        items.reversed().lazy.compactMap { item -> Goal? in
            if case .goal(let goal) = item { goal } else { nil }
        }.first
    }

    /// `base` plus the week's diets as hard rules and its foods to avoid as hard dislikes; existing rules are kept.
    func constraints(adding base: [DietaryConstraint], at date: Date) -> [DietaryConstraint] {
        var kinds: [ConstraintKind] = []
        for item in items {
            switch item {
            case .diet(let pattern, nil): kinds.append(.diet(pattern))
            case .avoid(let name): kinds.append(.dislike(.name(name)))
            case .diet, .maxMinutes, .useUp, .goal: break
            }
        }
        let added = kinds
            .filter { kind in !base.contains { $0.kind == kind && $0.strictness == .hard } }
            .map { kind in
                let axis: ConstraintAxis = if case .diet = kind { .ethical } else { .preference }
                return DietaryConstraint(axis: axis, kind: kind, strictness: .hard, source: .user, lastConfirmed: date)
            }
        return base + added
    }

    /// The rules for single days, keyed by offset from the plan start.
    var dayRules: [Int: DayRule] {
        var rules: [Int: DayRule] = [:]
        for item in items {
            switch item {
            case .diet(let pattern, let offset?): rules[offset, default: DayRule()].diets.insert(pattern)
            case .maxMinutes(let minutes, let offset?): rules[offset, default: DayRule()].maxCookMinutes = minutes
            case .diet, .maxMinutes, .avoid, .useUp, .goal: break
            }
        }
        return rules
    }

    /// Foods on the shelves whose item or food name contains a name the user asked to use up.
    func useUpFoods(in pantry: [PantryItem], foods: [FoodID: Food]) -> Set<FoodID> {
        let names = items.compactMap { item -> String? in if case .useUp(let name) = item { name } else { nil } }
        guard !names.isEmpty else { return [] }
        var matched = Set<FoodID>()
        for item in pantry where item.quantityGrams > 0 {
            guard let foodID = item.foodID else { continue }
            let labels = [item.rawName, foods[foodID]?.name].compactMap(\.self)
            if names.contains(where: { name in labels.contains { $0.localizedStandardContains(name) } }) {
                matched.insert(foodID)
            }
        }
        return matched
    }

    private mutating func append(_ item: Item) {
        if !items.contains(item) { items.append(item) }
    }

    private static func fits(_ offset: Int?, days: Int) -> Bool {
        offset.map { (0..<days).contains($0) } ?? true
    }
}
