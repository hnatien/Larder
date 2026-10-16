import SwiftUI

/// The one-sentence "why" behind a recommendation, set off by a thin verdigris rule.
public struct ReasonLine: View {
    private let text: String

    /// Creates a reason line with the given sentence.
    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(LarderFont.body(.body))
            .foregroundStyle(LarderColor.ink.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, LarderSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(LarderColor.accent.second)
                    .frame(width: 2)
                    .accessibilityHidden(true)
            }
    }
}

#Preview("ReasonLine") {
    ReasonLine(text: "Spinach is best by Thursday. Dinner tonight uses it.")
        .padding(LarderSpacing.l)
        .background(LarderColor.surface.canvas)
}
