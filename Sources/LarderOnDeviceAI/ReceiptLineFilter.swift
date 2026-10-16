import Foundation

/// Picks the product lines out of a receipt's text lines with fixed rules.
nonisolated enum ReceiptLineFilter {
    /// The product lines of `lines` with prices and unit prices removed; weights printed on their own line join the product above.
    ///
    /// Lines before the first priced item (store name, address, date) and from the first total onwards are dropped,
    /// as are payment, card, loyalty, date and time lines, lines that still show a currency symbol, and lines with fewer than three letters.
    static func pantryCandidates(from lines: [String]) -> [String] {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var candidates: [String] = []
        for line in trimmed[itemsStart(in: trimmed)...] {
            if line.contains(totalPattern) { break }
            if line.contains(dropPattern) || line.contains(cardNumberPattern) || line.contains(datePattern) { continue }
            let product = stripPrices(line)
            if product.wholeMatch(of: weightOnlyPattern) != nil {
                if !candidates.isEmpty { candidates[candidates.count - 1] += " \(product)" }
                continue
            }
            guard !product.contains(currencyPattern), letterCount(product) >= 3 else { continue }
            candidates.append(product)
        }
        return candidates
    }

    private static func itemsStart(in lines: [String]) -> Int {
        guard let first = lines.firstIndex(where: { $0.contains(trailingPricePattern) || $0.contains(unitPricePattern) }) else {
            return 0
        }
        let isWeightOnly = stripPrices(lines[first]).wholeMatch(of: weightOnlyPattern) != nil
        return isWeightOnly ? max(first - 1, 0) : first
    }

    private static func stripPrices(_ line: String) -> String {
        line
            .replacing(trailingPricePattern, with: "")
            .replacing(unitPricePattern, with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func letterCount(_ text: String) -> Int {
        text.unicodeScalars.filter(CharacterSet.letters.contains).count
    }

    private static var trailingPricePattern: Regex<Substring> {
        #/(?:^|\s+)-?[$€£¥]?\s?\d{1,6}[.,]\d{2}(?:\s?[$€£¥])?(?:\s+[A-Z*])?\s*$/#
    }

    private static var unitPricePattern: Regex<Substring> {
        #/\s*(?:@|\s[xX×])\s*[$€£¥]?\d+[.,]\d{2}(?:\s*\/\s*[A-Za-z]+)?/#
    }

    private static var weightOnlyPattern: Regex<Substring> {
        #/(?i)\d+(?:[.,]\d+)?\s*(?:kg|g|lb|lbs|oz)/#
    }

    private static var totalPattern: Regex<Substring> {
        #/(?i)\b(?:sub\s?-?total|total|balance\s+due|amount\s+due)\b/#
    }

    private static var dropPattern: Regex<Substring> {
        #/(?i)\b(?:tax|vat|change|cash|tender|visa|maestro|amex|debit|credit|contactless|payment|paid|auth\w*|approved|loyalty|rewards?|points|member\w*|sav(?:ed|ings?)|discount|coupon|receipt|thank\w*|cashier|till|store|tel|phone|www)\b|card\b|\.com\b/#
    }

    private static var cardNumberPattern: Regex<Substring> {
        #/(?:\d[ \-]?){15}\d|[*#]{4,}|[xX]{4,}\d/#
    }

    private static var datePattern: Regex<Substring> {
        #/\b\d{1,2}[\/.\-]\d{1,2}[\/.\-]\d{2,4}\b|\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}:\d{2}\b/#
    }

    private static var currencyPattern: Regex<Substring> {
        #/[$€£¥]/#
    }
}
