import Foundation

/// The CSV and Markdown views of a finished run.
enum Report {
    /// One row per household and arm: household descriptors, then every metric; an empty cell has no value.
    static func csv(_ runs: [HouseholdRun]) -> String {
        let header = ["household", "label", "persona", "household_size", "goal", "max_cook_minutes", "arm"] + Metric.all.map(\.key)
        let rows = runs.map { run in
            let household = run.household
            let descriptors = [
                String(household.index), household.label, household.persona.rawValue,
                String(household.profile.householdSize), household.profile.goal.rawValue,
                String(household.profile.maxCookMinutes), run.arm,
            ]
            return descriptors.map(escape) + Metric.all.map { metric in
                metric.value(run).map { String(format: "%.4f", $0) } ?? ""
            }
        }
        return ([header] + rows).map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    /// Metrics as rows and arms as columns; each cell is mean / median / p90 over households.
    static func markdown(_ runs: [HouseholdRun], arms: [String]) -> String {
        var lines = [
            "| Metric (mean / median / p90) | " + arms.joined(separator: " | ") + " |",
            "|---|" + String(repeating: "---|", count: arms.count),
        ]
        let violations = arms.map { arm in
            runs.filter { $0.arm == arm }.reduce(0) { total, run in total + run.weeks.reduce(0) { $0 + $1.hardViolations } }
        }
        lines.append("| Hard-constraint violations (sum over all plans) | " + violations.map(String.init).joined(separator: " | ") + " |")
        for metric in Metric.all where metric.key != "hard_violations" {
            let cells = arms.map { arm in
                guard let summary = Summary(runs.filter { $0.arm == arm }.compactMap(metric.value)) else { return "n/a" }
                return "\(metric.format(summary.mean)) / \(metric.format(summary.median)) / \(metric.format(summary.p90))"
            }
            lines.append("| \(metric.label) | " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
