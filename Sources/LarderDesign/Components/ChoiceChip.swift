import SwiftUI

/// A capsule chip that toggles a choice, with a check when chosen and the selected trait. Selection shows by a
/// check and weight as well as colour.
public struct ChoiceChip: View {
    @Environment(\.displayScale) private var displayScale
    private let title: String
    private let systemImage: String?
    private let isSelected: Bool
    private let action: () -> Void

    /// Creates a chip; `systemImage` shows before the title when not selected.
    public init(_ title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // Both states lay out underneath, so the chip keeps one width as it toggles and its row never reflows.
            ZStack {
                Group {
                    label(selected: true)
                    label(selected: false)
                }
                .hidden()
                .accessibilityHidden(true)
                label(selected: isSelected)
            }
            .foregroundStyle(isSelected ? LarderColor.ink.onAccent : LarderColor.ink.primary)
            .padding(.horizontal, LarderSpacing.m)
            .padding(.vertical, LarderSpacing.s + LarderSpacing.xxs)
            .frame(minHeight: 44)
            .background(isSelected ? LarderColor.accent.brand : LarderColor.surface.raised, in: Capsule())
            .overlay {
                if !isSelected {
                    Capsule().strokeBorder(LarderColor.line.strong, lineWidth: 1 / displayScale)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func label(selected: Bool) -> some View {
        HStack(spacing: LarderSpacing.xs) {
            if selected {
                Image(systemName: "checkmark")
                    .font(LarderFont.body(.subheadline, weight: .bold))
                    .accessibilityHidden(true)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(LarderFont.body(.body, weight: selected ? .semibold : .regular))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Lays its children out left to right, wrapping onto new lines like words in a sentence.
public struct ChipFlow: Layout {
    private let spacing: CGFloat

    /// Creates a flow with the same gap between chips and between lines.
    public init(spacing: CGFloat = LarderSpacing.s) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > width {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            if !current.indices.isEmpty, current.width + spacing + size.width > width {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
            current.sizes.append(size)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

#Preview("ChoiceChip") {
    @Previewable @State var chosen: Set<String> = ["Sesame"]
    ChipFlow {
        ForEach(["Peanuts", "Tree nuts", "Milk", "Eggs", "Wheat", "Sesame"], id: \.self) { name in
            ChoiceChip(name, isSelected: chosen.contains(name)) {
                if chosen.contains(name) { chosen.remove(name) } else { chosen.insert(name) }
            }
        }
    }
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
