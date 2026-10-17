import SwiftUI

/// A freshness word with its icon and tone, and the best-by date when known: relative within a week ("Tomorrow",
/// "2 days ago"), else the date, with the year when it is not this year. Colour is never the only signal.
public struct FreshnessStamp: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var typeSize
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

    private var dateText: String? {
        bestBy.map { Self.dateText($0, now: now, calendar: calendar, locale: locale) }
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
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LarderSpacing.xs))
            : AnyLayout(HStackLayout(spacing: LarderSpacing.s))
        layout { parts }
        .layoutPriority(1)
        .modifier(Tone(level: style.level))
        .padding(.horizontal, LarderSpacing.s)
        .padding(.vertical, LarderSpacing.xs)
        .background(fill, in: RoundedRectangle(cornerRadius: LarderRadius.stamp))
        .overlay {
            RoundedRectangle(cornerRadius: LarderRadius.stamp)
                .strokeBorder(border, lineWidth: style.level == .past ? 1 : 1 / displayScale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    @ViewBuilder private var parts: some View {
        HStack(spacing: LarderSpacing.xs) {
            Image(systemName: style.symbol)
            Text(style.word)
                .fixedSize()
        }
        .font(LarderFont.body(.footnote, weight: .semibold))
        if let dateText {
            Text(dateText)
                .font(LarderFont.body(.footnote))
                .fixedSize()
        }
    }

    private var fill: Color {
        switch style.level {
        case .fresh, .past: Color.clear
        case .soon: LarderColor.accent.spot
        case .today: LarderColor.accent.brand
        }
    }

    private var border: Color {
        switch style.level {
        case .fresh: LarderColor.line.strong
        case .past: LarderColor.status(.danger)
        case .soon, .today: Color.clear
        }
    }

    private struct Tone: ViewModifier {
        let level: FreshnessStyle.Level

        func body(content: Content) -> some View {
            switch level {
            case .fresh: content.foregroundStyle(LarderColor.ink.primary)
            case .soon: content.onSpotFill()
            case .today: content.foregroundStyle(LarderColor.ink.onAccent)
            case .past: content.foregroundStyle(LarderColor.status(.danger))
            }
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
