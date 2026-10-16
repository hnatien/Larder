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

/// An opaque raised card with hairline rules at the top and bottom. Never nest one inside another.
public struct PaperCard<Content: View>: View {
    @ScaledSpacing(.l) private var padding
    private let content: Content

    /// Creates a card around the content.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LarderColor.surface.raised)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }
            .clipShape(RoundedRectangle(cornerRadius: LarderRadius.card))
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
