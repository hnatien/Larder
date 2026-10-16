import SwiftUI

/// A short confirmation that floats above the content, with an optional action such as Undo.
public struct ToastBar: View {
    private let message: String
    private let systemImage: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    /// Creates a toast; pass `actionTitle` and `action` together for an Undo-style button.
    public init(_ message: String, systemImage: String = "checkmark.circle.fill", actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(spacing: LarderSpacing.m) {
            Image(systemName: systemImage)
                .foregroundStyle(LarderColor.accent.second)
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

#Preview("ToastBar") {
    VStack(spacing: LarderSpacing.m) {
        ToastBar("Added to Wednesday")
        ToastBar("Spinach removed", systemImage: "trash", actionTitle: "Undo") {}
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
