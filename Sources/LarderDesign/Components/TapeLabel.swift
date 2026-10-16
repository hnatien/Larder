import SwiftUI

extension View {
    /// Dark ink for text on the mustard spot fill. Mustard stays light in dark mode, so the ink is pinned to its light value.
    func onSpotFill() -> some View {
        foregroundStyle(LarderColor.ink.primary)
            .environment(\.colorScheme, .light)
    }
}

/// A leftovers row, such as "Chilli, day 2 of 4": a repeat icon and the words, on a mustard tint.
public struct TapeLabel: View {
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 44
    private let text: String

    /// Creates a tag with the given text.
    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: LarderSpacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: LarderRadius.tile, style: .continuous)
                    .fill(LarderColor.accent.spot)
                Image(systemName: "arrow.2.squarepath")
                    .font(LarderFont.body(.body, weight: .semibold))
                    .onSpotFill()
            }
            .frame(width: iconSide, height: iconSide)
            .accessibilityHidden(true)
            Text(text)
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
