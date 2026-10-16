import LarderCore
import Observation

/// Where the cook is in a recipe and the timers running along the way. A running timer also has a notification
/// scheduled for when it ends, so it is heard while Larder is in the background.
@Observable
@MainActor
public final class CookingSession {
    public let steps: [RecipeStep]
    public private(set) var stepIndex = 0
    /// Counts completed timers, so views can react to each one.
    public private(set) var finishCount = 0
    /// Set when a timer starts before the cook has been asked about notifications; the view explains why, then
    /// calls `requestNotificationPermission()`.
    public var asksForNotificationPermission = false
    /// Whether a timer's notification plays a sound; follows the "Timers flash and vibrate" setting.
    public var notificationsPlaySound = true

    private let recipe: Recipe
    private let ingredients: [Ingredient]
    private let notifications: any TimerNotifying
    private var timers: [Int: TimerModel] = [:]
    /// `nil` until `refreshNotificationPermission()` has read it.
    private var permission: TimerNotificationPermission?

    /// Creates a session with one timer for each step that has `timerSeconds`; `notifications` posts the alert for a
    /// timer that ends in the background.
    public init(
        recipe: Recipe,
        ingredients: [Ingredient],
        notifications: any TimerNotifying,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.recipe = recipe
        steps = recipe.steps
        self.ingredients = ingredients
        self.notifications = notifications
        for (index, step) in recipe.steps.enumerated() {
            guard let seconds = step.timerSeconds, seconds > 0 else { continue }
            let timer = TimerModel(seconds: seconds, clock: clock)
            timer.onFinish = { [weak self] in
                self?.finishCount += 1
            }
            timer.onRun = { [weak self] seconds in
                self?.timerStarted(step: index, seconds: seconds)
            }
            timer.onHalt = { [weak self] in
                guard let self else { return }
                notifications.cancel(id: notificationID(forStep: index))
            }
            timers[index] = timer
        }
    }

    /// Whether the cook is on the first step.
    public var isFirst: Bool { stepIndex == 0 }
    /// Whether the cook is on the last step.
    public var isLast: Bool { stepIndex >= steps.count - 1 }

    /// Moves to `index`, kept within the steps.
    public func go(to index: Int) {
        stepIndex = min(max(index, 0), max(steps.count - 1, 0))
    }

    /// Moves to the next step, if there is one.
    public func next() {
        go(to: stepIndex + 1)
    }

    /// Moves to the previous step, if there is one.
    public func back() {
        go(to: stepIndex - 1)
    }

    /// The timer for the step at `index`, if the step has one.
    public func timer(forStep index: Int) -> TimerModel? {
        timers[index]
    }

    /// Steps other than the current one whose timer is running, paused or finished, in recipe order.
    public var otherActiveTimers: [(step: Int, timer: TimerModel)] {
        timers.keys.sorted()
            .filter { $0 != stepIndex }
            .compactMap { index in timers[index].flatMap { $0.state == .idle ? nil : (index, $0) } }
    }

    /// The ingredients the step at `index` names, as one line.
    public func ingredientSummary(forStep index: Int) -> String? {
        guard steps.indices.contains(index) else { return nil }
        return StepIngredients.summary(for: steps[index].text, in: ingredients)
    }

    /// Stops every timer; call when cooking mode closes.
    public func stopTimers() {
        timers.values.forEach { $0.reset() }
    }

    // MARK: Notifications

    /// Reads whether notifications are allowed, then schedules or asks for any timer already running; call when
    /// cooking mode opens.
    public func refreshNotificationPermission() async {
        permission = await notifications.permission()
        applyPermission()
    }

    /// Shows the system prompt once the cook has read why; schedules the running timers if they allow it.
    public func requestNotificationPermission() async {
        asksForNotificationPermission = false
        permission = await notifications.requestPermission() ? .allowed : .denied
        applyPermission()
    }

    /// The notification identifier for the timer on step `index`.
    func notificationID(forStep index: Int) -> String {
        "timer.\(recipe.id.rawValue.uuidString).\(index)"
    }

    private func timerStarted(step index: Int, seconds: Int) {
        switch permission {
        case .allowed?:
            schedule(step: index, seconds: seconds)
        case .undetermined?:
            asksForNotificationPermission = true
        case .denied?, nil:
            // Before the permission is read, `refreshNotificationPermission()` picks up the running timer.
            break
        }
    }

    private func applyPermission() {
        let running = timers.filter { $0.value.state == .running }
        switch permission {
        case .allowed?:
            for (index, timer) in running {
                schedule(step: index, seconds: timer.remainingSeconds)
            }
        case .undetermined?:
            if !running.isEmpty { asksForNotificationPermission = true }
        case .denied?, nil:
            break
        }
    }

    private func schedule(step index: Int, seconds: Int) {
        notifications.schedule(
            id: notificationID(forStep: index),
            title: recipe.title,
            body: RecipesCopy.timerEnded(step: index + 1),
            after: seconds,
            playsSound: notificationsPlaySound
        )
    }
}
