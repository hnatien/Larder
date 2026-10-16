import SwiftUI

/// The meal tag: a mono slot and time caption over the meal title, like a label on a jar.
public struct JarLabel: View {
    /// The tag's ink.
    public enum Tone: CaseIterable, Sendable {
        case ink, brand, second
    }

    @ScaledSpacing(.xs) private var inset
    private let title: String
    private let minutes: Int
    private let tone: Tone
    private let slot: String?

    /// Creates a tag for a meal; `slot` is the optional meal slot such as "Dinner".
    public init(title: String, minutes: Int, tone: Tone = .ink, slot: String? = nil) {
        self.title = title
        self.minutes = minutes
        self.tone = tone
        self.slot = slot
    }

    private var caption: String {
        [slot, Copy.Ledger.minutes(minutes)].compactMap { $0 }.joined(separator: " \u{B7} ")
    }

    private var foreground: Color {
        tone == .ink ? LarderColor.ink.primary : LarderColor.ink.onAccent
    }

    private var fill: Color {
        switch tone {
        case .ink: LarderColor.surface.sunken
        case .brand: LarderColor.accent.brand
        case .second: LarderColor.accent.second
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
            Text(caption)
                .stamp()
            Text(title)
                .font(LarderFont.body(.body, weight: .semibold))
        }
        .foregroundStyle(foreground)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, LarderSpacing.s)
        .padding(.vertical, inset + LarderSpacing.xxs)
        .background(fill, in: RoundedRectangle(cornerRadius: LarderRadius.stamp))
        .overlay {
            if tone == .ink {
                RoundedRectangle(cornerRadius: LarderRadius.stamp)
                    .strokeBorder(LarderColor.line.strong, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([slot, title, Copy.Ledger.spokenMinutes(minutes)].compactMap { $0 }.joined(separator: ", "))
    }
}

#Preview("JarLabel") {
    VStack(alignment: .leading, spacing: LarderSpacing.m) {
        JarLabel(title: "Lentil soup", minutes: 35, tone: .ink, slot: "Dinner")
        JarLabel(title: "Chilli", minutes: 50, tone: .brand, slot: "Dinner")
        JarLabel(title: "Spinach omelette", minutes: 15, tone: .second)
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
