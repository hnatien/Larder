import FeatureAccount
import FeatureGrocery
import FeatureLedger
import FeatureRecipes
import FeatureShelves
import LarderCore
import LarderDesign
import SwiftUI

/// Onboarding until a profile exists, then the five tabs with Account, recipe detail and the paywall on top.
struct RootView: View {
    /// A problem the root view reports in an alert.
    private enum Notice: Identifiable {
        case recipeMissing
        case recipeUnreadable
        case couldNotAddToLedger

        var id: Self { self }

        var message: String {
            switch self {
            case .recipeMissing: String(localized: "That recipe is no longer in your library.")
            case .recipeUnreadable: String(localized: "Couldn't open that recipe. Try again.")
            case .couldNotAddToLedger: String(localized: "Couldn't add that to tonight's dinner. Try again.")
            }
        }
    }

    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentedRecipe: Recipe?
    @State private var showsAccount = false
    @State private var showsPaywall = false
    @State private var notice: Notice?

    private var state: AppState { dependencies.state }

    var body: some View {
        content
            .larderTheme()
            .preferredColorScheme(dependencies.launch.forcesDarkAppearance ? .dark : nil)
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
            StartupFailureView()
        } else {
            switch state.hasProfile {
            case nil:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                NavigationStack {
                    TonightView(model: dependencies.tonight, onOpenRecipe: openRecipe) {
                        state.selectedTab = .shelves
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigation) { accountButton }
                    }
                }
            }
            Tab(Copy.Tab.ledger, systemImage: "list.bullet.rectangle", value: AppTab.ledger) {
                LedgerView(
                    model: dependencies.ledger,
                    onOpenRecipe: openRecipe,
                    onShowPaywall: { showsPaywall = true },
                    onOpenAccount: { showsAccount = true }
                )
            }
            Tab(Copy.Tab.shelves, systemImage: "cabinet", value: AppTab.shelves) {
                ShelvesView(model: dependencies.shelves) { showsAccount = true }
            }
            Tab(Copy.Tab.recipes, systemImage: "book", value: AppTab.recipes) {
                RecipesView(model: dependencies.recipes, onAddToPlan: addToLedger)
            }
            Tab(Copy.Tab.grocery, systemImage: "basket", value: AppTab.grocery) {
                GroceryView(model: dependencies.grocery)
            }
        }
        .onChange(of: dependencies.ledger.meals) {
            Task { await dependencies.snapshots.write() }
        }
        .onChange(of: dependencies.tonight.cookingID) {
            Task { await dependencies.snapshots.write() }
        }
        .sheet(item: $presentedRecipe) { recipe in
            NavigationStack {
                RecipeDetailView(model: dependencies.recipes, recipe: recipe, onAddToPlan: addToLedger)
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
            Button(String(localized: "OK")) { notice = nil }
        }
    }

    private var accountButton: some View {
        Button(Copy.Tab.account, systemImage: "gearshape") { showsAccount = true }
    }

    private func openRecipe(_ id: RecipeID) {
        Task {
            do {
                guard let recipe = try await dependencies.recipeRepository.recipe(by: id) else {
                    notice = .recipeMissing
                    return
                }
                presentedRecipe = recipe
            } catch {
                notice = .recipeUnreadable
            }
        }
    }

    private func addToLedger(_ recipe: Recipe) {
        Task {
            do {
                try await dependencies.addToTonight(recipe)
            } catch {
                notice = .couldNotAddToLedger
                return
            }
            presentedRecipe = nil
            state.selectedTab = .ledger
        }
    }
}

/// Shown when the store cannot be opened; there is nothing else the app can do without it.
struct StartupFailureView: View {
    var body: some View {
        ContentUnavailableView(
            String(localized: "Larder couldn't open your data"),
            systemImage: "exclamationmark.triangle",
            description: Text(String(localized: "Close Larder and open it again. Your data stays on this device."))
        )
        .foregroundStyle(LarderColor.ink.primary)
    }
}
