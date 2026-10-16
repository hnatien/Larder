import Observation

/// A countdown that survives page changes; ticks once a second against an injectable clock.
@Observable
@MainActor
public final class TimerModel {
    /// Where the countdown is.
    public enum State: Hashable, Sendable {
        case idle
        case running
        case paused
        case finished
    }

    public let totalSeconds: Int
    public private(set) var remainingSeconds: Int
    public private(set) var state = State.idle
    /// Called once each time the countdown reaches zero.
    public var onFinish: (() -> Void)?

    private let clock: any Clock<Duration>
    private var countdown: Task<Void, Never>?

    /// Creates an idle timer of `seconds`, at least one.
    public init(seconds: Int, clock: any Clock<Duration> = ContinuousClock()) {
        totalSeconds = max(seconds, 1)
        remainingSeconds = max(seconds, 1)
        self.clock = clock
    }

    /// Starts, resumes, or restarts a finished timer.
    public func start() {
        guard state != .running else { return }
        if state == .finished { remainingSeconds = totalSeconds }
        state = .running
        countdown = Task { [weak self] in
            await self?.tickDown()
        }
    }

    /// Stops the countdown and keeps the time left.
    public func pause() {
        guard state == .running else { return }
        countdown?.cancel()
        countdown = nil
        state = .paused
    }

    /// Stops the countdown and returns to the full time.
    public func reset() {
        countdown?.cancel()
        countdown = nil
        remainingSeconds = totalSeconds
        state = .idle
    }

    private func finish() {
        countdown = nil
        remainingSeconds = 0
        state = .finished
        onFinish?()
    }

    private func tickDown() async {
        guard await countDown(on: clock, seconds: remainingSeconds) else { return }
        finish()
    }

    /// Sleeps to a deadline for each second so ticks do not drift; returns whether it reached zero without being cancelled.
    private func countDown<C: Clock>(on clock: C, seconds: Int) async -> Bool where C.Duration == Duration {
        let start = clock.now
        for elapsed in 1...seconds {
            do {
                try await clock.sleep(until: start.advanced(by: .seconds(elapsed)), tolerance: nil)
            } catch {
                return false
            }
            guard !Task.isCancelled else { return false }
            remainingSeconds = seconds - elapsed
        }
        return true
    }
}
