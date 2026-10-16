import SwiftUI

/// A row that stacks vertically from a Dynamic Type size, so its controls wrap instead of shrinking or overflowing.
public struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let verticalAlignment: HorizontalAlignment
    private let spacing: CGFloat
    private let stacksFrom: DynamicTypeSize
    private let content: Content

    /// Creates a row; `alignment` places the items once they stack, which starts at `stacksFrom`.
    public init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat,
        stacksFrom: DynamicTypeSize = .accessibility1,
        @ViewBuilder content: () -> Content
    ) {
        self.verticalAlignment = alignment
        self.spacing = spacing
        self.stacksFrom = stacksFrom
        self.content = content()
    }

    public var body: some View {
        let layout = typeSize >= stacksFrom
            ? AnyLayout(VStackLayout(alignment: verticalAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}
