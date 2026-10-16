import SwiftUI

/// A 1 px ledger rule.
struct Hairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(LarderColor.line.hairline)
            .frame(height: 1 / displayScale)
            .accessibilityHidden(true)
    }
}

/// An opaque raised card with a hairline outline and continuous corners. Never nest one inside another.
public struct PaperCard<Content: View>: View {
    @Environment(\.displayScale) private var displayScale
    @ScaledSpacing(.l) private var padding
    private let content: Content
    private let usesPadding: Bool

    /// Creates a card around the content; `padded: false` lets the content run to the card's edges.
    public init(padded: Bool = true, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.usesPadding = padded
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LarderRadius.panel, style: .continuous)
    }

    public var body: some View {
        content
            .padding(usesPadding ? padding : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LarderColor.surface.raised, in: shape)
            .clipShape(shape)
            .overlay { shape.strokeBorder(LarderColor.line.hairline, lineWidth: 1 / displayScale) }
    }
}

#Preview("PaperCard") {
    PaperCard {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            Text("Chicken stir fry")
                .font(LarderFont.body(.body, weight: .semibold))
                .foregroundStyle(LarderColor.ink.primary)
            Text("Uses the spinach and the last of the rice.")
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.secondary)
        }
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}

#Preview("PaperCard dark") {
    PaperCard {
        Text("Chicken stir fry")
            .font(LarderFont.body(.body, weight: .semibold))
            .foregroundStyle(LarderColor.ink.primary)
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
    .preferredColorScheme(.dark)
}
