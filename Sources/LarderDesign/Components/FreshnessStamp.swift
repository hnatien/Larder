import SwiftUI

/// A freshness level as a quiet trailing label: its icon and, when known, the best-by date in its tone, relative
/// within a week ("Tomorrow", "2 days ago"), else the date, with the year when it is not this year. Without a date it
/// shows the freshness word. The word is always spoken, and each level has its own icon, so colour is never the only
/// signal.
public struct FreshnessStamp: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    private let style: FreshnessStyle
    private let bestBy: Date?
    private let now: Date

    /// Creates a stamp for a freshness level and optional best-by date; `now` sets what "Tomorrow" counts from.
    public init(level: FreshnessStyle.Level, bestBy: Date?, now: Date = .now) {
        self.style = FreshnessStyle(level)
        self.bestBy = bestBy
        self.now = now
    }

    /// The date, which says how soon on its own, or the word when there is none.
    private var shownText: String {
        bestBy.map { Self.dateText($0, now: now, calendar: calendar, locale: locale) } ?? style.word
    }

    /// Days within which a best-by date reads as relative words.
    static let relativeDays = 6

    /// "Today", "Tomorrow", "In 3 days" or "2 days ago" within a week of `now`; otherwise "23 Oct", or "23 Oct 2027" in
    /// another year.
    public static func dateText(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if abs(days) <= relativeDays {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.dateTimeStyle = .named
            formatter.unitsStyle = .full
            formatter.formattingContext = .beginningOfSentence
            return formatter.localizedString(from: DateComponents(day: days))
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)
        return sameYear ? date.formatted(style) : date.formatted(style.year())
    }

    private var spokenLabel: String {
        guard let bestBy else { return style.word }
        return Copy.Freshness.spoken(word: style.word, bestBy: bestBy.formatted(.dateTime.day().month(.wide)))
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LarderSpacing.xs) {
            Image(systemName: style.symbol)
            Text(shownText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(LarderFont.body(.subheadline, weight: .semibold))
        .foregroundStyle(tone)
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private var tone: Color {
        switch style.level {
        case .fresh: LarderColor.ink.secondary
        case .soon: LarderColor.status(.warning)
        case .today: LarderColor.accent.brand
        case .past: LarderColor.status(.danger)
        }
    }
}

#Preview("FreshnessStamp") {
    VStack(alignment: .leading, spacing: LarderSpacing.m) {
        FreshnessStamp(level: .fresh, bestBy: .now.addingTimeInterval(86_400 * 6))
        FreshnessStamp(level: .soon, bestBy: .now.addingTimeInterval(86_400 * 2))
        FreshnessStamp(level: .today, bestBy: .now)
        FreshnessStamp(level: .past, bestBy: .now.addingTimeInterval(-86_400))
        FreshnessStamp(level: .fresh, bestBy: nil)
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
