import SwiftUI

/// A freshness word with its icon and tone, and the best-by date when known. Colour is never the only signal.
public struct FreshnessStamp: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var typeSize
    private let style: FreshnessStyle
    private let bestBy: Date?

    /// Creates a stamp for a freshness level and optional best-by date.
    public init(level: FreshnessStyle.Level, bestBy: Date?) {
        self.style = FreshnessStyle(level)
        self.bestBy = bestBy
    }

    private var dateText: String? {
        bestBy?.formatted(.dateTime.day().month(.abbreviated))
    }

    private var spokenLabel: String {
        guard let bestBy else { return style.word }
        return Copy.Freshness.spoken(word: style.word, bestBy: bestBy.formatted(.dateTime.day().month(.wide)))
    }

    public var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LarderSpacing.xs))
            : AnyLayout(HStackLayout(spacing: LarderSpacing.s))
        layout { parts }
        .layoutPriority(1)
        .modifier(Tone(level: style.level))
        .padding(.horizontal, LarderSpacing.s)
        .padding(.vertical, LarderSpacing.xs)
        .background(fill, in: RoundedRectangle(cornerRadius: LarderRadius.stamp))
        .overlay {
            RoundedRectangle(cornerRadius: LarderRadius.stamp)
                .strokeBorder(border, lineWidth: 1 / displayScale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    @ViewBuilder private var parts: some View {
        HStack(spacing: LarderSpacing.xs) {
            Image(systemName: style.symbol)
            Text(style.word)
                .fixedSize()
        }
        .font(LarderFont.body(.footnote, weight: .semibold))
        if let dateText {
            Text(dateText)
                .stamp()
                .strikethrough(style.level == .past)
                .fixedSize()
        }
    }

    private var fill: Color {
        switch style.level {
        case .fresh, .past: Color.clear
        case .soon: LarderColor.accent.spot
        case .today: LarderColor.accent.brand
        }
    }

    private var border: Color {
        switch style.level {
        case .fresh, .past: LarderColor.line.strong
        case .soon, .today: Color.clear
        }
    }

    private struct Tone: ViewModifier {
        let level: FreshnessStyle.Level

        func body(content: Content) -> some View {
            switch level {
            case .fresh: content.foregroundStyle(LarderColor.ink.primary)
            case .soon: content.onSpotFill()
            case .today: content.foregroundStyle(LarderColor.ink.onAccent)
            case .past: content.foregroundStyle(LarderColor.ink.secondary)
            }
        }
    }
}

#Preview("FreshnessStamp") {
    VStack(alignment: .leading, spacing: LarderSpacing.m) {
        FreshnessStamp(level: .fresh, bestBy: .now.addingTimeInterval(86_400 * 6))
        FreshnessStamp(level: .soon, bestBy: .now.addingTimeInterval(86_400 * 2))
        FreshnessStamp(level: .today, bestBy: .now)
        FreshnessStamp(level: .past, bestBy: .now.addingTimeInterval(-86_400))
        FreshnessStamp(level: .fresh, bestBy: nil)
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
