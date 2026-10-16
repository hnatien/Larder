import SwiftUI

extension View {
    /// Dark ink for text on the mustard spot fill. Mustard stays light in dark mode, so the ink is pinned to its light value.
    func onSpotFill() -> some View {
        foregroundStyle(LarderColor.ink.primary)
            .environment(\.colorScheme, .light)
    }
}

/// A masking-tape tag for leftovers, such as "Chilli, day 2 of 4".
public struct TapeLabel: View {
    private let text: String

    /// Creates a tag with the given text.
    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(LarderFont.body(.footnote, weight: .semibold))
            .onSpotFill()
            .padding(.horizontal, LarderSpacing.m)
            .padding(.vertical, LarderSpacing.xs)
            .background(LarderColor.accent.spot, in: RoundedRectangle(cornerRadius: LarderRadius.stamp))
            .rotationEffect(.degrees(-1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}

#Preview("TapeLabel") {
    VStack(alignment: .leading, spacing: LarderSpacing.m) {
        TapeLabel(text: "Chilli, day 2 of 4")
        TapeLabel(text: "Soup, day 1 of 3")
            .preferredColorScheme(.dark)
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
