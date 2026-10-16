import SwiftUI

/// The screen's one floating action: an opaque brand capsule so the label keeps its contrast.
/// Place it with `safeAreaInset(edge: .bottom)` so the content can scroll clear of it.
public struct FloatingAction: View {
    private let title: String
    private let systemImage: String
    private let action: () -> Void

    /// Creates a floating action with a visible title.
    public init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(LarderFont.body(.body, weight: .semibold))
                .foregroundStyle(LarderColor.ink.onAccent)
                .padding(.horizontal, LarderSpacing.l)
                .padding(.vertical, LarderSpacing.m)
                .frame(minHeight: LarderButtonStyle.minimumHitTarget)
                .background(LarderColor.accent.brand, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview("FloatingAction") {
    FloatingAction(Copy.Action.addWhatYouHave, systemImage: "plus") {}
        .padding(LarderSpacing.xl)
        .background(LarderColor.surface.canvas)
}
