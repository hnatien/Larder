/// The word and icon that carry a freshness level, so colour is never the only signal.
public nonisolated struct FreshnessStyle: Equatable, Sendable {
    /// How close a pantry item is to its best-by date.
    public enum Level: CaseIterable, Sendable {
        case fresh, soon, today, past
    }

    public let level: Level

    /// Creates the style for a level.
    public init(_ level: Level) {
        self.level = level
    }

    /// The freshness word shown and spoken.
    public var word: String {
        switch level {
        case .fresh: Copy.Freshness.fresh
        case .soon: Copy.Freshness.soon
        case .today: Copy.Freshness.today
        case .past: Copy.Freshness.past
        }
    }

    /// The SF Symbol paired with the word.
    public var symbol: String {
        switch level {
        case .fresh: "leaf"
        case .soon: "clock"
        case .today: "exclamationmark.circle"
        case .past: "archivebox"
        }
    }
}
