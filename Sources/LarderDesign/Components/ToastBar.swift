import SwiftUI

/// A short confirmation that floats above the content, with an optional action such as Undo.
public struct ToastBar: View {
    /// Whether the toast confirms something or reports that it did not happen.
    public enum Tone: Sendable {
        case done, problem

        var defaultSymbol: String {
            switch self {
            case .done: "checkmark.circle.fill"
            case .problem: "exclamationmark.triangle.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .done: LarderColor.accent.second
            case .problem: LarderColor.status(.warning)
            }
        }
    }

    private let message: String
    private let systemImage: String
    private let tone: Tone
    private let actionTitle: String?
    private let action: (() -> Void)?

    /// Creates a toast; pass `actionTitle` and `action` together for an Undo-style button. Without `systemImage` the
    /// tone picks a check or a warning sign.
    public init(
        _ message: String,
        systemImage: String? = nil,
        tone: Tone = .done,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = message
        self.systemImage = systemImage ?? tone.defaultSymbol
        self.tone = tone
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(spacing: LarderSpacing.m) {
            Image(systemName: systemImage)
                .foregroundStyle(tone.iconColor)
                .accessibilityHidden(true)
            Text(message)
                .font(LarderFont.body(.subheadline, weight: .medium))
                .foregroundStyle(LarderColor.ink.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.larderQuiet)
            }
        }
        .padding(.leading, LarderSpacing.l)
        .padding(.trailing, actionTitle == nil ? LarderSpacing.l : LarderSpacing.xs)
        .padding(.vertical, LarderSpacing.xs)
        .frame(minHeight: 52)
        .background(LarderColor.surface.raised, in: Capsule())
        .overlay { Capsule().strokeBorder(LarderColor.line.hairline, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }
}

/// One toast to show: what it says, how it looks, and an optional action such as Undo.
public struct LarderToast: Identifiable, Equatable {
    /// How long a toast stays when it only confirms.
    public static let plainLifetime: Duration = .seconds(4)
    /// How long a toast with an action such as Undo stays, so there is time to read it and reach the button.
    public static let actionLifetime: Duration = .seconds(8)
    /// How long a toast with an action stays while VoiceOver is running, so it can be found by swiping.
    public static let voiceOverLifetime: Duration = .seconds(20)

    public let id: UUID
    public let message: String
    public let systemImage: String?
    public let tone: ToastBar.Tone
    public let actionTitle: String?
    public let action: (@MainActor () -> Void)?

    /// Creates a toast; `actionTitle` and `action` go together.
    public init(
        id: UUID = UUID(),
        _ message: String,
        systemImage: String? = nil,
        tone: ToastBar.Tone = .done,
        actionTitle: String? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.id = id
        self.message = message
        self.systemImage = systemImage
        self.tone = tone
        self.actionTitle = actionTitle
        self.action = action
    }

    public static func == (lhs: LarderToast, rhs: LarderToast) -> Bool { lhs.id == rhs.id }

    /// How long this toast stays on screen.
    public func lifetime(voiceOverRunning: Bool) -> Duration {
        guard action != nil else { return Self.plainLifetime }
        return voiceOverRunning ? Self.voiceOverLifetime : Self.actionLifetime
    }
}

private struct ToastPresenter: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverRunning
    let toast: LarderToast?
    let onExpire: () -> Void

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if let toast {
                    ToastBar(
                        toast.message,
                        systemImage: toast.systemImage,
                        tone: toast.tone,
                        actionTitle: toast.actionTitle,
                        action: toast.action.map { action in { action() } }
                    )
                    .padding(.horizontal, LarderSpacing.l)
                    .padding(.bottom, LarderSpacing.s)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .task(id: toast?.id) {
                guard let toast else { return }
                AccessibilityNotification.Announcement(toast.message).post()
                do {
                    try await Task.sleep(for: toast.lifetime(voiceOverRunning: voiceOverRunning))
                } catch {
                    return
                }
                onExpire()
            }
            .larderAnimation(LarderMotion.tap, value: toast?.id)
    }
}

public extension View {
    /// Shows `toast` above the bottom edge, announces it, and calls `onExpire` once it has been up long enough:
    /// longer when it carries an action such as Undo, and longer still while VoiceOver is running. Under Reduce Motion
    /// it fades instead of sliding.
    func larderToast(_ toast: LarderToast?, onExpire: @escaping () -> Void) -> some View {
        modifier(ToastPresenter(toast: toast, onExpire: onExpire))
    }
}

#Preview("ToastBar") {
    VStack(spacing: LarderSpacing.m) {
        ToastBar("Added to Wednesday")
        ToastBar("Spinach removed", systemImage: "trash", actionTitle: "Undo") {}
        ToastBar("Couldn't add it to the plan. Try again.", tone: .problem)
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
