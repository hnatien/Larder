import SwiftUI

/// A date or quantity stamp: uppercase mono text in a thin box.
public struct Stamp: View {
    @Environment(\.displayScale) private var displayScale
    private let text: String

    /// Creates a stamp with the given text.
    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .stamp()
            .foregroundStyle(LarderColor.ink.primary)
            .padding(.horizontal, LarderSpacing.s)
            .padding(.vertical, LarderSpacing.xs)
            .overlay {
                RoundedRectangle(cornerRadius: LarderRadius.stamp)
                    .strokeBorder(LarderColor.line.strong, lineWidth: 1 / displayScale)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}

#Preview("Stamp") {
    HStack(spacing: LarderSpacing.m) {
        Stamp(text: "14 Oct")
        Stamp(text: "400 g")
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
