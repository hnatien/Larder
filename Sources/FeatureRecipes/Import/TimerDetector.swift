import Foundation

/// Finds a cooking time in step text.
nonisolated enum TimerDetector {
    /// Seconds for the first duration in `text` ("10 minutes", "1 hour 20 minutes", "8-10 min" takes 10), or `nil` when there is none.
    static func seconds(in text: String) -> Int? {
        let pattern = /(\d+(?:\.\d+)?)(?:\s*(?:-|\u{2013}|\u{2014}|to)\s*(\d+(?:\.\d+)?))?\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b/
            .ignoresCase()
        var total = 0.0
        var previousEnd: String.Index?
        for match in text.matches(of: pattern) {
            if let previousEnd, !isJoiner(text[previousEnd..<match.range.lowerBound]) { break }
            let amount = Double(match.output.2 ?? match.output.1) ?? 0
            total += amount * multiplier(for: match.output.3)
            previousEnd = match.range.upperBound
        }
        guard total >= 1 else { return nil }
        return Int(total.rounded())
    }

    private static func multiplier(for unit: Substring) -> Double {
        switch unit.lowercased().first {
        case "h": 3600
        case "m": 60
        default: 1
        }
    }

    private static func isJoiner(_ gap: Substring) -> Bool {
        ["", "and", ",", ", and"].contains(gap.trimmingCharacters(in: .whitespaces).lowercased())
    }
}
