import LarderCore
import LarderDesign
import SwiftUI

/// The home tab: up to three dinner ideas from what is on the shelves, and a "Pick for me" for tired evenings.
public struct TonightView: View {
    /// Ideas show at most this many reasons each.
    static let reasonLimit = 2

    private let model: TonightModel
    private let onOpenRecipe: (RecipeID) -> Void
    private let onAddToPantry: () -> Void
    @AccessibilityFocusState private var focusedOption: RecipeID?

    /// Creates the tab root; `onAddToPantry` runs from the empty state.
    public init(model: TonightModel, onOpenRecipe: @escaping (RecipeID) -> Void, onAddToPantry: @escaping () -> Void = {}) {
        self.model = model
        self.onOpenRecipe = onOpenRecipe
        self.onAddToPantry = onAddToPantry
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: LarderSpacing.xl) {
                    Text(Copy.Tab.tonight)
                        .font(LarderFont.display(.largeTitle))
                        .foregroundStyle(LarderColor.ink.primary)
                        .accessibilityAddTraits(.isHeader)
                    if let error = model.error {
                        LedgerNotice(error: error, onDismiss: model.clearError)
                    }
                    content(proxy)
                }
                .padding(LarderSpacing.l)
            }
            .background(LarderColor.surface.canvas)
        }
        .task { await model.load() }
    }

    @ViewBuilder private func content(_ proxy: ScrollViewProxy) -> some View {
        if model.isLoading, model.options.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if model.shelvesAreEmpty || model.options.isEmpty {
            EmptyShelf(
                title: model.shelvesAreEmpty ? LedgerCopy.emptyShelvesTitle : LedgerCopy.nothingFits,
                message: model.shelvesAreEmpty ? Copy.Voice.emptyPantry : LedgerCopy.nothingFitsTonight,
                action: .init(title: Copy.Action.addWhatYouHave, perform: onAddToPantry)
            )
        } else {
            Text(LedgerCopy.tonightContext(count: model.options.count))
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                pick(proxy)
            } label: {
                Text(Copy.Action.pickForMe)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.larderPrimary)
            ForEach(model.options, id: \.recipeID) { option in
                TonightCard(
                    option: option,
                    reasons: model.reasons(for: option, limit: Self.reasonLimit),
                    isPicked: model.pickedID == option.recipeID,
                    isCooking: model.cookingID == option.recipeID,
                    onCook: { cook(option) },
                    onOpenRecipe: { onOpenRecipe(option.recipeID) }
                )
                .id(option.recipeID)
                .accessibilityFocused($focusedOption, equals: option.recipeID)
            }
            .larderAnimation(LarderMotion.tap, value: model.pickedID)
        }
    }

    private func pick(_ proxy: ScrollViewProxy) {
        guard let top = model.pickForMe() else { return }
        proxy.scrollTo(top.recipeID, anchor: .top)
        focusedOption = top.recipeID
        AccessibilityNotification.Announcement(LedgerCopy.pickedAnnouncement(top.candidate.recipe.title)).post()
    }

    private func cook(_ option: ScoredRecipe) {
        Task {
            await model.cookTonight(option)
            if model.cookingID == option.recipeID {
                AccessibilityNotification.Announcement(LedgerCopy.cookingTonight(option.candidate.recipe.title)).post()
            }
        }
    }
}

/// One idea: title, minutes, up to two reasons, and the two choices.
private struct TonightCard: View {
    let option: ScoredRecipe
    let reasons: [String]
    let isPicked: Bool
    let isCooking: Bool
    let onCook: () -> Void
    let onOpenRecipe: () -> Void

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: LarderSpacing.m) {
                if isCooking {
                    Stamp(text: LedgerCopy.onForTonight)
                } else if isPicked {
                    Stamp(text: LedgerCopy.picked)
                }
                Text(option.candidate.recipe.title)
                    .font(LarderFont.body(.body, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Stamp(text: Copy.Ledger.minutes(option.candidate.totalMinutes))
                    .accessibilityLabel(Copy.Ledger.spokenMinutes(option.candidate.totalMinutes))
                ForEach(reasons, id: \.self) { reason in
                    ReasonLine(text: reason)
                }
                AdaptiveStack(spacing: LarderSpacing.m, stacksFrom: .xLarge) { buttons }
            }
        }
        .overlay {
            if isPicked {
                RoundedRectangle(cornerRadius: LarderRadius.card)
                    .strokeBorder(LarderColor.accent.brand, lineWidth: 2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var buttons: some View {
        Button(LedgerCopy.cookThis, action: onCook)
            .buttonStyle(.larderPrimary)
            .disabled(isCooking)
        Button(LedgerCopy.seeRecipe, action: onOpenRecipe)
            .buttonStyle(.larderQuiet)
    }
}

#if DEBUG
#Preview("TonightView") {
    TonightView(model: PreviewKitchen.tonightModel(), onOpenRecipe: { _ in })
        .larderTheme()
}

#Preview("TonightView empty") {
    TonightView(model: PreviewKitchen.tonightModel(empty: true), onOpenRecipe: { _ in })
        .larderTheme()
}
#endif
