import SwiftUI

/// Durations and curves. One bounce exists: `stamped`.
public nonisolated enum LarderMotion {
    /// Seconds for a state change.
    public static let state: TimeInterval = 0.12
    /// Seconds for a navigation transition.
    public static let navigation: TimeInterval = 0.22
    /// Seconds for a sheet.
    public static let sheet: TimeInterval = 0.36

    public static let tap: Animation = .snappy(duration: 0.28)
    public static let layout: Animation = .smooth(duration: 0.4)
    /// The save stamp; the only bounce in the app.
    public static let stamped: Animation = .bouncy
    /// Replaces every other curve under Reduce Motion.
    public static let reduced: Animation = .easeOut(duration: state)

    /// The animation to run: the requested one, or `reduced` when Reduce Motion is on.
    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }
}

private struct LarderAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(LarderMotion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}

public extension View {
    /// Animates changes of `value`, swapping in a short ease-out with no bounce under Reduce Motion.
    func larderAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(LarderAnimation(animation: animation, value: value))
    }
}
