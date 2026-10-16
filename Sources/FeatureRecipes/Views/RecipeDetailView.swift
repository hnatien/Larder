import LarderCore
import LarderDesign
import SwiftUI

/// One recipe: ingredients scaled to the servings chosen, the constraint verdict, optional nutrition and the method.
public struct RecipeDetailView: View {
    private enum Phase {
        case loading
        case loaded(RecipeDetail)
        case failed
    }

    /// The most servings the stepper offers.
    static let maximumServings = 99

    private let model: RecipesModel
    private let recipe: Recipe
    private let onAddToPlan: ((Recipe) -> Void)?
    @State private var phase = Phase.loading
    @State private var servings: Int
    @State private var isCooking = false
    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    /// Creates the detail for `recipe`; `onAddToPlan` is the app's "Add to Ledger" handler, and the button is hidden without it.
    public init(model: RecipesModel, recipe: Recipe, onAddToPlan: ((Recipe) -> Void)? = nil) {
        self.model = model
        self.recipe = recipe
        self.onAddToPlan = onAddToPlan
        _servings = State(initialValue: recipe.servings)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LarderSpacing.xl) {
                header
                servingsStepper
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
            .padding(LarderSpacing.l)
        }
        .background(LarderColor.surface.canvas)
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
    }

    private var scaledIngredients: [Ingredient] {
        if case .loaded(let detail) = phase { detail.scaled(to: servings) } else { [] }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            Text(recipe.title)
                .font(LarderFont.display(.largeTitle))
                .foregroundStyle(LarderColor.ink.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            AdaptiveStack(spacing: LarderSpacing.s) { stamps }
            if let url = recipe.sourceURL, let host = url.host() {
                Link(RecipesCopy.source(host), destination: url)
                    .font(LarderFont.body(.subheadline))
                    .foregroundStyle(LarderColor.accent.second)
            }
        }
    }

    @ViewBuilder private var stamps: some View {
        Stamp(text: Copy.Ledger.minutes(recipe.prepMinutes + recipe.cookMinutes))
        Stamp(text: RecipesCopy.servingsStamp(servings))
    }

    private var servingsStepper: some View {
        Stepper(value: $servings, in: 1...Self.maximumServings) {
            HStack {
                Text(RecipesCopy.servings)
                Spacer()
                Text(servings, format: .number)
                    .font(LarderFont.mono(.body))
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
            SectionHeading(RecipesCopy.ingredients)
            ForEach(detail.scaled(to: servings)) { ingredient in
                IngredientLine(ingredient: ingredient)
            }
        }
        VerdictView(verdict: detail.verdict)
        if detail.showsNumbers {
            NutritionList(nutrition: detail.nutrition)
        }
        actions(for: detail)
    }

    private func actions(for detail: RecipeDetail) -> some View {
        VStack(spacing: LarderSpacing.m) {
            Button {
                isCooking = true
            } label: {
                Text(RecipesCopy.startCooking).frame(maxWidth: .infinity)
            }
            .buttonStyle(.larderPrimary)
            .disabled(recipe.steps.isEmpty)
            if let onAddToPlan {
                Button {
                    onAddToPlan(recipe)
                } label: {
                    Text(RecipesCopy.addToLedger).frame(maxWidth: .infinity)
                }
                .buttonStyle(.larderSecondary)
            }
        }
    }

    private var method: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.m) {
            SectionHeading(RecipesCopy.method)
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { offset, step in
                HStack(alignment: .firstTextBaseline, spacing: LarderSpacing.m) {
                    Text(offset + 1, format: .number)
                        .font(LarderFont.mono(.body))
                        .foregroundStyle(LarderColor.ink.secondary)
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

private struct IngredientLine: View {
    let ingredient: Ingredient

    private var showsOptionalMarker: Bool {
        ingredient.isOptional && ingredient.rawText.range(of: RecipesCopy.optional, options: .caseInsensitive) == nil
    }

    var body: some View {
        Text(showsOptionalMarker ? "\(ingredient.rawText) (\(RecipesCopy.optional))" : ingredient.rawText)
            .font(LarderFont.body(.body))
            .foregroundStyle(LarderColor.ink.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        RecipeDetailView(model: PreviewData.model(), recipe: PreviewData.chanaMasala, onAddToPlan: { _ in })
    }
}

#Preview("RecipeDetailView dark") {
    NavigationStack {
        RecipeDetailView(model: PreviewData.model(), recipe: PreviewData.porridge)
    }
    .preferredColorScheme(.dark)
}
#endif
