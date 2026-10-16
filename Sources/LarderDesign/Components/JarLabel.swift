import SwiftUI

/// A meal in the week plan: a dish tile, the title, the slot and time, any status badges, and a chevron.
public struct JarLabel<Badges: View>: View {
    private let title: String
    private let minutes: Int
    private let slot: String?
    private let badges: Badges

    /// Creates a meal row; `slot` is the optional meal slot such as "Dinner".
    public init(title: String, minutes: Int, slot: String? = nil, @ViewBuilder badges: () -> Badges) {
        self.title = title
        self.minutes = minutes
        self.slot = slot
        self.badges = badges()
    }

    private var caption: String {
        [slot, Copy.Ledger.minutes(minutes)].compactMap { $0 }.joined(separator: " \u{B7} ")
    }

    public var body: some View {
        HStack(spacing: LarderSpacing.m) {
            RecipeTile(title: title, size: .small)
            VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
                Text(title)
                    .font(LarderFont.body(.body, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption)
                    .font(LarderFont.body(.subheadline))
                    .foregroundStyle(LarderColor.ink.secondary)
                badges
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(LarderFont.body(.footnote, weight: .semibold))
                .foregroundStyle(LarderColor.ink.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([slot, title, Copy.Ledger.spokenMinutes(minutes)].compactMap { $0 }.joined(separator: ", "))
    }
}

public extension JarLabel where Badges == EmptyView {
    /// Creates a meal row without badges.
    init(title: String, minutes: Int, slot: String? = nil) {
        self.init(title: title, minutes: minutes, slot: slot) { EmptyView() }
    }
}

#Preview("JarLabel") {
    VStack(alignment: .leading, spacing: LarderSpacing.m) {
        JarLabel(title: "Lentil soup", minutes: 35, slot: "Dinner")
        JarLabel(title: "Chilli", minutes: 50, slot: "Dinner") {
            Pill("Locked", systemImage: "lock", tone: .neutral)
        }
        JarLabel(title: "Spinach omelette", minutes: 15)
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
