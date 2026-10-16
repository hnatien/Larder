import LarderDesign
import OSLog
import SwiftUI
import WidgetKit

/// Tonight's planned dinner on paper, with its minutes stamped, or a quiet "Nothing planned".
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodaySnapshot.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(LarderColor.surface.canvas, for: .widget)
        }
        .configurationDisplayName(Copy.Tab.tonight)
        .description(String(localized: "Tonight's dinner from your Ledger."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

nonisolated struct TodayEntry: TimelineEntry {
    let date: Date
    /// `nil` when nothing is planned for the entry's day.
    let dinner: TodaySnapshot.Dinner?
}

/// Reads the snapshot the app writes and refreshes at the next midnight, when "tonight" changes.
nonisolated struct TodayProvider: TimelineProvider {
    private static let logger = Logger(subsystem: "com.larder.Larder.Widgets", category: "TodaySnapshot")

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, dinner: TodaySnapshot.Dinner(day: .now, title: "Chickpea and spinach stew", minutes: 30))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.current
        let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
        completion(Timeline(entries: [entry(at: now)], policy: midnight.map(TimelineReloadPolicy.after) ?? .atEnd))
    }

    /// An unreadable snapshot shows as "Nothing planned" until the app writes a new one.
    private func entry(at date: Date) -> TodayEntry {
        guard let url = TodaySnapshot.fileURL else { return TodayEntry(date: date, dinner: nil) }
        do {
            let snapshot = try TodaySnapshot.read(from: url)
            return TodayEntry(date: date, dinner: snapshot.dinner(on: date, calendar: .current))
        } catch {
            Self.logger.error("Could not read the Today snapshot: \(String(describing: type(of: error)), privacy: .public)")
            return TodayEntry(date: date, dinner: nil)
        }
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            Text(Copy.Tab.tonight)
                .stamp()
                .foregroundStyle(LarderColor.ink.secondary)
            if let dinner = entry.dinner {
                Text(dinner.title)
                    .font(LarderFont.display(.title3))
                    .foregroundStyle(LarderColor.ink.primary)
                    .lineLimit(3)
                Spacer(minLength: 0)
                Stamp(text: Copy.Ledger.minutes(dinner.minutes))
                    .accessibilityLabel(Copy.Ledger.spokenMinutes(dinner.minutes))
            } else {
                Text(String(localized: "Nothing planned"))
                    .font(LarderFont.display(.title3))
                    .foregroundStyle(LarderColor.ink.primary)
                Spacer(minLength: 0)
                Text(String(localized: "Open Larder for three ideas."))
                    .font(LarderFont.body(.footnote))
                    .foregroundStyle(LarderColor.ink.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
