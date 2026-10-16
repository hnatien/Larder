import SwiftUI

/// A small icon-and-words caption for metadata such as "35 min" or "Uses 4 things you have".
public struct MetaLabel: View {
    private let text: String
    private let systemImage: String
    private let spoken: String?

    /// Creates a caption; `spoken` replaces the visible text for VoiceOver when it reads better.
    public init(_ text: String, systemImage: String, spoken: String? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.spoken = spoken
    }

    public var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(LarderColor.ink.tertiary)
        }
        .labelStyle(MetaLabelStyle())
        .font(LarderFont.body(.subheadline))
        .foregroundStyle(LarderColor.ink.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? text)
    }
}

/// Icon and title close together, aligned on the first line.
private struct MetaLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LarderSpacing.xs) {
            configuration.icon
            configuration.title
        }
    }
}

#Preview("MetaLabel") {
    VStack(alignment: .leading, spacing: LarderSpacing.s) {
        MetaLabel("35 min", systemImage: "clock", spoken: "35 minutes")
        MetaLabel("Uses 4 things you have", systemImage: "refrigerator")
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
