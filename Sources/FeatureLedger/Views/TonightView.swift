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
    /// The idea waiting for "Cook this instead?" while tonight already has a dinner.
    @State private var replacing: ScoredRecipe?
    /// Whether the "nothing left out yet" reminder was put away; it does not come back on this device.
    @AppStorage("larder.tonight.rulesReminderDismissed") private var rulesReminderDismissed = false

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
                    if model.loadFailed {
                        InlineBanner(
                            LedgerCopy.tonightLoadFailed,
                            action: .init(title: LedgerCopy.tryAgain) { Task { await model.load() } },
                            dismissTitle: LedgerCopy.dismiss,
                            onDismiss: model.clearError
                        )
                    } else if let error = model.error {
                        LedgerNotice(error: error, onDismiss: model.clearError)
                    }
                    if model.hasNoRules, !rulesReminderDismissed, let onOpenSettings {
                        InlineBanner(
                            LedgerCopy.noRulesReminder,
                            tone: .info,
                            action: .init(title: LedgerCopy.openSettings, perform: onOpenSettings),
                            dismissTitle: Copy.Action.notNow
                        ) {
                            rulesReminderDismissed = true
                        }
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
        .confirmationDialog(
            replacing.map { _ in LedgerCopy.replaceTonight(model.dinner?.title ?? "") } ?? "",
            isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }),
            titleVisibility: .visible,
            presenting: replacing
        ) { option in
            Button(LedgerCopy.cookInstead(option.candidate.recipe.title)) { schedule(option) }
            Button(LedgerCopy.replaceKeep, role: .cancel) {}
        }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading, model.options.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, LarderSpacing.xxl)
        } else if model.loadFailed, model.options.isEmpty {
            EmptyView()
        } else if model.dinner != nil, model.options.isEmpty, !model.shelvesAreEmpty {
            Text(LedgerCopy.noOtherIdeas)
                .font(LarderFont.body(.subheadline))
                .foregroundStyle(LarderColor.ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.shelvesAreEmpty || model.options.isEmpty {
            EmptyShelf(
                title: model.shelvesAreEmpty ? LedgerCopy.emptyShelvesTitle : LedgerCopy.nothingFitsTitle,
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
                    isMainAction: model.dinner == nil,
                    onCook: { cook(option) },
                    onOpenRecipe: { onOpenRecipe(option.recipeID) }
                )
                .transition(.opacity)
            }
            .larderAnimation(LarderMotion.layout, value: model.page)
            if model.hasOtherIdeas {
                Button {
                    model.showOtherIdeas()
                } label: {
                    Label(Copy.Action.otherIdeas, systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.larderSecondary)
                .sensoryFeedback(.selection, trigger: model.page)
            }
        }
    }

    /// Puts the idea on tonight, asking first when it would replace a dinner that is planned and not yet cooked.
    private func cook(_ option: ScoredRecipe) {
        if let dinner = model.dinner, !dinner.isCooked, dinner.recipeID != option.recipeID {
            replacing = option
        } else {
            schedule(option)
        }
    }

    private func schedule(_ option: ScoredRecipe) {
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
                RecipeImage(title: dinner.title, photoFileName: dinner.photoFileName, size: .banner)
                VStack(alignment: .leading, spacing: LarderSpacing.m) {
                    if dinner.isCooked {
                        Pill(LedgerCopy.cookedTonight, systemImage: "checkmark", tone: .second)
                    } else if let source = dinner.leftoverFrom {
                        Pill(LedgerCopy.leftoversFrom(source.formatted(.dateTime.weekday(.wide))), systemImage: "arrow.2.squarepath", tone: .second)
                    } else {
                        Pill(LedgerCopy.tonightsDinner, systemImage: "fork.knife", tone: .brand)
                    }
                    Text(dinner.title)
                        .font(LarderFont.display(.title2))
                        .foregroundStyle(LarderColor.ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    MetaLabel(Copy.Ledger.minutes(dinner.minutes), systemImage: "clock", spoken: Copy.Ledger.spokenMinutes(dinner.minutes))
                    AdaptiveStack(spacing: LarderSpacing.s, stacksFrom: .xLarge) {
                        // A cooked dinner or one that is leftovers needs no cooking, so the recipe is all it offers.
                        if dinner.isCooked || dinner.leftoverFrom != nil {
                            Button(LedgerCopy.seeRecipe, action: onOpenRecipe)
                                .buttonStyle(.larderSecondary)
                        } else {
                            Button(action: onStartCooking) {
                                Label(LedgerCopy.startCooking, systemImage: "flame")
                            }
                            .buttonStyle(.larderPrimary)
                            Button(LedgerCopy.seeRecipe, action: onOpenRecipe)
                                .buttonStyle(.larderQuiet)
                        }
                    }
                }
                .padding(LarderSpacing.l)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One idea: a dish band, the title, time, up to two reasons, and what to do with it. Once tonight has a dinner,
/// its Start cooking is the screen's main action and the ideas step down to the tinted button.
private struct TonightCard: View {
    let option: ScoredRecipe
    let reasons: [String]
    let isMainAction: Bool
    let onCook: () -> Void
    let onOpenRecipe: () -> Void

    private var minutes: Int { option.candidate.totalMinutes }

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: LarderSpacing.m) {
                HStack(alignment: .top, spacing: LarderSpacing.m) {
                    RecipeImage(title: option.candidate.recipe.title, photoFileName: option.candidate.recipe.photoFileName, size: .large)
                    VStack(alignment: .leading, spacing: LarderSpacing.xs) {
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
                AdaptiveStack(spacing: LarderSpacing.s, stacksFrom: .xLarge) {
                    Button(LedgerCopy.cookThis, action: onCook)
                        .buttonStyle(isMainAction ? .larderPrimary : .larderSecondary)
                    Button(LedgerCopy.seeRecipe, action: onOpenRecipe)
                        .buttonStyle(.larderQuiet)
                }
            }
        }
        .accessibilityElement(children: .contain)
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
