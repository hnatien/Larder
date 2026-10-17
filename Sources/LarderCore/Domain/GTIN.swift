import Foundation

/// Retail barcode numbers (GTIN-8, UPC-A, EAN-13, GTIN-14), compared in one canonical spelling.
public enum GTIN {
    /// `code` as GTIN-13 when it is a 12-, 13- or 14-digit code (UPC-A gains a leading zero, a GTIN-14 loses one),
    /// an 8-digit code as it is, and `nil` for anything that is not one of those.
    ///
    /// Check digits are not verified: the scanners that produce codes already do.
    public static func normalized(_ code: String) -> String? {
        let digits = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        switch digits.count {
        case 8, 13: return digits
        case 12: return "0" + digits
        case 14 where digits.hasPrefix("0"): return String(digits.dropFirst())
        default: return nil
        }
    }

    /// Every spelling a stored barcode for `code` may have, canonical first; empty when `code` is not a GTIN.
    public static func spellings(of code: String) -> [String] {
        guard let canonical = normalized(code) else { return [] }
        guard canonical.count == 13 else { return [canonical] }
        var spellings = [canonical, "0" + canonical]
        if canonical.hasPrefix("0") { spellings.append(String(canonical.dropFirst())) }
        return spellings
    }
}
