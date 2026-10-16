import Foundation

/// Reads and writes the amount at the start of an ingredient line: "2", "1 1/2", "½", "1½", "2-3", "0.5".
nonisolated enum QuantityText {
    /// An amount found at the start of a string; `upper` is set for a range such as "2-3".
    struct Amount: Hashable, Sendable {
        var lower: Double
        var upper: Double?
        var end: String.Index

        /// The larger end of a range, or the single value.
        var value: Double { upper ?? lower }
    }

    private static let unicodeFractions: [Character: Double] = [
        "\u{BC}": 0.25, "\u{BD}": 0.5, "\u{BE}": 0.75,
        "\u{2153}": 1.0 / 3, "\u{2154}": 2.0 / 3,
        "\u{2155}": 0.2, "\u{2156}": 0.4, "\u{2157}": 0.6, "\u{2158}": 0.8,
        "\u{2159}": 1.0 / 6, "\u{215A}": 5.0 / 6,
        "\u{215B}": 0.125, "\u{215C}": 0.375, "\u{215D}": 0.625, "\u{215E}": 0.875,
    ]

    /// The amount at the start of `text`, or `nil` when it does not begin with a number.
    static func scan(_ text: Substring) -> Amount? {
        guard let first = number(in: text, from: text.startIndex) else { return nil }
        guard let separatorEnd = rangeSeparatorEnd(in: text, from: first.end),
              let second = number(in: text, from: separatorEnd)
        else { return Amount(lower: first.value, upper: nil, end: first.end) }
        if second.value < 1, first.value >= 1, first.value == first.value.rounded() {
            return Amount(lower: first.value + second.value, upper: nil, end: second.end)
        }
        guard second.value >= first.value else { return Amount(lower: first.value, upper: nil, end: first.end) }
        return Amount(lower: first.value, upper: second.value, end: second.end)
    }

    /// Text for `value` in quarter steps with a vulgar fraction ("1 ½"), else up to two decimals.
    static func format(_ value: Double) -> String {
        let whole = value.rounded(.down)
        let fraction = value - whole
        let glyph: String? = switch fraction {
        case 0.24...0.26: "\u{BC}"
        case 0.49...0.51: "\u{BD}"
        case 0.74...0.76: "\u{BE}"
        default: nil
        }
        if let glyph {
            return whole == 0 ? glyph : "\(Int(whole)) \(glyph)"
        }
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    private static func number(in text: Substring, from start: Substring.Index) -> (value: Double, end: Substring.Index)? {
        var index = start
        let digitsStart = index
        while index < text.endIndex, text[index].isASCIIDigit { index = text.index(after: index) }
        guard index > digitsStart else {
            guard start < text.endIndex, let fraction = unicodeFractions[text[start]] else { return nil }
            return (fraction, text.index(after: start))
        }
        guard var value = Double(text[digitsStart..<index]) else { return nil }

        if index < text.endIndex, text[index] == ".", case let next = text.index(after: index),
           next < text.endIndex, text[next].isASCIIDigit {
            var decimalEnd = next
            while decimalEnd < text.endIndex, text[decimalEnd].isASCIIDigit { decimalEnd = text.index(after: decimalEnd) }
            guard let decimal = Double(text[digitsStart..<decimalEnd]) else { return nil }
            return (decimal, decimalEnd)
        }
        if let slash = slashFraction(in: text, from: index, numerator: value) {
            return slash
        }
        var probe = index
        while probe < text.endIndex, text[probe] == " " { probe = text.index(after: probe) }
        if probe < text.endIndex, let fraction = unicodeFractions[text[probe]] {
            value += fraction
            index = text.index(after: probe)
        } else if let mixed = mixedFraction(in: text, from: probe) {
            value += mixed.value
            index = mixed.end
        }
        return (value, index)
    }

    private static func slashFraction(in text: Substring, from index: Substring.Index, numerator: Double) -> (Double, Substring.Index)? {
        guard index < text.endIndex, text[index] == "/" else { return nil }
        var end = text.index(after: index)
        let denominatorStart = end
        while end < text.endIndex, text[end].isASCIIDigit { end = text.index(after: end) }
        guard end > denominatorStart, let denominator = Double(text[denominatorStart..<end]), denominator > 0 else { return nil }
        return (numerator / denominator, end)
    }

    private static func mixedFraction(in text: Substring, from start: Substring.Index) -> (value: Double, end: Substring.Index)? {
        var index = start
        while index < text.endIndex, text[index].isASCIIDigit { index = text.index(after: index) }
        guard index > start, let numerator = Double(text[start..<index]),
              let fraction = slashFraction(in: text, from: index, numerator: numerator)
        else { return nil }
        return (fraction.0, fraction.1)
    }

    private static func rangeSeparatorEnd(in text: Substring, from start: Substring.Index) -> Substring.Index? {
        var index = start
        while index < text.endIndex, text[index] == " " { index = text.index(after: index) }
        guard index < text.endIndex else { return nil }
        if ["-", "\u{2013}", "\u{2014}"].contains(text[index]) {
            index = text.index(after: index)
        } else if text[index...].lowercased().hasPrefix("to "), let toEnd = text.index(index, offsetBy: 2, limitedBy: text.endIndex) {
            index = toEnd
        } else {
            return nil
        }
        while index < text.endIndex, text[index] == " " { index = text.index(after: index) }
        return index
    }
}

private nonisolated extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
