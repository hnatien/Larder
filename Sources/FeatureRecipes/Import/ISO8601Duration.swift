import Foundation

/// Reads schema.org durations such as "PT1H20M".
nonisolated enum ISO8601Duration {
    /// Whole minutes, rounded up, or `nil` when `text` is not a duration or is zero.
    static func minutes(from text: String) -> Int? {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces).uppercased())
        guard rest.first == "P" else { return nil }
        rest = rest.dropFirst()
        var seconds = 0.0
        var inTime = false
        var digits = ""
        var sawComponent = false
        for character in rest {
            if character == "T" {
                inTime = true
            } else if character.isNumber || character == "." {
                digits.append(character)
            } else {
                guard let value = Double(digits) else { return nil }
                digits = ""
                switch (character, inTime) {
                case ("W", false): seconds += value * 7 * 86_400
                case ("D", false): seconds += value * 86_400
                case ("H", true): seconds += value * 3600
                case ("M", true): seconds += value * 60
                case ("S", true): seconds += value
                default: return nil
                }
                sawComponent = true
            }
        }
        guard digits.isEmpty, sawComponent, seconds > 0 else { return nil }
        return Int((seconds / 60).rounded(.up))
    }
}
