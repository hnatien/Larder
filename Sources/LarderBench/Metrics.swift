import Foundation
import LarderCore

/// One per-household measure, computed the same way for every arm.
struct Metric: Sendable {
    enum Unit: Sendable {
        case count
        case share
        case grams
        case bits
        case milliseconds
    }

    let key: String
    let label: String
    let unit: Unit
    let value: @Sendable (HouseholdRun) -> Double?

    func format(_ number: Double) -> String {
        switch unit {
        case .count: String(format: "%.2f", number)
        case .share: String(format: "%.1f%%", number * 100)
        case .grams: String(format: "%.0f g", number)
        case .bits: String(format: "%.2f", number)
        case .milliseconds: String(format: "%.1f ms", number)
        }
    }

    /// A signed difference between two values of this metric; shares are in percentage points.
    func formatDifference(_ number: Double) -> String {
        switch unit {
        case .share: String(format: "%+.1f pt", number * 100)
        default: (number < 0 ? "" : "+") + format(number)
        }
    }

    /// Nutrients the default targets cover (`NutrientTargets.defaults`), in report order.
    static let nutrients: [Nutrient] = [.energy, .protein, .fiber, .sodium, .saturatedFat, .addedSugar, .potassium]

    static let all: [Metric] = [
        Metric(key: "hard_violations", label: "Hard-constraint violations (total per household)", unit: .count) { run in
            Double(run.weeks.reduce(0) { $0 + $1.hardViolations })
        },
        Metric(key: "pantry_use", label: "Perishable grams used before expiry", unit: .share) { $0.pantryUse },
        Metric(key: "starting_pantry_use", label: "Starting-pantry perishables used before expiry", unit: .share) {
            $0.startingPantryUse
        },
        Metric(key: "waste_g_per_week", label: "Grams expired per week (waste at risk)", unit: .grams) { run in
            run.weeks.isEmpty ? nil : run.expiredGrams / Double(run.weeks.count)
        },
        Metric(key: "grocery_lines_per_week", label: "New grocery lines per week", unit: .count) { run in
            mean(run.weeks.map { Double($0.groceryLines) })
        },
        Metric(key: "repeat_within_week", label: "Recipe repeats within a week", unit: .share) { run in
            mean(run.weeks.compactMap { repeatsWithin(cooked($0.plan)) })
        },
        Metric(key: "repeat_across_weeks", label: "Recipes repeated from the previous week", unit: .share) { run in
            mean(zip(run.weeks, run.weeks.dropFirst()).compactMap { previous, week in
                repeatsAcross(cooked(week.plan), previous: Set(cooked(previous.plan).map(\.recipeID)))
            })
        },
        Metric(key: "cuisine_entropy_bits", label: "Cuisine entropy per week (bits)", unit: .bits) { run in
            mean(run.weeks.compactMap { $0.cuisineEntropy })
        },
        Metric(key: "unfilled_per_week", label: "Unfilled slots per week", unit: .count) { run in
            mean(run.weeks.map { Double($0.unfilledSlots) })
        },
        Metric(key: "tonight_per_week", label: "Dinners swapped for Tonight per week", unit: .count) { run in
            mean(run.weeks.map { Double($0.tonightMeals) })
        },
        Metric(key: "solve_ms", label: "Solve time per week", unit: .milliseconds) { run in
            mean(run.weeks.map { $0.solveSeconds * 1000 })
        },
    ] + nutrients.map { nutrient in
        Metric(
            key: "within_\(nutrient.rawValue)", label: "Weeks within the \(nutrient.readableName) band, per filled dinner", unit: .share
        ) { run in
            mean(run.weeks.compactMap { week in
                week.nutrientNotes.first { $0.nutrient == nutrient }.map { $0.status == .within ? 1 : 0 }
            })
        }
    }

    /// Planned meals the household cooked from scratch: skipped and Tonight-replaced meals and leftovers excluded.
    static func cooked(_ plan: [PlannedMeal]) -> [PlannedMeal] {
        plan.filter { $0.status == .cooked && $0.leftoverOf == nil }
    }

    /// Share of meals whose recipe already appeared earlier in the same week.
    private static func repeatsWithin(_ meals: [PlannedMeal]) -> Double? {
        guard !meals.isEmpty else { return nil }
        var seen = Set<RecipeID>()
        let repeats = meals.count { !seen.insert($0.recipeID).inserted }
        return Double(repeats) / Double(meals.count)
    }

    private static func repeatsAcross(_ meals: [PlannedMeal], previous: Set<RecipeID>) -> Double? {
        guard !meals.isEmpty else { return nil }
        return Double(meals.count { previous.contains($0.recipeID) }) / Double(meals.count)
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

extension WeekRecord {
    /// Shannon entropy in bits of the cuisines cooked from scratch; `nil` when nothing was.
    var cuisineEntropy: Double? {
        guard !cuisines.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for cuisine in cuisines { counts[cuisine, default: 0] += 1 }
        let total = Double(cuisines.count)
        return counts.values.sorted().reduce(0) { entropy, count in
            let share = Double(count) / total
            return entropy - share * log2(share)
        }
    }
}

/// Mean, median and 90th percentile of one metric over households.
struct Summary: Sendable {
    var mean: Double
    var median: Double
    var p90: Double
    var count: Int

    /// `nil` when no household has a value; percentiles interpolate linearly between ranks.
    init?(_ values: [Double]) {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        mean = sorted.reduce(0, +) / Double(sorted.count)
        median = Self.quantile(sorted, 0.5)
        p90 = Self.quantile(sorted, 0.9)
        count = sorted.count
    }

    /// The `q` quantile of ascending `sorted`, which must not be empty.
    static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        let position = q * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }
}

extension Nutrient {
    var readableName: String {
        switch self {
        case .energy: "energy"
        case .protein: "protein"
        case .fiber: "fibre"
        case .sodium: "sodium"
        case .saturatedFat: "saturated fat"
        case .addedSugar: "added sugar"
        case .potassium: "potassium"
        default: rawValue
        }
    }
}
