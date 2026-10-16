import SwiftUI

/// A left-aligned section heading in the display face. No eyebrow label above it.
public struct SectionHeading: View {
    private let text: String

    /// Creates a heading with the given text.
    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(LarderFont.display(.title2))
            .foregroundStyle(LarderColor.ink.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("SectionHeading") {
    VStack(alignment: .leading, spacing: LarderSpacing.l) {
        SectionHeading("This week's shelf")
        SectionHeading("Eat first")
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
