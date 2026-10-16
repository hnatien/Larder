import LarderCore
import LarderDesign
import SwiftUI

/// The home tab: tonight's dinner when one is planned, and pantry-first ideas three at a time.
public struct TonightView: View {
    /// Ideas show at most this many reasons each.
    static let reasonLimit = 2

    private let model: TonightModel
    private let onOpenRecipe: (RecipeID) -> Void
    private let onStartCooking: (RecipeID) -> Void
    private let onAddToPantry: () -> Void
    private let onBrowseRecipes: (() -> Void)?
    private let onOpenSettings: (() -> Void)?

    /// Creates the tab root. `onAddToPantry` and `onBrowseRecipes` run from the empty state; `onOpenSettings` adds
    /// the Settings button.
    public init(
        model: TonightModel,
        onOpenRecipe: @escaping (RecipeID) -> Void,
        onStartCooking: @escaping (RecipeID) -> Void = { _ in },
        onAddToPantry: @escaping () -> Void = {},
        onBrowseRecipes: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.model = model
        self.onOpenRecipe = onOpenRecipe
        self.onStartCooking = onStartCooking
        self.onAddToPantry = onAddToPantry
        self.onBrowseRecipes = onBrowseRecipes
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LarderSpacing.xl) {
                    if let error = model.error {
                        LedgerNotice(error: error, onDismiss: model.clearError)
                    }
                    if let dinner = model.dinner {
                        DinnerCard(dinner: dinner) { onStartCooking(dinner.recipeID) } onOpenRecipe: {
                            onOpenRecipe(dinner.recipeID)
                        }
                    }
                    content
                }
                .padding(.horizontal, LarderSpacing.l)
                .padding(.bottom, LarderSpacing.xl)
            }
            .background(LarderColor.surface.canvas)
            .navigationTitle(Copy.Tab.tonight)
            .navigationSubtitle(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .settingsButton(onOpenSettings)
            .refreshable { await model.load() }
        }
        .task { await model.load() }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading, model.options.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, LarderSpacing.xxl)
        } else if model.shelvesAreEmpty || model.options.isEmpty {
            EmptyShelf(
                title: model.shelvesAreEmpty ? LedgerCopy.emptyShelvesTitle : LedgerCopy.nothingFits,
                message: model.shelvesAreEmpty ? Copy.Voice.emptyPantry : LedgerCopy.nothingFitsTonight,
                illustration: .tonight,
                systemImage: "refrigerator",
                action: .init(title: Copy.Action.addWhatYouHave, perform: onAddToPantry),
                secondaryAction: onBrowseRecipes.map { .init(title: LedgerCopy.browseRecipes, perform: $0) }
            )
        } else {
            VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                SectionHeading(model.dinner == nil ? LedgerCopy.ideasTitle : LedgerCopy.otherIdeasTitle)
                Text(LedgerCopy.ideasDetail)
                    .font(LarderFont.body(.subheadline))
                    .foregroundStyle(LarderColor.ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.options, id: \.recipeID) { option in
                TonightCard(
                    option: option,
                    reasons: model.reasons(for: option, limit: Self.reasonLimit),
                    isCooking: model.cookingID == option.recipeID,
                    onCook: { cook(option) },
                    onStartCooking: { onStartCooking(option.recipeID) },
                    onOpenRecipe: { onOpenRecipe(option.recipeID) }
                )
                .transition(.opacity)
            }
            .larderAnimation(LarderMotion.layout, value: model.page)
            if model.hasOtherIdeas {
                Button {
                    model.showOtherIdeas()
                } label: {
                    Label(Copy.Action.otherIdeas, systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.larderSecondary)
                .sensoryFeedback(.selection, trigger: model.page)
            }
        }
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

/// Tonight's planned dinner, first on the screen, with the way to start cooking it.
private struct DinnerCard: View {
    let dinner: TonightDinner
    let onStartCooking: () -> Void
    let onOpenRecipe: () -> Void

    var body: some View {
        PaperCard(padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                RecipeTile(title: dinner.title, size: .banner)
                VStack(alignment: .leading, spacing: LarderSpacing.m) {
                    Pill(LedgerCopy.tonightsDinner, systemImage: "fork.knife", tone: .brand)
                    Text(dinner.title)
                        .font(LarderFont.display(.title2))
                        .foregroundStyle(LarderColor.ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    MetaLabel(Copy.Ledger.minutes(dinner.minutes), systemImage: "clock", spoken: Copy.Ledger.spokenMinutes(dinner.minutes))
                    AdaptiveStack(spacing: LarderSpacing.s, stacksFrom: .xLarge) {
                        Button(action: onStartCooking) {
                            Label(LedgerCopy.startCooking, systemImage: "flame")
                        }
                        .buttonStyle(.larderPrimary)
                        Button(LedgerCopy.seeRecipe, action: onOpenRecipe)
                            .buttonStyle(.larderQuiet)
                    }
                }
                .padding(LarderSpacing.l)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One idea: a dish band, the title, time, up to two reasons, and what to do with it.
private struct TonightCard: View {
    let option: ScoredRecipe
    let reasons: [String]
    let isCooking: Bool
    let onCook: () -> Void
    let onStartCooking: () -> Void
    let onOpenRecipe: () -> Void

    private var minutes: Int { option.candidate.totalMinutes }

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: LarderSpacing.m) {
                HStack(alignment: .top, spacing: LarderSpacing.m) {
                    RecipeTile(title: option.candidate.recipe.title, size: .large)
                    VStack(alignment: .leading, spacing: LarderSpacing.xs) {
                        if isCooking {
                            Pill(LedgerCopy.onForTonight, systemImage: "checkmark", tone: .second)
                        }
                        Text(option.candidate.recipe.title)
                            .font(LarderFont.body(.title3, weight: .semibold))
                            .foregroundStyle(LarderColor.ink.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        MetaLabel(Copy.Ledger.minutes(minutes), systemImage: "clock", spoken: Copy.Ledger.spokenMinutes(minutes))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(reasons, id: \.self) { reason in
                    ReasonLine(text: reason)
                }
                AdaptiveStack(spacing: LarderSpacing.s, stacksFrom: .xLarge) { buttons }
            }
        }
        .overlay {
            if isCooking {
                RoundedRectangle(cornerRadius: LarderRadius.panel, style: .continuous)
                    .strokeBorder(LarderColor.accent.second, lineWidth: 2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var buttons: some View {
        if isCooking {
            Button(action: onStartCooking) {
                Label(LedgerCopy.startCooking, systemImage: "flame")
            }
            .buttonStyle(.larderPrimary)
        } else {
            Button(LedgerCopy.cookThis, action: onCook)
                .buttonStyle(.larderPrimary)
        }
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
