import SwiftUI

/// A small capsule badge with an icon and a word, such as "Today" or "Locked". Colour is never the only signal.
public struct Pill: View {
    /// The badge's colour.
    public enum Tone: CaseIterable, Sendable {
        case brand, second, spot, neutral
    }

    private let text: String
    private let systemImage: String?
    private let tone: Tone

    /// Creates a badge.
    public init(_ text: String, systemImage: String? = nil, tone: Tone = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.tone = tone
    }

    private var fill: Color {
        switch tone {
        case .brand: LarderColor.accent.brand
        case .second: LarderColor.accent.second
        case .spot: LarderColor.accent.spot
        case .neutral: LarderColor.surface.sunken
        }
    }

    public var body: some View {
        HStack(spacing: LarderSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(LarderFont.body(.footnote, weight: .semibold))
        .modifier(PillInk(tone: tone))
        .padding(.horizontal, LarderSpacing.s + LarderSpacing.xxs)
        .padding(.vertical, LarderSpacing.xs)
        .background(fill, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct PillInk: ViewModifier {
    let tone: Pill.Tone

    func body(content: Content) -> some View {
        switch tone {
        case .brand, .second: content.foregroundStyle(LarderColor.ink.onAccent)
        case .spot: content.onSpotFill()
        case .neutral: content.foregroundStyle(LarderColor.ink.primary)
        }
    }
}

#Preview("Pill") {
    HStack(spacing: LarderSpacing.s) {
        Pill("Today", tone: .brand)
        Pill("On for tonight", systemImage: "checkmark", tone: .second)
        Pill("Use soon", systemImage: "clock", tone: .spot)
        Pill("Locked", systemImage: "lock", tone: .neutral)
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
