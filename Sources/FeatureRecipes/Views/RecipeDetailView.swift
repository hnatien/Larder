import LarderCore
import LarderDesign
import SwiftUI

/// One recipe: a photo or dish banner, time and servings, ingredients to tick off, the constraint verdict, optional nutrition and
/// the method, with Start cooking and Add to plan pinned to the bottom.
public struct RecipeDetailView: View {
    private enum Phase {
        case loading
        case loaded(RecipeDetail)
        case failed
    }

    /// The most servings the stepper offers.
    static let maximumServings = 99
    /// How many days ahead "Add to plan" offers.
    static let planDays = 7

    private let model: RecipesModel
    private let recipe: Recipe
    private let onAddToPlan: AddToPlan?
    private let startsCooking: Bool
    @State private var phase = Phase.loading
    @State private var servings: Int
    @State private var isCooking = false
    @State private var isConfirmingDelete = false
    @State private var ticked: Set<IngredientID> = []
    @State private var toast: String?
    @State private var hasAutoStarted = false
    @Environment(\.dismiss) private var dismiss

    /// Creates the detail for `recipe`; without `onAddToPlan` the Add to plan button is hidden. `startsCooking` opens
    /// cooking mode as soon as the recipe has loaded.
    public init(model: RecipesModel, recipe: Recipe, onAddToPlan: AddToPlan? = nil, startsCooking: Bool = false) {
        self.model = model
        self.recipe = recipe
        self.onAddToPlan = onAddToPlan
        self.startsCooking = startsCooking
        _servings = State(initialValue: recipe.servings)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LarderSpacing.xl) {
                header
                switch phase {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                case .failed:
                    failure
                case .loaded(let detail):
                    loaded(detail)
                }
                method
            }
            .padding(.horizontal, LarderSpacing.l)
            .padding(.bottom, LarderSpacing.xl)
        }
        .background(LarderColor.surface.canvas)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) { actionBar }
        .toolbar {
            if recipe.origin == .userImport {
                ToolbarItem(placement: .primaryAction) {
                    Button(RecipesCopy.deleteRecipe, systemImage: "trash") { isConfirmingDelete = true }
                }
            }
        }
        .confirmationDialog(RecipesCopy.deleteQuestion, isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(RecipesCopy.deleteRecipe, role: .destructive) {
                Task {
                    if await model.delete(recipe) { dismiss() }
                }
            }
        } message: {
            Text(RecipesCopy.deleteMessage)
        }
        .cookingCover(isPresented: $isCooking) {
            CookingModeView(recipe: recipe, ingredients: scaledIngredients)
        }
        .task { await loadDetail() }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            toast = nil
        }
        .larderAnimation(LarderMotion.tap, value: toast)
    }

    private var scaledIngredients: [Ingredient] {
        if case .loaded(let detail) = phase { detail.scaled(to: servings) } else { [] }
    }

    private var isLoaded: Bool {
        if case .loaded = phase { true } else { false }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            RecipeImage(title: recipe.title, photoFileName: recipe.photoFileName, size: .banner)
                .clipShape(RoundedRectangle(cornerRadius: LarderRadius.panel, style: .continuous))
            Text(recipe.title)
                .font(LarderFont.display(.largeTitle))
                .foregroundStyle(LarderColor.ink.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            AdaptiveStack(spacing: LarderSpacing.l) {
                MetaLabel(
                    Copy.Ledger.minutes(recipe.prepMinutes + recipe.cookMinutes),
                    systemImage: "clock",
                    spoken: Copy.Ledger.spokenMinutes(recipe.prepMinutes + recipe.cookMinutes)
                )
                MetaLabel(RecipesCopy.servingsStamp(servings), systemImage: "person.2")
                if let cuisine = recipe.tags.cuisine {
                    MetaLabel(cuisine, systemImage: "globe")
                }
            }
            if let url = recipe.sourceURL, let host = url.host() {
                Link(destination: url) {
                    Label(RecipesCopy.source(host), systemImage: "link")
                }
                .font(LarderFont.body(.subheadline))
                .foregroundStyle(LarderColor.accent.second)
            }
        }
    }

    private var servingsStepper: some View {
        Stepper(value: $servings, in: 1...Self.maximumServings) {
            HStack {
                Text(RecipesCopy.servings)
                Spacer()
                Text(servings, format: .number)
                    .font(LarderFont.body(.body, weight: .semibold))
                    .contentTransition(.numericText())
            }
            .font(LarderFont.body(.body))
            .foregroundStyle(LarderColor.ink.primary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RecipesCopy.servings)
            .accessibilityValue(RecipesCopy.spokenServings(servings))
        }
    }

    @ViewBuilder
    private func loaded(_ detail: RecipeDetail) -> some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
                SectionHeading(RecipesCopy.ingredients)
                Text(RecipesCopy.ingredientsHint)
                    .font(LarderFont.body(.footnote))
                    .foregroundStyle(LarderColor.ink.secondary)
            }
            PaperCard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    servingsStepper
                        .padding(.horizontal, LarderSpacing.l)
                        .padding(.vertical, LarderSpacing.s)
                    ForEach(detail.scaled(to: servings)) { ingredient in
                        Divider().overlay(LarderColor.line.hairline).padding(.leading, LarderSpacing.l)
                        IngredientLine(ingredient: ingredient, isTicked: ticked.contains(ingredient.id)) {
                            ticked.formSymmetricDifference([ingredient.id])
                        }
                    }
                }
            }
        }
        VerdictView(verdict: detail.verdict)
        if detail.showsNumbers {
            NutritionList(nutrition: detail.nutrition)
        }
        Color.clear
            .frame(height: 0)
            .task {
                guard startsCooking, !hasAutoStarted, !recipe.steps.isEmpty else { return }
                hasAutoStarted = true
                isCooking = true
            }
    }

    private var actionBar: some View {
        VStack(spacing: LarderSpacing.s) {
            if let toast {
                ToastBar(toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            AdaptiveStack(spacing: LarderSpacing.s, stacksFrom: .xLarge) {
                Button {
                    isCooking = true
                } label: {
                    Label(RecipesCopy.startCooking, systemImage: "flame")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.larderPrimary)
                .disabled(recipe.steps.isEmpty || !isLoaded)
                .accessibilityIdentifier("recipe.startCooking")
                if onAddToPlan != nil {
                    addToPlanMenu
                }
            }
        }
        .padding(.horizontal, LarderSpacing.l)
        .padding(.vertical, LarderSpacing.s)
        .background(LarderColor.surface.canvas)
    }

    private var addToPlanMenu: some View {
        Menu {
            Section(RecipesCopy.addToPlanQuestion) {
                ForEach(Self.upcomingDays(from: .now), id: \.self) { day in
                    Button(Self.dayName(day)) { add(on: day) }
                }
            }
        } label: {
            Label(RecipesCopy.addToPlan, systemImage: "calendar.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.larderSecondary)
    }

    private func add(on day: Date) {
        guard let onAddToPlan else { return }
        Task {
            if await onAddToPlan(recipe, day) {
                toast = RecipesCopy.addedTo(Self.dayName(day))
                AccessibilityNotification.Announcement(RecipesCopy.addedTo(Self.dayName(day))).post()
            } else {
                toast = RecipesCopy.couldNotAdd
            }
        }
    }

    /// Today and the six days after it, at the start of each day.
    static func upcomingDays(from now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<planDays).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    static func dayName(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return RecipesCopy.today }
        if calendar.isDateInTomorrow(day) { return RecipesCopy.tomorrow }
        return day.formatted(.dateTime.weekday(.wide))
    }

    private var method: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            SectionHeading(RecipesCopy.method)
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { offset, step in
                HStack(alignment: .firstTextBaseline, spacing: LarderSpacing.m) {
                    Text(offset + 1, format: .number)
                        .font(LarderFont.body(.subheadline, weight: .bold))
                        .foregroundStyle(LarderColor.accent.brand)
                        .frame(minWidth: 28, minHeight: 28)
                        .background(LarderColor.accent.brand.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                    Text(step.text)
                        .font(LarderFont.body(.body))
                        .foregroundStyle(LarderColor.ink.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(RecipesCopy.stepPosition(offset + 1, of: recipe.steps.count) + ". " + step.text)
            }
        }
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            Label(RecipesCopy.detailFailed, systemImage: "exclamationmark.triangle.fill")
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.status(.danger))
            Button(RecipesCopy.retry) {
                Task { await loadDetail() }
            }
            .buttonStyle(.larderSecondary)
        }
    }

    private func loadDetail() async {
        phase = .loading
        do {
            phase = .loaded(try await model.detail(for: recipe))
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }
}

/// One ingredient line; tapping ticks it off while you gather things.
private struct IngredientLine: View {
    let ingredient: Ingredient
    let isTicked: Bool
    let toggle: () -> Void

    private var showsOptionalMarker: Bool {
        ingredient.isOptional && ingredient.rawText.range(of: RecipesCopy.optional, options: .caseInsensitive) == nil
    }

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: LarderSpacing.m) {
                Image(systemName: isTicked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isTicked ? LarderColor.accent.second : LarderColor.ink.tertiary)
                    .accessibilityHidden(true)
                Text(showsOptionalMarker ? "\(ingredient.rawText) (\(RecipesCopy.optional))" : ingredient.rawText)
                    .font(LarderFont.body(.body))
                    .foregroundStyle(isTicked ? LarderColor.ink.secondary : LarderColor.ink.primary)
                    .strikethrough(isTicked)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, LarderSpacing.l)
            .padding(.vertical, LarderSpacing.s)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isTicked)
        .accessibilityAddTraits(isTicked ? .isSelected : [])
    }
}

/// The constraint verdict: nothing for a pass, then always the label reminder.
private struct VerdictView: View {
    let verdict: FilterVerdict

    var body: some View {
        switch verdict {
        case .pass:
            Text(Copy.Allergen.checkTheLabel)
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.secondary)
        case .excluded(let reasons):
            card(title: RecipesCopy.excludedTitle, tone: .danger, reasons: reasons)
        case .uncertain(let reasons):
            card(title: RecipesCopy.uncertainTitle, tone: .warning, reasons: reasons)
        }
    }

    private func card(title: String, tone: LarderColor.Status, reasons: [String]) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: LarderSpacing.s) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(LarderFont.body(.headline))
                ForEach(reasons, id: \.self) { reason in
                    Text(reason)
                        .font(LarderFont.body(.body))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(Copy.Allergen.checkTheLabel)
                    .font(LarderFont.body(.body))
                    .foregroundStyle(LarderColor.ink.secondary)
            }
            .foregroundStyle(LarderColor.status(tone))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Per-serving energy, protein, fibre and sodium as stamps; never a chart.
private struct NutritionList: View {
    let nutrition: RecipeNutrition

    private var entries: [String] {
        let serving = nutrition.perServing
        return [
            serving.energyKcal.map { "\(RecipesCopy.energy) \(Int($0.rounded())) kcal" },
            serving.proteinG.map { "\(RecipesCopy.protein) \(Int($0.rounded())) g" },
            serving.fiberG.map { "\(RecipesCopy.fibre) \(Int($0.rounded())) g" },
            serving.sodiumMg.map { "\(RecipesCopy.sodium) \(Int($0.rounded())) mg" },
        ].compactMap { $0 }
    }

    var body: some View {
        if nutrition.coverage > 0, !entries.isEmpty {
            VStack(alignment: .leading, spacing: LarderSpacing.s) {
                SectionHeading(RecipesCopy.perServing)
                ForEach(entries, id: \.self) { Stamp(text: $0) }
                if nutrition.coverage < 1 || !nutrition.unresolved.isEmpty {
                    Text(RecipesCopy.partialNutrition)
                        .font(LarderFont.body(.subheadline))
                        .foregroundStyle(LarderColor.ink.secondary)
                }
            }
        }
    }
}

private extension View {
    /// Presents full screen on iOS and as a sheet elsewhere.
    @ViewBuilder
    func cookingCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }
}

#if DEBUG
#Preview("RecipeDetailView") {
    NavigationStack {
        RecipeDetailView(model: PreviewData.model(), recipe: PreviewData.chanaMasala, onAddToPlan: { _, _ in true })
    }
}

#Preview("RecipeDetailView dark") {
    NavigationStack {
        RecipeDetailView(model: PreviewData.model(), recipe: PreviewData.porridge)
    }
    .preferredColorScheme(.dark)
}
#endif
