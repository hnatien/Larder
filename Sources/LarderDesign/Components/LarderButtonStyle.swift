import SwiftUI

/// Larder's three button weights, all capsules: a filled brand capsule, a tinted capsule, and text only.
/// Disabled buttons drop the fill and use tertiary ink. Primary taps give a light haptic.
public struct LarderButtonStyle: ButtonStyle {
    /// Which weight to draw.
    public enum Kind: CaseIterable, Sendable {
        case primary, secondary, quiet
    }

    /// The least a tappable control measures on either side, in points.
    static let minimumHitTarget: CGFloat = 44
    /// How much the primary fill darkens while pressed.
    static let pressedDarkening = 0.08
    /// How strongly the secondary capsule is tinted with the brand colour.
    static let secondaryTint = 0.12

    private let kind: Kind

    /// Creates a style of the given weight.
    public init(_ kind: Kind) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyledLabel(kind: kind, configuration: configuration)
    }

    private struct StyledLabel: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.displayScale) private var displayScale
        @Environment(\.accessibilityShowButtonShapes) private var showButtonShapes
        @ScaledSpacing(.m) private var verticalPadding
        @ScaledSpacing(.l) private var horizontalPadding
        let kind: Kind
        let configuration: ButtonStyleConfiguration

        private var foreground: Color {
            guard isEnabled else { return LarderColor.ink.tertiary }
            return switch kind {
            case .primary: LarderColor.ink.onAccent
            case .secondary: LarderColor.accent.brand
            case .quiet: LarderColor.accent.second
            }
        }

        var body: some View {
            configuration.label
                .font(LarderFont.body(.body, weight: .semibold))
                .foregroundStyle(foreground)
                .multilineTextAlignment(.center)
                .underline(kind == .quiet && showButtonShapes)
                .padding(.horizontal, kind == .quiet ? LarderSpacing.s : horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(minWidth: LarderButtonStyle.minimumHitTarget, minHeight: LarderButtonStyle.minimumHitTarget)
                .background { fill }
                .overlay {
                    if kind != .quiet, !isEnabled {
                        Capsule().strokeBorder(LarderColor.line.strong, lineWidth: 1 / displayScale)
                    }
                }
                .opacity(pressedOpacity)
                .scaleEffect(configuration.isPressed && kind != .quiet ? 0.98 : 1)
                .contentShape(Capsule())
                .larderAnimation(LarderMotion.tap, value: configuration.isPressed)
                .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in
                    pressed && kind == .primary && isEnabled
                }
        }

        @ViewBuilder private var fill: some View {
            if isEnabled {
                switch kind {
                case .primary:
                    Capsule().fill(LarderColor.accent.brand)
                        .overlay(Capsule().fill(Color.black.opacity(configuration.isPressed ? LarderButtonStyle.pressedDarkening : 0)))
                case .secondary:
                    Capsule().fill(LarderColor.accent.brand.opacity(LarderButtonStyle.secondaryTint * (configuration.isPressed ? 1.8 : 1)))
                case .quiet:
                    EmptyView()
                }
            }
        }

        private var pressedOpacity: Double {
            kind == .quiet && isEnabled && configuration.isPressed ? 0.6 : 1
        }
    }
}

public extension ButtonStyle where Self == LarderButtonStyle {
    /// A brand capsule with on-accent text: the screen's one main action.
    static var larderPrimary: LarderButtonStyle { LarderButtonStyle(.primary) }
    /// A brand-tinted capsule with brand text: a second action.
    static var larderSecondary: LarderButtonStyle { LarderButtonStyle(.secondary) }
    /// Text only, in the second accent.
    static var larderQuiet: LarderButtonStyle { LarderButtonStyle(.quiet) }
}

#Preview("LarderButtonStyle") {
    VStack(alignment: .leading, spacing: LarderSpacing.m) {
        Button(Copy.Action.planMyWeek) {}
            .buttonStyle(.larderPrimary)
        Button(Copy.Action.notNow) {}
            .buttonStyle(.larderSecondary)
        Button(Copy.Action.skip) {}
            .buttonStyle(.larderQuiet)
        Button(Copy.Action.swap) {}
            .buttonStyle(.larderPrimary)
            .disabled(true)
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
