import Foundation

/// The upcoming dinners the app hands to the Today widget through the shared App Group container.
nonisolated struct TodaySnapshot: Codable, Hashable, Sendable {
    /// One planned dinner.
    struct Dinner: Codable, Hashable, Sendable {
        /// The start of the day the dinner is planned for.
        var day: Date
        var title: String
        var minutes: Int
    }

    static let appGroupID = "group.com.larder.app"
    static let widgetKind = "TodayWidget"
    /// Opens the app on the Tonight tab; the widget's tap target.
    static let tonightURL = URL(string: "larder://tonight")
    private static let fileName = "today-snapshot.json"

    /// Dinners from today onwards, in date order.
    var dinners: [Dinner]

    /// The snapshot file in the App Group container, or `nil` when the container is unavailable.
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appending(path: fileName, directoryHint: .notDirectory)
    }

    /// The dinner planned for the day containing `date`.
    func dinner(on date: Date, calendar: Calendar) -> Dinner? {
        dinners.first { calendar.isDate($0.day, inSameDayAs: date) }
    }

    /// Up to `limit` dinners on the days after the one containing `date`, in date order.
    func dinners(after date: Date, limit: Int, calendar: Calendar) -> [Dinner] {
        let today = calendar.startOfDay(for: date)
        return Array(dinners.filter { calendar.startOfDay(for: $0.day) > today }.prefix(limit))
    }

    /// Reads the snapshot at `url`; a missing file reads as no dinners.
    static func read(from url: URL) throws -> TodaySnapshot {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return TodaySnapshot(dinners: [])
        }
        return try JSONDecoder().decode(TodaySnapshot.self, from: Data(contentsOf: url))
    }

    /// Replaces the snapshot at `url` in one atomic write.
    func write(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
