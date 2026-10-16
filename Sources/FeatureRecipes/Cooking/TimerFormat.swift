import Foundation

/// How a time left is written and spoken.
nonisolated enum TimerFormat {
    /// "04:05", or "1:04:05" from an hour up.
    static func clock(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        let rest = seconds % 60
        let pair = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
        return hours > 0 ? "\(hours):\(pair(minutes)):\(pair(rest))" : "\(pair(minutes)):\(pair(rest))"
    }

    /// "4 minutes, 5 seconds" for VoiceOver.
    static func spoken(_ seconds: Int) -> String {
        Duration.seconds(max(seconds, 0)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
