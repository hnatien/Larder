import SwiftUI

/// An empty state, centred: an illustration (or a symbol, or the line-drawn shelf and jar), a heading, a sentence, and
/// up to two actions.
public struct EmptyShelf: View {
    /// One of the empty state's actions.
    public struct Action {
        let title: String
        let perform: () -> Void

        /// Creates an action with a visible title.
        public init(title: String, perform: @escaping () -> Void) {
            self.title = title
            self.perform = perform
        }
    }

    @ScaledMetric(relativeTo: .title2) private var illustrationWidth: CGFloat = 140
    @ScaledMetric(relativeTo: .title2) private var symbolSide: CGFloat = 52
    @ScaledMetric(relativeTo: .title2) private var illustrationSide: CGFloat = 200
    private let title: String
    private let message: String
    private let systemImage: String?
    private let illustration: LarderIllustration?
    private let action: Action?
    private let secondaryAction: Action?

    /// Creates an empty state; `illustration` wins over `systemImage` when the catalogue has it, and without either the
    /// shelf drawing shows.
    public init(
        title: String,
        message: String,
        illustration: LarderIllustration? = nil,
        systemImage: String? = nil,
        action: Action? = nil,
        secondaryAction: Action? = nil
    ) {
        self.title = title
        self.message = message
        self.illustration = illustration
        self.systemImage = systemImage
        self.action = action
        self.secondaryAction = secondaryAction
    }

    public var body: some View {
        VStack(spacing: LarderSpacing.l) {
            artwork
                .accessibilityHidden(true)
            VStack(spacing: LarderSpacing.s) {
                Text(title)
                    .font(LarderFont.display(.title2))
                    .foregroundStyle(LarderColor.ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            if action != nil || secondaryAction != nil {
                VStack(spacing: LarderSpacing.s) {
                    if let action {
                        Button(action: action.perform) {
                            Text(action.title).frame(maxWidth: 320)
                        }
                        .buttonStyle(.larderPrimary)
                    }
                    if let secondaryAction {
                        Button(secondaryAction.title, action: secondaryAction.perform)
                            .buttonStyle(.larderQuiet)
                    }
                }
                .padding(.top, LarderSpacing.xs)
            }
        }
        .padding(.vertical, LarderSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var artwork: some View {
        if let illustration, illustration.isAvailable {
            illustration.image
                .frame(width: illustrationSide, height: illustrationSide)
        } else if let systemImage {
            ZStack {
                Circle()
                    .fill(LarderColor.accent.brand.opacity(0.1))
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(LarderColor.accent.brand)
                    .frame(width: symbolSide, height: symbolSide)
            }
            .frame(width: symbolSide * 2, height: symbolSide * 2)
        } else {
            ShelfLines()
                .stroke(LarderColor.ink.secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: illustrationWidth, height: illustrationWidth * 0.75)
        }
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

#Preview("EmptyShelf with symbol") {
    EmptyShelf(
        title: "No plan yet",
        message: "Plan the week in one tap.",
        systemImage: "calendar.badge.plus",
        action: .init(title: Copy.Action.planMyWeek) {},
        secondaryAction: .init(title: Copy.Action.notNow) {}
    )
    .padding(LarderSpacing.l)
    .background(LarderColor.surface.canvas)
}
