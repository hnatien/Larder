import SwiftUI

/// The one inline notice every screen uses: an icon, a plain sentence, an optional action such as Try again, and a
/// dismiss button. The tone sets the icon and a faint tint; the words carry the meaning, never the colour alone.
public struct InlineBanner: View {
    /// What kind of notice it is.
    public enum Tone: Sendable {
        /// Something the user may want to know; nothing failed.
        case info
        /// Something did not work; trying again or another way may help.
        case problem

        var symbol: String {
            switch self {
            case .info: "info.circle"
            case .problem: "exclamationmark.triangle"
            }
        }

        var color: Color {
            switch self {
            case .info: LarderColor.status(.info)
            case .problem: LarderColor.status(.warning)
            }
        }
    }

    /// The banner's own action, such as Try again or Open Settings.
    public struct Action {
        let title: String
        let perform: () -> Void

        /// Creates an action with a visible title.
        public init(title: String, perform: @escaping () -> Void) {
            self.title = title
            self.perform = perform
        }
    }

    /// How strongly the tone tints the banner's background.
    static let tint = 0.08

    @Environment(\.dynamicTypeSize) private var typeSize
    private let message: String
    private let tone: Tone
    private let action: Action?
    private let dismissTitle: String?
    private let onDismiss: (() -> Void)?

    /// Creates a banner; `dismissTitle` and `onDismiss` go together, and either action may be left out.
    public init(
        _ message: String,
        tone: Tone = .problem,
        action: Action? = nil,
        dismissTitle: String? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.message = message
        self.tone = tone
        self.action = action
        self.dismissTitle = dismissTitle
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            Label {
                Text(message)
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: tone.symbol)
                    .foregroundStyle(tone.color)
            }
            if action != nil || onDismiss != nil {
                AdaptiveStack(spacing: LarderSpacing.s, stacksFrom: .accessibility1) {
                    if let action {
                        Button(action.title, action: action.perform)
                            .buttonStyle(.larderSecondary)
                    }
                    if let dismissTitle, let onDismiss {
                        Button(dismissTitle, action: onDismiss)
                            .buttonStyle(.larderQuiet)
                    }
                }
            }
        }
        .padding(LarderSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.color.opacity(Self.tint), in: RoundedRectangle(cornerRadius: LarderRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

#Preview("InlineBanner") {
    VStack(alignment: .leading, spacing: LarderSpacing.l) {
        InlineBanner("The assistant is busy. Your plan is saved.", tone: .info, dismissTitle: "Dismiss") {}
        InlineBanner(
            "Couldn't load tonight's ideas.",
            action: .init(title: "Try again") {},
            dismissTitle: "Dismiss"
        ) {}
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
