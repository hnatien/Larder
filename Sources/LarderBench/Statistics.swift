import Foundation

/// A mean with its bootstrap 95% interval, over `count` values.
struct Interval: Codable, Hashable, Sendable {
    var mean: Double
    var low: Double
    var high: Double
    var count: Int

    /// `mean [low, high]`; a difference is signed, with shares in percentage points.
    func format(_ metric: Metric, difference: Bool = false) -> String {
        let text = difference ? metric.formatDifference : metric.format
        return "\(text(mean)) [\(text(low)), \(text(high))]"
    }
}

/// Percentile bootstrap over households, stratified by seed.
///
/// Each seed draws its own households from the seed alone, and nothing in the simulation is shared between households
/// of one seed, so every (seed, household) pair is an independent unit. A resample redraws each seed's households
/// with replacement and keeps each seed's count, so every resample has the same seed mix as the run.
enum Bootstrap {
    static let resamples = 2000
    /// Fixed so the same values always give the same interval.
    static let seed: UInt64 = 0xB007_5747

    /// The pooled mean of `groups` (one per seed) and its 95% interval; `nil` when there are no values. Empty groups
    /// are ignored, and a single value gives a zero-width interval.
    static func mean(_ groups: [[Double]], resamples: Int = resamples) -> Interval? {
        let groups = groups.filter { !$0.isEmpty }
        let count = groups.reduce(0) { $0 + $1.count }
        guard count > 0, resamples > 0 else { return nil }
        var draws = Draws(seed: seed)
        var means: [Double] = []
        means.reserveCapacity(resamples)
        for _ in 0..<resamples {
            var total = 0.0
            for group in groups {
                for _ in group.indices { total += group[draws.integer(0...(group.count - 1))] }
            }
            means.append(total / Double(count))
        }
        means.sort()
        return Interval(
            mean: groups.joined().reduce(0, +) / Double(count),
            low: Summary.quantile(means, 0.025),
            high: Summary.quantile(means, 0.975),
            count: count
        )
    }

    /// `metric` for `arm`, one group per seed in seed order; households without a value are left out.
    static func values(_ runs: [HouseholdRun], arm: String, metric: Metric) -> [[Double]] {
        let bySeed = Dictionary(grouping: runs.filter { $0.arm == arm }, by: \.seed)
        return bySeed.keys.sorted().map { seed in bySeed[seed, default: []].compactMap(metric.value) }
    }

    /// `metric` for `arm` minus `metric` for `baseline`, household by household, one group per seed in seed order.
    /// A household is left out when either arm has no value for it.
    static func differences(_ runs: [HouseholdRun], arm: String, baseline: String, metric: Metric) -> [[Double]] {
        let bySeed = Dictionary(grouping: runs, by: \.seed)
        return bySeed.keys.sorted().map { seed in
            let seedRuns = bySeed[seed, default: []]
            let reference = Dictionary(
                seedRuns.filter { $0.arm == baseline }.map { ($0.household.index, $0) }, uniquingKeysWith: { first, _ in first }
            )
            return seedRuns.filter { $0.arm == arm }.compactMap { run in
                guard let value = metric.value(run), let other = reference[run.household.index].flatMap(metric.value) else {
                    return nil
                }
                return value - other
            }
        }
    }
}
