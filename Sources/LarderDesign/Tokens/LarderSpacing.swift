import SwiftUI

/// The 4 pt spacing scale.
public nonisolated enum LarderSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
    public static let huge: CGFloat = 64

    /// A named step on the scale.
    public enum Step: CaseIterable, Sendable {
        case xxs, xs, s, m, l, xl, xxl, xxxl, huge

        /// The step's size in points at the default Dynamic Type size.
        public var points: CGFloat {
            switch self {
            case .xxs: LarderSpacing.xxs
            case .xs: LarderSpacing.xs
            case .s: LarderSpacing.s
            case .m: LarderSpacing.m
            case .l: LarderSpacing.l
            case .xl: LarderSpacing.xl
            case .xxl: LarderSpacing.xxl
            case .xxxl: LarderSpacing.xxxl
            case .huge: LarderSpacing.huge
            }
        }
    }
}

/// A spacing step that scales with Dynamic Type: `@ScaledSpacing(.m) private var gap`.
@propertyWrapper
public struct ScaledSpacing: DynamicProperty {
    @ScaledMetric private var points: CGFloat

    /// Creates a scaled step that follows the given text style.
    public init(_ step: LarderSpacing.Step, relativeTo style: Font.TextStyle = .body) {
        _points = ScaledMetric(wrappedValue: step.points, relativeTo: style)
    }

    public var wrappedValue: CGFloat { points }
}

/// The corner radius scale.
public nonisolated enum LarderRadius {
    public static let stamp: CGFloat = 2
    public static let field: CGFloat = 8
    public static let card: CGFloat = 12
    public static let sheet: CGFloat = 24
    /// For glass controls only.
    public static let pill: CGFloat = .infinity
}
