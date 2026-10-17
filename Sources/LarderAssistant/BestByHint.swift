import Foundation

/// Turns best-by wording copied from pantry text, such as "exp friday", "use by 12/10" or "use soon", into a day.
///
/// The models copy the wording as written and never compute dates, so the date is worked out here with fixed rules.
public enum BestByHint {
    /// Days "use soon" stands for: the edge of the pantry's Use soon list.
    static let soonDays = 3
    /// A written day and month this many days or more in the past means next year's.
    static let rollForwardDays = 31

    /// The start of the day `hint` names, counted from `now`; `nil` when it names no day Larder can work out.
    ///
    /// Numeric dates follow `locale`'s day and month order unless only the other order is a real date; a date without
    /// a year is this year's, or next year's when it is a month or more past. A weekday means the next one, today included.
    public static func date(from hint: String?, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> Date? {
        guard let hint else { return nil }
        let text = hint.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var calendar = calendar
        calendar.locale = locale
        let today = calendar.startOfDay(for: now)
        func later(_ days: Int) -> Date? { calendar.date(byAdding: .day, value: days, to: today) }

        if let date = isoDate(in: text, calendar: calendar) ?? numericDate(in: text, today: today, calendar: calendar, locale: locale)
            ?? namedMonthDate(in: text, today: today, calendar: calendar) {
            return date
        }
        if let match = text.firstMatch(of: #/(\d{1,3})\s*(?:days?|d)\b/#), let count = Int(match.output.1) {
            return later(count)
        }
        let words = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if words.contains("today") || words.contains("tonight") { return today }
        if words.contains("tomorrow") { return later(1) }
        if text.contains("next week") { return later(7) }
        if let weekday = words.lazy.compactMap({ weekdayNumber($0, calendar: calendar) }).first {
            return calendar.nextDate(
                after: today.addingTimeInterval(-1),
                matching: DateComponents(hour: 0, minute: 0, second: 0, weekday: weekday),
                matchingPolicy: .nextTime
            )
        }
        if words.contains("soon") { return later(soonDays) }
        return nil
    }

    private static func isoDate(in text: String, calendar: Calendar) -> Date? {
        guard let match = text.firstMatch(of: #/\b(\d{4})-(\d{1,2})-(\d{1,2})\b/#),
              let year = Int(match.output.1), let month = Int(match.output.2), let day = Int(match.output.3)
        else { return nil }
        return makeDay(year: year, month: month, day: day, calendar: calendar)
    }

    private static func numericDate(in text: String, today: Date, calendar: Calendar, locale: Locale) -> Date? {
        guard let match = text.firstMatch(of: #/\b(\d{1,2})[\/.\-](\d{1,2})(?:[\/.\-](\d{2}|\d{4}))?\b/#),
              let first = Int(match.output.1), let second = Int(match.output.2)
        else { return nil }
        let year = match.output.3.flatMap { Int($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
        let dayFirst = isDayFirst(locale)
        let orders = dayFirst ? [(second, first), (first, second)] : [(first, second), (second, first)]
        for (month, day) in orders where (1...12).contains(month) && (1...31).contains(day) {
            if let year { return makeDay(year: year, month: month, day: day, calendar: calendar) }
            return withoutYear(month: month, day: day, today: today, calendar: calendar)
        }
        return nil
    }

    private static func namedMonthDate(in text: String, today: Date, calendar: Calendar) -> Date? {
        let tokens = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        for (index, token) in tokens.enumerated() {
            guard let month = monthNumber(token, calendar: calendar) else { continue }
            let neighbours = [index - 1, index + 1].filter(tokens.indices.contains).map { tokens[$0] }
            let dayNumber = neighbours.lazy.compactMap { Int($0.prefix(while: \.isNumber)) }.first { (1...31).contains($0) }
            if let dayNumber {
                return withoutYear(month: month, day: dayNumber, today: today, calendar: calendar)
            }
        }
        return nil
    }

    private static func withoutYear(month: Int, day dayNumber: Int, today: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: today)
        guard let date = makeDay(year: year, month: month, day: dayNumber, calendar: calendar) else { return nil }
        let daysPast = calendar.dateComponents([.day], from: date, to: today).day ?? 0
        return daysPast >= rollForwardDays ? makeDay(year: year + 1, month: month, day: dayNumber, calendar: calendar) : date
    }

    /// The day, or `nil` when the parts do not make one, such as 31 February.
    private static func makeDay(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components).map(calendar.startOfDay)
    }

    private static func isDayFirst(_ locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "M/d"
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M") else { return false }
        return day < month
    }

    private static func weekdayNumber(_ word: String, calendar: Calendar) -> Int? {
        guard word.count >= 3 else { return nil }
        let names = [calendar.weekdaySymbols, calendar.shortWeekdaySymbols, englishWeekdays]
        for list in names {
            if let index = list.firstIndex(where: { name in
                let name = name.lowercased().trimmingCharacters(in: .punctuationCharacters)
                return name == word || (name.hasPrefix(word) && word.count >= 3)
            }) {
                return index + 1
            }
        }
        return nil
    }

    private static func monthNumber(_ word: String, calendar: Calendar) -> Int? {
        guard word.count >= 3, word.allSatisfy(\.isLetter) else { return nil }
        let names = [calendar.monthSymbols, calendar.shortMonthSymbols, englishMonths]
        for list in names {
            if let index = list.firstIndex(where: { name in
                let name = name.lowercased().trimmingCharacters(in: .punctuationCharacters)
                return name == word || (name.hasPrefix(word) && word.count >= 3)
            }) {
                return index + 1
            }
        }
        return nil
    }

    private static let englishWeekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let englishMonths = [
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december",
    ]
}
