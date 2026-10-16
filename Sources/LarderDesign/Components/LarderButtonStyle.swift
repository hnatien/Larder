import SwiftUI

/// Larder's three button weights: filled brand, outlined, and text only. Disabled buttons drop the fill and use tertiary ink.
public struct LarderButtonStyle: ButtonStyle {
    /// Which weight to draw.
    public enum Kind: CaseIterable, Sendable {
        case primary, secondary, quiet
    }

    /// The least a tappable control measures on either side, in points.
    static let minimumHitTarget: CGFloat = 44
    /// How much the primary fill darkens while pressed.
    static let pressedDarkening = 0.08

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
        let kind: Kind
        let configuration: ButtonStyleConfiguration

        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: LarderRadius.field) }

        private var foreground: Color {
            guard isEnabled else { return LarderColor.ink.tertiary }
            return switch kind {
            case .primary: LarderColor.ink.onAccent
            case .secondary: LarderColor.ink.primary
            case .quiet: LarderColor.accent.second
            }
        }

        var body: some View {
            configuration.label
                .font(LarderFont.body(.body, weight: .semibold))
                .foregroundStyle(foreground)
                .underline(kind == .quiet && showButtonShapes)
                .padding(.horizontal, LarderSpacing.l)
                .padding(.vertical, LarderSpacing.m)
                .frame(minWidth: LarderButtonStyle.minimumHitTarget, minHeight: LarderButtonStyle.minimumHitTarget)
                .background {
                    if kind == .primary, isEnabled {
                        shape.fill(LarderColor.accent.brand)
                            .overlay(shape.fill(Color.black.opacity(configuration.isPressed ? LarderButtonStyle.pressedDarkening : 0)))
                    }
                }
                .overlay {
                    if kind == .secondary || (kind == .primary && !isEnabled) {
                        shape.strokeBorder(LarderColor.line.strong, lineWidth: 1 / displayScale)
                    }
                }
                .opacity(pressedOpacity)
                .contentShape(shape)
                .larderAnimation(LarderMotion.tap, value: configuration.isPressed)
        }

        private var pressedOpacity: Double {
            kind == .quiet && isEnabled && configuration.isPressed ? 0.6 : 1
        }
    }
}

public extension ButtonStyle where Self == LarderButtonStyle {
    /// Brand fill with on-accent text.
    static var larderPrimary: LarderButtonStyle { LarderButtonStyle(.primary) }
    /// A strong-line outline with ink text.
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
