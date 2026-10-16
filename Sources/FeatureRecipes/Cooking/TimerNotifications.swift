import Foundation
import OSLog
import UserNotifications

/// Whether Larder may post a notification when a timer ends.
public enum TimerNotificationPermission: Hashable, Sendable {
    /// The cook has not been asked yet.
    case undetermined
    case allowed
    case denied
}

/// Posts the notification that says a cooking timer ended while Larder was in the background.
public protocol TimerNotifying: AnyObject {
    /// Whether notifications are allowed, without asking.
    func permission() async -> TimerNotificationPermission
    /// Asks the system for permission; returns whether notifications are now allowed.
    func requestPermission() async -> Bool
    /// Schedules the notification `id` for `seconds` from now, replacing any pending one with the same id.
    func schedule(id: String, title: String, body: String, after seconds: Int, playsSound: Bool)
    /// Removes the notification `id`, whether it is still pending or already delivered.
    func cancel(id: String)
}

/// Timer notifications through `UNUserNotificationCenter`.
public final class SystemTimerNotifications: TimerNotifying {
    private nonisolated static let logger = Logger(subsystem: "com.larder.Larder", category: "Timers")

    /// Creates the system notifier; nothing touches the notification center until a method is called.
    public init() {}

    private var center: UNUserNotificationCenter { .current() }

    public func permission() async -> TimerNotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .undetermined
        case .denied: .denied
        default: .allowed
        }
    }

    public func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.logger.error("Notification permission request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    public func schedule(id: String, title: String, body: String, after seconds: Int, playsSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = playsSound ? .default : nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(seconds, 1)), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
            if let error {
                Self.logger.error("Could not schedule a timer notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }
}
