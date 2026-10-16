import Foundation

/// Plain-text helpers for page markup; a scanner, not an HTML parser.
nonisolated enum HTMLText {
    private static let skippedElements = ["script", "style", "noscript", "head", "svg", "template", "iframe"]
    private static let blockElements: Set<String> = [
        "p", "div", "br", "li", "ul", "ol", "tr", "table", "section", "article", "header", "footer", "main", "nav",
        "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "dd", "dt",
    ]
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "\u{2013}", "mdash": "\u{2014}",
        "frac12": "\u{BD}", "frac14": "\u{BC}", "frac34": "\u{BE}", "deg": "\u{B0}", "rsquo": "\u{2019}", "lsquo": "\u{2018}",
        "rdquo": "\u{201D}", "ldquo": "\u{201C}", "hellip": "\u{2026}",
    ]

    /// The text a reader would see, block elements on their own lines, cut to at most `limit` characters.
    static func visibleText(from html: String, limit: Int) -> String {
        var output = ""
        var length = 0
        let budget = limit.multipliedReportingOverflow(by: 2).overflow ? Int.max : limit * 2
        var index = html.startIndex
        while index < html.endIndex, length < budget {
            guard html[index] == "<" else {
                output.append(html[index])
                length += 1
                index = html.index(after: index)
                continue
            }
            if html[index...].hasPrefix("<!--") {
                index = html.range(of: "-->", range: index..<html.endIndex)?.upperBound ?? html.endIndex
                continue
            }
            guard let close = html[index...].firstIndex(of: ">") else { break }
            let tag = html[html.index(after: index)..<close]
            let isClosing = tag.first == "/"
            let name = tag.drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber }.lowercased()
            index = html.index(after: close)
            if !isClosing, skippedElements.contains(name) {
                index = html.range(of: "</\(name)", options: .caseInsensitive, range: index..<html.endIndex)
                    .flatMap { html[$0.upperBound...].firstIndex(of: ">") }
                    .map { html.index(after: $0) } ?? html.endIndex
            } else if blockElements.contains(name) {
                output.append("\n")
                length += 1
            }
        }
        return String(collapsingWhitespace(decodeEntities(output)).prefix(limit))
    }

    /// `text` with tags removed and entities decoded, for short fields such as an instruction.
    static func plain(_ text: String) -> String {
        visibleText(from: text, limit: .max).replacing("\n", with: " ")
    }

    /// Decodes named and numeric character references.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "&", let semicolon = text[index...].prefix(10).firstIndex(of: ";") else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }
            let body = text[text.index(after: index)..<semicolon]
            if let decoded = decode(body) {
                result.append(decoded)
                index = text.index(after: semicolon)
            } else {
                result.append("&")
                index = text.index(after: index)
            }
        }
        return result
    }

    private static func decode(_ body: Substring) -> String? {
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            return value.flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
        }
        return namedEntities[String(body)]
    }

    private static func collapsingWhitespace(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
