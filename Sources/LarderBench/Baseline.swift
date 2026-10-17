import Foundation

/// The planner's committed reference figures, and the regression gate that compares a run against them.
///
/// The gate fails when the run's planner has any hard violation, or when a gated metric's mean is worse than the
/// baseline's 95% interval on that metric's bad side. The interval comes from the baseline's own households, so a
/// change smaller than the gate set's sampling noise passes; the paired report is the place to look for those.
struct Baseline: Codable, Hashable, Sendable {
    /// The flags a run must use to be compared with this baseline.
    struct Configuration: Codable, Hashable, Sendable, CustomStringConvertible {
        var seed: UInt64
        var seeds: Int
        var households: Int
        var weeks: Int

        var description: String {
            "--seed \(seed) --seeds \(seeds) --households \(households) --weeks \(weeks)"
        }
    }

    /// A gated metric and the direction in which it gets worse.
    struct Gate: Sendable {
        var key: String
        var lowerIsBetter: Bool
    }

    enum Failure: Error, CustomStringConvertible {
        case mismatch(String)
        case regressed([String])

        var description: String {
            switch self {
            case .mismatch(let text): text
            case .regressed(let reasons): "regression gate failed:\n" + reasons.map { "  - " + $0 }.joined(separator: "\n")
            }
        }
    }

    /// One gated metric in a check: the baseline interval, the run's interval and whether it regressed.
    struct Row: Sendable {
        var metric: Metric
        var baseline: Interval?
        var current: Interval?
        var regressed: Bool
    }

    static let arm = "planner"
    static let gates: [Gate] = [
        Gate(key: "waste_g_per_week", lowerIsBetter: true),
        Gate(key: "starting_pantry_use", lowerIsBetter: false),
        Gate(key: "repeat_across_weeks", lowerIsBetter: true),
    ]

    var configuration: Configuration
    var arm: String
    /// Gated metric key to the planner's mean and interval over the baseline's households.
    var metrics: [String: Interval]

    init(configuration: Configuration, metrics: [String: Interval], arm: String = Baseline.arm) {
        self.configuration = configuration
        self.arm = arm
        self.metrics = metrics
    }

    /// The baseline a finished run would write.
    init(runs: [HouseholdRun], configuration: Configuration) {
        var metrics: [String: Interval] = [:]
        for gate in Self.gates {
            guard let metric = Self.metric(gate.key) else { continue }
            metrics[gate.key] = Bootstrap.mean(Bootstrap.values(runs, arm: Self.arm, metric: metric))
        }
        self.init(configuration: configuration, metrics: metrics)
    }

    static func load(from url: URL) throws -> Baseline {
        try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }

    /// Throws `Failure.mismatch` unless a run with `configuration` can be compared with this baseline.
    func require(_ configuration: Configuration) throws {
        guard configuration == self.configuration else {
            throw Failure.mismatch(
                "the baseline was written for \(self.configuration), not \(configuration); rerun with its flags or write a new baseline"
            )
        }
    }

    /// Every gated metric for `runs` against this baseline; throws `Failure.mismatch` when the run's flags differ.
    func compare(_ runs: [HouseholdRun], configuration: Configuration) throws -> [Row] {
        try require(configuration)
        return Self.gates.compactMap { gate in
            guard let metric = Self.metric(gate.key) else { return nil }
            let baseline = metrics[gate.key]
            let current = Bootstrap.mean(Bootstrap.values(runs, arm: arm, metric: metric))
            let regressed: Bool = if let baseline, let current {
                gate.lowerIsBetter ? current.mean > baseline.high : current.mean < baseline.low
            } else {
                // A metric that was measured before and cannot be measured now, or the reverse, is a failure too.
                baseline != nil || current != nil
            }
            return Row(metric: metric, baseline: baseline, current: current, regressed: regressed)
        }
    }

    /// The reasons the gate fails for `runs`, empty when it passes; throws `Failure.mismatch` like `compare`.
    func failures(_ runs: [HouseholdRun], configuration: Configuration) throws -> [String] {
        let rows = try compare(runs, configuration: configuration)
        let violations = Self.hardViolations(runs, arm: arm)
        var reasons = violations > 0 ? ["\(arm) has \(violations) hard-constraint violations (must be 0)"] : []
        reasons += rows.filter(\.regressed).map { row in
            let baseline = row.baseline?.format(row.metric) ?? "n/a"
            let current = row.current?.format(row.metric) ?? "n/a"
            return "\(row.metric.label): \(current), baseline \(baseline)"
        }
        return reasons
    }

    /// The check as a Markdown table, one row per gated metric plus hard violations.
    func markdown(_ runs: [HouseholdRun], configuration: Configuration) throws -> String {
        let rows = try compare(runs, configuration: configuration)
        let violations = Self.hardViolations(runs, arm: arm)
        var lines = [
            "| Gate (\(arm), mean [95% CI]) | Baseline | This run | Result |",
            "|---|---|---|---|",
            "| Hard-constraint violations | 0 | \(violations) | \(violations > 0 ? "FAIL" : "pass") |",
        ]
        for row in rows {
            let baseline = row.baseline?.format(row.metric) ?? "n/a"
            let current = row.current?.format(row.metric) ?? "n/a"
            lines.append("| \(row.metric.label) | \(baseline) | \(current) | \(row.regressed ? "FAIL" : "pass") |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func hardViolations(_ runs: [HouseholdRun], arm: String) -> Int {
        runs.filter { $0.arm == arm }.reduce(0) { total, run in total + run.weeks.reduce(0) { $0 + $1.hardViolations } }
    }

    private static func metric(_ key: String) -> Metric? {
        Metric.all.first { $0.key == key }
    }
}
