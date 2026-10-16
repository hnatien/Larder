import SwiftUI

/// An empty state: a line-drawn shelf and jar, a heading, a sentence and an optional action.
public struct EmptyShelf: View {
    /// The empty state's single action.
    public struct Action {
        let title: String
        let perform: () -> Void

        /// Creates an action with a visible title.
        public init(title: String, perform: @escaping () -> Void) {
            self.title = title
            self.perform = perform
        }
    }

    @ScaledMetric(relativeTo: .title2) private var illustrationWidth: CGFloat = 160
    private let title: String
    private let message: String
    private let action: Action?

    /// Creates an empty state.
    public init(title: String, message: String, action: Action? = nil) {
        self.title = title
        self.message = message
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.l) {
            ShelfLines()
                .stroke(LarderColor.ink.secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: illustrationWidth, height: illustrationWidth * 0.75)
                .accessibilityHidden(true)
            SectionHeading(title)
            Text(message)
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.larderPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// Three shelf boards with a jar standing on the middle one.
private struct ShelfLines: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let boards: [CGFloat] = [0.2, 0.55, 0.9]
        for fraction in boards {
            let y = rect.minY + rect.height * fraction
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        let shelfY = rect.minY + rect.height * boards[1]
        let jarWidth = rect.width * 0.22
        let jarLeft = rect.minX + rect.width * 0.55
        let jarRight = jarLeft + jarWidth
        let neckInset = jarWidth * 0.14
        let bodyTop = shelfY - rect.height * 0.24
        let lidTop = bodyTop - rect.height * 0.07
        path.move(to: CGPoint(x: jarLeft + neckInset, y: lidTop))
        path.addLine(to: CGPoint(x: jarRight - neckInset, y: lidTop))
        path.addLine(to: CGPoint(x: jarRight - neckInset, y: bodyTop))
        path.addLine(to: CGPoint(x: jarRight, y: bodyTop + rect.height * 0.04))
        path.addLine(to: CGPoint(x: jarRight, y: shelfY))
        path.move(to: CGPoint(x: jarLeft + neckInset, y: lidTop))
        path.addLine(to: CGPoint(x: jarLeft + neckInset, y: bodyTop))
        path.addLine(to: CGPoint(x: jarLeft, y: bodyTop + rect.height * 0.04))
        path.addLine(to: CGPoint(x: jarLeft, y: shelfY))
        return path
    }
}

#Preview("EmptyShelf") {
    EmptyShelf(
        title: "Nothing on the shelves",
        message: Copy.Voice.emptyPantry,
        action: .init(title: Copy.Action.addWhatYouHave) {}
    )
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
