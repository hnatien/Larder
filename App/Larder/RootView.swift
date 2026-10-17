import FeatureAccount
import FeatureGrocery
import FeatureLedger
import FeatureRecipes
import FeatureShelves
import LarderCore
import LarderDesign
import SwiftUI

/// The welcome screen and setup until a profile exists, then the five tabs with Settings, recipe detail and the paywall on top.
struct RootView: View {
    /// A problem the root view reports in an alert.
    private enum Notice: Identifiable {
        case recipeMissing
        case recipeUnreadable

        var id: Self { self }

        var message: String {
            switch self {
            case .recipeMissing: Copy.App.recipeMissing
            case .recipeUnreadable: Copy.App.recipeUnreadable
            }
        }
    }

    /// A recipe shown over the tabs, and whether cooking mode should open straight away.
    private struct PresentedRecipe: Identifiable {
        let recipe: Recipe
        let startsCooking: Bool

        var id: RecipeID { recipe.id }
    }

    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentedRecipe: PresentedRecipe?
    @State private var showsAccount = false
    @State private var showsPaywall = false
    @State private var isAddingFood = false
    /// Set when Add food was opened from Tonight's empty state, so the first food added leads back to the ideas.
    @State private var returnsToTonight = false
    @State private var notice: Notice?

    private var state: AppState { dependencies.state }

    var body: some View {
        content
            .larderTheme()
            .environment(\.timersFlashAndVibrate, dependencies.settings.timersFlashAndVibrate)
            .environment(\.recipePhotoDirectory, dependencies.photos.directory)
            .preferredColorScheme(dependencies.launch.forcesDarkAppearance ? .dark : nil)
            .onOpenURL { url in
                // larder://tonight, from the widget.
                if url.scheme == "larder", url.host() == "tonight" { state.selectedTab = .tonight }
            }
            .onChange(of: state.hasProfile) { _, hasProfile in
                // After Delete all data nothing from the old session should come back over the new setup.
                guard hasProfile == false else { return }
                showsAccount = false
                showsPaywall = false
                presentedRecipe = nil
                isAddingFood = false
                returnsToTonight = false
            }
            .task { await dependencies.start() }
            .task { await dependencies.entitlements.start() }
            .task { await dependencies.prepareOnDeviceModel() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .background else { return }
                Task { await dependencies.snapshots.write() }
            }
    }

    @ViewBuilder private var content: some View {
        if state.startupFailed {
            StartupFailureView { Task { await dependencies.retryStart() } }
        } else {
            switch state.hasProfile {
            case nil:
                // Matches the launch screen while the store opens.
                ZStack {
                    LarderColor.surface.canvas
                        .ignoresSafeArea()
                    Image("LaunchMark")
                        .accessibilityHidden(true)
                }
            case false?:
                OnboardingFlow(model: dependencies.onboarding) {
                    Task { await dependencies.finishOnboarding() }
                }
            case true?:
                tabs
            }
        }
    }

    private var tabs: some View {
        TabView(selection: Bindable(state).selectedTab) {
            Tab(Copy.Tab.tonight, systemImage: "sun.horizon", value: AppTab.tonight) {
                TonightView(
                    model: dependencies.tonight,
                    onOpenRecipe: { openRecipe($0) },
                    onStartCooking: { openRecipe($0, startsCooking: true) },
                    onAddToPantry: {
                        returnsToTonight = dependencies.shelves.items.isEmpty
                        state.selectedTab = .shelves
                        isAddingFood = true
                    },
                    onBrowseRecipes: { state.selectedTab = .recipes },
                    onOpenSettings: openSettings
                )
            }
            Tab(Copy.Tab.ledger, systemImage: "calendar", value: AppTab.ledger) {
                LedgerView(
                    model: dependencies.ledger,
                    onOpenRecipe: { openRecipe($0) },
                    onShowPaywall: { showsPaywall = true },
                    onOpenAccount: openSettings
                )
            }
            Tab(Copy.Tab.shelves, systemImage: "refrigerator", value: AppTab.shelves) {
                ShelvesView(model: dependencies.shelves, isAdding: $isAddingFood, onOpenAccount: openSettings)
            }
            Tab(Copy.Tab.recipes, systemImage: "book", value: AppTab.recipes) {
                RecipesView(
                    model: dependencies.recipes,
                    onAddToPlan: addToPlan,
                    onFinishCooking: finishCooking,
                    onAddToGroceries: dependencies.addToGroceries,
                    plannedDinners: dependencies.plannedDinners,
                    onOpenSettings: openSettings
                )
            }
            Tab(Copy.Tab.grocery, systemImage: "cart", value: AppTab.grocery) {
                GroceryView(model: dependencies.grocery, onOpenPlan: { state.selectedTab = .ledger }, onOpenSettings: openSettings)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: dependencies.ledger.meals) {
            Task {
                await dependencies.snapshots.write()
                await dependencies.shelves.load()
                await dependencies.tonight.load()
                await dependencies.grocery.load()
            }
        }
        .onChange(of: dependencies.tonight.cookingID) {
            Task { await dependencies.snapshots.write() }
        }
        .onChange(of: isAddingFood) { _, isAdding in
            // The first food added from Tonight's empty state goes straight back to tonight's ideas.
            guard !isAdding, returnsToTonight else { return }
            returnsToTonight = false
            if !dependencies.shelves.items.isEmpty {
                state.selectedTab = .tonight
                AccessibilityNotification.Announcement(Copy.App.addedFirstFood).post()
            }
        }
        .onChange(of: dependencies.shelves.items) {
            Task {
                await dependencies.tonight.load()
                await dependencies.recipes.refreshCoverage()
            }
        }
        .sheet(item: $presentedRecipe) { presented in
            NavigationStack {
                RecipeDetailView(
                    model: dependencies.recipes,
                    recipe: presented.recipe,
                    onAddToPlan: addToPlan,
                    onFinishCooking: finishCooking,
                    onAddToGroceries: dependencies.addToGroceries,
                    plannedDinners: dependencies.plannedDinners,
                    startsCooking: presented.startsCooking
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { presentedRecipe = nil }
                    }
                }
            }
        }
        .sheet(isPresented: $showsAccount) {
            NavigationStack {
                SettingsView(model: dependencies.settings, entitlements: dependencies.entitlements)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .close) { showsAccount = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView(entitlements: dependencies.entitlements) { showsPaywall = false }
        }
        .alert(
            notice?.message ?? "",
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            Button(Copy.App.ok) { notice = nil }
        }
    }

    private func openSettings() {
        showsAccount = true
    }

    private func openRecipe(_ id: RecipeID, startsCooking: Bool = false) {
        Task {
            do {
                guard let recipe = try await dependencies.recipeRepository.recipe(by: id) else {
                    notice = .recipeMissing
                    return
                }
                presentedRecipe = PresentedRecipe(recipe: recipe, startsCooking: startsCooking)
            } catch {
                notice = .recipeUnreadable
            }
        }
    }

    /// Marks the recipe cooked when cooking mode finishes; the detail offers the returned undo in a toast.
    private func finishCooking(_ recipe: Recipe, servings: Int) async -> CookingUndo? {
        await dependencies.finishCooking(recipe, servings: servings)
    }

    /// Puts the recipe on the day's dinner and stays where the user is; the detail confirms with a toast.
    private func addToPlan(_ recipe: Recipe, on day: Date) async -> Bool {
        do {
            try await dependencies.addToPlan(recipe, on: day)
            return true
        } catch {
            return false
        }
    }
}

/// Shown when the store cannot be opened; there is nothing else the app can do without it, so it offers to try again
/// when it can.
struct StartupFailureView: View {
    var onRetry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(Copy.App.startupFailedTitle, systemImage: "exclamationmark.triangle")
        } description: {
            Text(Copy.App.startupFailedMessage)
        } actions: {
            if let onRetry {
                Button(Copy.App.tryAgain, action: onRetry)
                    .buttonStyle(.larderPrimary)
            }
        }
        .foregroundStyle(LarderColor.ink.primary)
    }
}
