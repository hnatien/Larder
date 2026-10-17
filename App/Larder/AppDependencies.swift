import FeatureAccount
import FeatureGrocery
import FeatureLedger
import FeatureRecipes
import FeatureShelves
import Foundation
import LarderAssistant
import LarderCore
import LarderOnDeviceAI
import LarderPersistence
import OSLog

/// The current time from the system clock.
nonisolated struct SystemDateProvider: DateProvider {
    var now: Date { Date() }
}

/// How the app was launched; UI tests pass arguments that swap in an in-memory store with fixtures.
nonisolated struct LaunchOptions: Sendable {
    /// `-LarderUITestMode`: in-memory store, fresh flags, seeded shelves, a saved profile and no widget snapshot.
    var isUITest: Bool
    /// `-LarderUITestOnboarding`: in UI-test mode, leave the profile out so onboarding shows.
    var showsOnboarding: Bool
    /// `-LarderUITestEmptyPantry`: in UI-test mode, leave the shelves empty so the first-run empty states show.
    var startsWithEmptyPantry: Bool
    /// `-AppleInterfaceStyle Dark`: in UI-test mode, render dark, since iOS ignores that argument on its own.
    var forcesDarkAppearance: Bool

    /// The options in this process's launch arguments.
    static var current: LaunchOptions {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITest = arguments.contains("-LarderUITestMode")
        return LaunchOptions(
            isUITest: isUITest,
            showsOnboarding: isUITest && arguments.contains("-LarderUITestOnboarding"),
            startsWithEmptyPantry: isUITest && arguments.contains("-LarderUITestEmptyPantry"),
            forcesDarkAppearance: isUITest && UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        )
    }
}

/// Why the app could not build its dependencies.
nonisolated enum AppStartupError: Error {
    /// `LarderProxyBaseURL` is missing from Info.plist or is not a URL.
    case invalidProxyURL
}

/// Builds the app's object graph once: store, repositories, StoreKit, assistant routing and feature models.
@MainActor
final class AppDependencies {
    /// Bump when the bundled seed files change so existing installs load them again.
    static let seedVersion = 2
    static let seedVersionKey = "seedVersion"
    private static let uiTestDefaultsSuite = "com.larder.Larder.uitest"
    private static let onDeviceWarmUpDelay = Duration.seconds(2)
    private static let logger = Logger(subsystem: "com.larder.Larder", category: "Startup")

    /// The graph the running app built, for App Intents; `nil` when building it failed.
    private(set) static var shared: AppDependencies?

    let state = AppState()
    let entitlements: EntitlementStore
    let tonight: TonightModel
    let ledger: LedgerModel
    let shelves: ShelvesModel
    let recipes: RecipesModel
    let grocery: GroceryModel
    let dinners: DinnerReader
    let snapshots: TodaySnapshotWriter
    let foundationModels: FoundationModelsBackend
    private(set) var onboarding: OnboardingModel
    private(set) lazy var settings = SettingsModel(
        profiles: profiles,
        exporter: ExportBuilder(profiles: profiles, recipes: recipeRepository, pantry: pantry, plans: plans),
        preferences: preferences,
        dates: dates,
        deleteAllData: { [weak self] in try await self?.eraseAllData() }
    )

    let recipeRepository: GRDBRecipeRepository
    let photos: FileRecipePhotoStore
    private let database: LarderDatabase
    private let foods: GRDBFoodRepository
    private let pantry: GRDBPantryRepository
    private let plans: GRDBPlanRepository
    private let profiles: GRDBProfileRepository
    private let dates: any DateProvider
    private let planning: PlanningService
    private let preferences: ComfortPreferences
    private let defaults: UserDefaults
    let launch: LaunchOptions
    private var hasStarted = false

    /// Builds the graph for `launch` and makes it the shared one.
    static func makeShared(launch: LaunchOptions) throws -> AppDependencies {
        let dependencies = try AppDependencies(launch: launch)
        shared = dependencies
        return dependencies
    }

    private init(launch: LaunchOptions) throws {
        self.launch = launch
        if launch.isUITest {
            let suite = UserDefaults(suiteName: Self.uiTestDefaultsSuite) ?? .standard
            suite.removePersistentDomain(forName: Self.uiTestDefaultsSuite)
            defaults = suite
            database = try LarderDatabase.inMemory()
            let uiTestPhotos = FileRecipePhotoStore(directory: FileManager.default.temporaryDirectory.appending(path: "RecipePhotos-UITest"))
            try uiTestPhotos.deleteAll()
            photos = uiTestPhotos
        } else {
            defaults = .standard
            database = try LarderDatabase.onDisk(at: try LarderDatabase.defaultURL())
            photos = FileRecipePhotoStore(directory: try FileRecipePhotoStore.defaultDirectory())
        }
        foods = GRDBFoodRepository(database: database)
        recipeRepository = GRDBRecipeRepository(database: database)
        pantry = GRDBPantryRepository(database: database)
        plans = GRDBPlanRepository(database: database)
        profiles = GRDBProfileRepository(database: database)
        let dates = SystemDateProvider()
        self.dates = dates
        let flags = UserDefaultsKeyValueStore(defaults: defaults)
        let trialWeek = TrialWeekGate(store: flags)
        preferences = ComfortPreferences(store: flags)
        planning = PlanningService(
            plans: plans, recipes: recipeRepository, foods: foods, pantry: pantry, profiles: profiles, dates: dates
        )

        let entitlements = EntitlementStore(storeFront: LiveStoreFront(), dates: dates)
        self.entitlements = entitlements
        let assistant = try Self.makeAssistant(
            entitlements: entitlements, planning: planning, plans: plans, profiles: profiles, dates: dates
        )
        foundationModels = assistant.onDevice

        tonight = TonightModel(
            plans: plans, recipes: recipeRepository, foods: foods, pantry: pantry, profiles: profiles, dates: dates
        )
        ledger = LedgerModel(
            plans: plans,
            recipes: recipeRepository,
            foods: foods,
            pantry: pantry,
            profiles: profiles,
            assistant: assistant.router,
            dates: dates,
            isPlus: entitlements.isPlus,
            canGenerateFreeWeek: { trialWeek.canGenerateFreeWeek },
            markFreeWeekUsed: { trialWeek.markFreeWeekUsed() }
        )
        shelves = ShelvesModel(pantry: pantry, foods: foods, assistant: assistant.router, dates: dates)
        recipes = RecipesModel(
            recipes: recipeRepository, photos: photos, foods: foods, profile: profiles, assistant: assistant.router, isPlus: entitlements.isPlus
        )
        grocery = GroceryModel(plans: plans, recipes: recipeRepository, foods: foods, pantry: pantry, dates: dates)
        onboarding = OnboardingModel(profiles: profiles, preferences: preferences, dates: dates)
        dinners = DinnerReader(plans: plans, recipes: recipeRepository, calendar: .current)
        snapshots = TodaySnapshotWriter(reader: dinners, dates: dates, fileURL: launch.isUITest ? nil : TodaySnapshot.fileURL)
    }

    private static func makeAssistant(
        entitlements: EntitlementStore,
        planning: PlanningService,
        plans: any PlanRepository,
        profiles: any ProfileRepository,
        dates: any DateProvider
    ) throws -> (router: AssistantRouter, onDevice: FoundationModelsBackend) {
        guard let address = Bundle.main.object(forInfoDictionaryKey: "LarderProxyBaseURL") as? String,
              let baseURL = URL(string: address)
        else { throw AppStartupError.invalidProxyURL }
        let configuration = ProxyConfiguration(
            baseURL: baseURL,
            clientSecretProvider: {
                #if DEBUG
                ProcessInfo.processInfo.environment["LARDER_DEV_CLIENT_SECRET"]
                #else
                nil
                #endif
            },
            entitlementProvider: { await entitlements.entitlementJWS() },
            // The Simulator has no App Attest, so Debug runs there use the development secret above.
            appAttest: AppAttestConfiguration(attester: LiveAppAttester(), keyStore: UserDefaultsAttestedKeyStore())
        )
        let client = ProxyClient(configuration: configuration, urlSession: URLSession(configuration: .ephemeral), dateProvider: dates)
        let proxy = ProxyAssistantBackend(client: client, dateProvider: dates) {
            try await explainContext(planning: planning, plans: plans, profiles: profiles)
        }
        let onDevice = FoundationModelsBackend(dates: dates)
        let router = AssistantRouter(onDevice: onDevice, proxy: proxy) {
            do {
                return try await profiles.profile()?.consents ?? Consents()
            } catch {
                return Consents()
            }
        }
        return (router, onDevice)
    }

    /// The profile, constraints, recipe minutes and shelf balance of the active plan, for the explain route.
    private nonisolated static func explainContext(
        planning: PlanningService,
        plans: any PlanRepository,
        profiles: any ProfileRepository
    ) async throws -> ExplainContext {
        guard let profile = try await profiles.profile() else { throw LarderError.notFound }
        let constraints = try await profiles.constraints()
        guard let plan = try await plans.currentPlan() else {
            return ExplainContext(profile: profile, constraints: constraints, recipeMinutes: [:])
        }
        let meals = try await plans.meals(for: plan.id)
        let catalogue = try await planning.catalogue(for: Set(meals.map(\.recipeID)))
        let minutes = Dictionary(
            catalogue.candidates.map { ($0.recipe.title, $0.totalMinutes) },
            uniquingKeysWith: { first, _ in first }
        )
        let balance = try await planning.verify(meals: meals, days: plan.days, catalogue: catalogue).shelfBalance
        return ExplainContext(
            profile: profile,
            constraints: constraints,
            recipeMinutes: minutes,
            groupsLight: balance.groupsLight,
            groupsHeavy: balance.groupsHeavy
        )
    }

    // MARK: Launch

    /// Seeds the library, installs UI-test fixtures, reads whether a profile exists and writes the widget snapshot.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await seedIfNeeded()
        do {
            if launch.isUITest { try await installUITestFixtures() }
            state.hasProfile = try await profiles.profile() != nil
        } catch {
            Self.logger.error("Could not read the store at launch: \(String(describing: type(of: error)), privacy: .public)")
            state.startupFailed = true
            return
        }
        await snapshots.write()
    }

    /// Warms the on-device model once the first frame is up.
    func prepareOnDeviceModel() async {
        do {
            try await Task.sleep(for: Self.onDeviceWarmUpDelay)
        } catch {
            return
        }
        await foundationModels.prepare()
    }

    /// Loads the bundled seed files when this install has not loaded the current version; UI tests always load them.
    private func seedIfNeeded() async {
        guard launch.isUITest || defaults.integer(forKey: Self.seedVersionKey) < Self.seedVersion else { return }
        guard let foodsURL = Bundle.main.url(forResource: "seed-foods", withExtension: "json"),
              let recipesURL = Bundle.main.url(forResource: "seed-recipes", withExtension: "json")
        else {
            Self.logger.fault("The seed files are missing from the app bundle")
            return
        }
        do {
            let report = try await SeedLoader(database: database).load(foodsURL: foodsURL, recipesURL: recipesURL)
            if !report.unresolvedFoodSlugs.isEmpty {
                Self.logger.error("Seed recipes reference \(report.unresolvedFoodSlugs.count, privacy: .public) unknown foods")
            }
            defaults.set(Self.seedVersion, forKey: Self.seedVersionKey)
        } catch {
            Self.logger.error("Seeding failed and will retry next launch: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Actions

    /// Marks onboarding as done so the tabs show.
    func finishOnboarding() async {
        state.hasProfile = true
        await snapshots.write()
    }

    /// Puts `recipe` on `day`'s dinner, replacing whatever was there, and reloads Tonight and the Plan.
    func addToPlan(_ recipe: Recipe, on day: Date) async throws {
        guard let profile = try await profiles.profile() else { throw LarderError.notFound }
        let catalogue = try await planning.catalogue(for: [recipe.id])
        guard let candidate = catalogue.candidates.first else { throw LarderError.notFound }
        let context = planning.context(for: profile, pantry: try await pantry.items(), recentPlans: [], catalogue: catalogue)
        await tonight.schedule(RecipeScorer.score(candidate, context: context), on: day)
        if let error = tonight.error {
            tonight.clearError()
            throw error
        }
        await ledger.load()
        await grocery.load()
    }

    /// Erases the store, reloads the seed library and returns to onboarding.
    private func eraseAllData() async throws {
        try await database.eraseAll()
        try photos.deleteAll()
        defaults.removeObject(forKey: Self.seedVersionKey)
        await seedIfNeeded()
        onboarding = OnboardingModel(profiles: profiles, preferences: preferences, dates: dates)
        state.selectedTab = .tonight
        state.hasProfile = false
        await snapshots.write()
    }

    // MARK: UI-test fixtures

    /// Eight shelf items so Tonight has ideas unless the test wants an empty pantry, plus a saved profile unless the
    /// test wants onboarding.
    private func installUITestFixtures() async throws {
        let now = dates.now
        let calendar = Calendar.current
        func inDays(_ days: Int) -> Date? { calendar.date(byAdding: .day, value: days, to: now) }
        let shelf: [(slug: String, name: String, grams: Double, location: StorageLocation, bestBy: Date?)] = [
            ("spinach", "Spinach", 200, .fridge, inDays(1)),
            ("eggs", "Eggs", 300, .fridge, inDays(6)),
            ("onion", "Onions", 330, .pantry, inDays(14)),
            ("garlic", "Garlic", 40, .pantry, inDays(21)),
            ("canned-tomatoes", "Chopped tomatoes", 800, .pantry, inDays(300)),
            ("chickpeas-canned", "Chickpeas", 480, .pantry, inDays(300)),
            ("white-rice", "Rice", 1000, .pantry, inDays(365)),
            ("olive-oil", "Olive oil", 500, .pantry, inDays(365)),
        ]
        for item in shelf where !launch.startsWithEmptyPantry {
            try await pantry.upsert(PantryItem(
                foodID: DeterministicID.foodID(slug: item.slug),
                rawName: item.name,
                quantityGrams: item.grams,
                location: item.location,
                bestBy: item.bestBy,
                source: .manual,
                addedOn: now
            ))
        }
        guard !launch.showsOnboarding else { return }
        let profile = UserProfile(
            birthYear: 1988,
            heightCm: 170,
            activityLevel: .moderate,
            goal: .lessWaste,
            householdSize: 2,
            currencyCode: "USD",
            maxCookMinutes: 45,
            equipment: [.oven, .stovetop, .microwave]
        )
        let constraints = [
            DietaryConstraint(axis: .medical, kind: .allergen(.peanut), strictness: .hard, source: .user, lastConfirmed: now),
        ]
        let referenceYear = calendar.component(.year, from: now)
        try await profiles.saveConstraints(constraints)
        try await profiles.saveTargets(NutrientTargets.defaults(for: profile, constraints: constraints, referenceYear: referenceYear))
        try await profiles.save(profile)
    }
}
