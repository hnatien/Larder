import LarderCore
import SwiftUI

/// One food group on the week shelf: a band filled to its level with a dotted bracket over the comfortable range. Words, never numbers.
public struct ShelfBand: View {
    /// How much of the group the week holds.
    public nonisolated enum Level: CaseIterable, Sendable {
        case light, comfortable, heavy

        /// The word shown and spoken.
        public var word: String {
            switch self {
            case .light: Copy.Shelf.light
            case .comfortable: Copy.Shelf.comfortable
            case .heavy: Copy.Shelf.heavy
            }
        }
    }

    /// Band thickness; food hues are 3:1 against paper, so keep it at 6 pt or more.
    static let barHeight: CGFloat = 8
    /// The fill extent that reads as comfortable, as fractions of the band.
    static let comfortableRange: ClosedRange<Double> = 0.4...0.8
    private static let bracketHeight: CGFloat = 6

    @ScaledSpacing(.xs) private var gap
    private let group: FoodGroup
    private let level: Level

    /// Creates a band for a food group at a level.
    public init(group: FoodGroup, level: Level) {
        self.group = group
        self.level = level
    }

    /// How full the band is drawn: light 30%, comfortable 65%, heavy 100%.
    public nonisolated static func fillFraction(for level: Level) -> Double {
        switch level {
        case .light: 0.3
        case .comfortable: 0.65
        case .heavy: 1
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            HStack(alignment: .firstTextBaseline, spacing: LarderSpacing.s) {
                Text(Copy.Shelf.name(of: group))
                    .font(LarderFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.primary)
                Spacer(minLength: LarderSpacing.s)
                Text(level.word)
                    .stamp()
                    .foregroundStyle(LarderColor.ink.secondary)
            }
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
                    ComfortBracket(range: Self.comfortableRange)
                        .stroke(LarderColor.line.strong, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 4]))
                        .frame(height: Self.bracketHeight)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: LarderRadius.stamp)
                            .fill(LarderColor.surface.sunken)
                        RoundedRectangle(cornerRadius: LarderRadius.stamp)
                            .fill(LarderColor.food(group))
                            .frame(width: proxy.size.width * Self.fillFraction(for: level))
                    }
                    .frame(height: Self.barHeight)
                }
                .flipsForRightToLeftLayoutDirection(true)
            }
            .frame(height: Self.bracketHeight + LarderSpacing.xxs + Self.barHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.Shelf.name(of: group))
        .accessibilityValue(level.word)
    }
}

private struct ComfortBracket: Shape {
    let range: ClosedRange<Double>

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = rect.minX + rect.width * range.lowerBound
        let end = rect.minX + rect.width * range.upperBound
        path.move(to: CGPoint(x: start, y: rect.maxY))
        path.addLine(to: CGPoint(x: start, y: rect.minY))
        path.addLine(to: CGPoint(x: end, y: rect.minY))
        path.addLine(to: CGPoint(x: end, y: rect.maxY))
        return path
    }
}

#Preview("ShelfBand") {
    VStack(spacing: LarderSpacing.l) {
        ShelfBand(group: .produce, level: .light)
        ShelfBand(group: .grains, level: .comfortable)
        ShelfBand(group: .protein, level: .heavy)
        ShelfBand(group: .dairy, level: .comfortable)
        ShelfBand(group: .fats, level: .light)
        ShelfBand(group: .legumes, level: .heavy)
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
