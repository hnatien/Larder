import LarderCore
import Observation

/// Where the cook is in a recipe and the timers running along the way.
@Observable
@MainActor
public final class CookingSession {
    public let steps: [RecipeStep]
    public private(set) var stepIndex = 0
    /// Counts completed timers, so views can react to each one.
    public private(set) var finishCount = 0

    private let ingredients: [Ingredient]
    private var timers: [Int: TimerModel] = [:]

    /// Creates a session with one timer for each step that has `timerSeconds`.
    public init(recipe: Recipe, ingredients: [Ingredient], clock: any Clock<Duration> = ContinuousClock()) {
        steps = recipe.steps
        self.ingredients = ingredients
        for (index, step) in recipe.steps.enumerated() {
            guard let seconds = step.timerSeconds, seconds > 0 else { continue }
            let timer = TimerModel(seconds: seconds, clock: clock)
            timer.onFinish = { [weak self] in
                self?.finishCount += 1
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
}
