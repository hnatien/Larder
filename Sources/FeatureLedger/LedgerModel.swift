import Foundation
import LarderCore
import LarderDesign
import Observation

/// One meal as the ledger shows it.
public nonisolated struct LedgerMeal: Identifiable, Hashable, Sendable {
    public var meal: PlannedMeal
    public var title: String
    public var minutes: Int
    /// The recipe's photo in the photo store, if it has one.
    public var photoFileName: String?
    /// "Chilli, day 2 of 4" for a leftover whose cooked meal is in the plan; `nil` otherwise.
    public var leftoverTag: String?

    public var id: PlannedMealID { meal.id }
}

/// One day of the plan.
public nonisolated struct LedgerDay: Identifiable, Hashable, Sendable {
    public var date: Date
    public var isToday: Bool
    /// Meals in meal-type order.
    public var meals: [LedgerMeal]
    /// Planned slots with no meal yet.
    public var openSlots: [MealType]

    public var id: Date { date }
}

/// A cooked meal whose cooking can still be taken back.
public nonisolated struct CookedMealUndo: Identifiable, Hashable, Sendable {
    /// How long the undo stays on offer.
    public static let lifetime: Duration = .seconds(5)

    public let id = UUID()
    /// The meal as it was before it was marked cooked; `nil` for a recipe cooked outside the plan.
    public let meal: PlannedMeal?
    /// The dish's name, for the toast.
    public let title: String
    /// What cooking took off the shelves.
    public let draw: ShelfDraw
}

/// One change of a proposed repair as the ledger shows it.
public nonisolated struct RepairLine: Identifiable, Hashable, Sendable {
    public var id: PlannedMealID
    /// The day, the dish and what happens to it.
    public var text: String
    /// Why it changes.
    public var reason: String
}

/// Drives the week ledger: planning, swaps, skips, slides and leftovers, with the shelf balance from verification.
@Observable
@MainActor
public final class LedgerModel {
    /// Days a leftover keeps, counted from the day it was cooked.
    static let leftoverKeepDays = 4
    /// Slots a generated week fills.
    static let plannedSlots: [MealType] = [.dinner]

    public private(set) var plan: MealPlan?
    public private(set) var meals: [PlannedMeal] = []
    public private(set) var recipesByID: [RecipeID: Recipe] = [:]
    public private(set) var foodsByID: [FoodID: Food] = [:]
    public private(set) var profile: UserProfile?
    public private(set) var verification: VerificationReport?
    public private(set) var explanation: PlanExplanation?
    public private(set) var isPlanning = false
    public private(set) var isExplaining = false
    public private(set) var error: LarderError?
    /// Set when a free user with no free week left asks for a plan; the view shows the paywall and clears it.
    public var paywallRequested = false
    /// Whether the user asked "Why this week?".
    public private(set) var showsExplanation = false
    /// Replacements for the selected meal or open slot, best first.
    public private(set) var swapCandidates: [ScoredRecipe] = []
    /// Counts plans saved by `planWeek` and `replan`, so the view can announce each one.
    public private(set) var savedPlanCount = 0
    /// What the user asks the assistant to change about the week, such as "vegetarian Tuesday, use the rice".
    public var adjustDraft = ""
    /// Whether the assistant is reading `adjustDraft`.
    public private(set) var isAdjusting = false
    /// The changes the assistant proposed, waiting for the user to apply them or not.
    public private(set) var proposedAdjustment: WeekAdjustment?
    /// The assistant's question back, when the request was unclear or asked for something it cannot change here.
    public private(set) var adjustQuestion: String?
    /// Set when the user asks for an adjustment before allowing AI help in Settings.
    public private(set) var adjustNeedsConsent = false
    /// Why the last adjustment request failed.
    public private(set) var adjustError: LarderError?
    /// Days of the last adjusted plan whose own change nothing could meet; they kept the planner's dinner.
    public private(set) var unmetAdjustmentDays: [Date] = []
    /// The last cooking, while it can still be undone.
    public private(set) var cookUndo: CookedMealUndo?

    /// Changes for the rest of the week after a skip, a day left uncooked or a lost food, waiting for the user to
    /// apply them or not; never applied on its own.
    public private(set) var proposedRepair: PlanRepair?

    private let plans: any PlanRepository
    private let service: PlanningService
    private let depletion: PantryDepletion
    private let assistant: any AssistantBackend
    private let dates: any DateProvider
    private let calendar: Calendar
    private let isPlus: @Sendable () async -> Bool
    private let canGenerateFreeWeek: @Sendable () async -> Bool
    private let markFreeWeekUsed: @Sendable () async -> Void
    private let profileRepository: any ProfileRepository
    /// Meal identifiers in the order of the last explain request, so meal notes map back to meals.
    private var explainedMealIDs: [PlannedMealID] = []
    /// The meals `proposedRepair` was worked out from, and the skips it answers; a proposal for other meals is stale.
    private var repairBase: [PlannedMeal] = []
    private var repairSkipped: Set<PlannedMealID> = []
    /// The meals before and after the last applied repair.
    private var repairUndo: (before: [PlannedMeal], after: [PlannedMeal])?
    /// The plan and day whose repair the user turned down, so loading does not offer it again that day.
    private var declinedRepair: (plan: MealPlanID, day: Date)?

    /// Creates a model over the given ports; `calendar` decides plan days and which day is today.
    public init(
        plans: any PlanRepository,
        recipes: any RecipeRepository,
        foods: any FoodRepository,
        pantry: any PantryRepository,
        profiles: any ProfileRepository,
        assistant: any AssistantBackend,
        dates: any DateProvider,
        isPlus: @escaping @Sendable () async -> Bool,
        canGenerateFreeWeek: @escaping @Sendable () async -> Bool,
        markFreeWeekUsed: @escaping @Sendable () async -> Void,
        calendar: Calendar = .current
    ) {
        self.plans = plans
        self.service = PlanningService(
            plans: plans, recipes: recipes, foods: foods, pantry: pantry, profiles: profiles, dates: dates, calendar: calendar
        )
        self.depletion = PantryDepletion(recipes: recipes, foods: foods, pantry: pantry, dates: dates)
        self.profileRepository = profiles
        self.assistant = assistant
        self.dates = dates
        self.calendar = calendar
        self.isPlus = isPlus
        self.canGenerateFreeWeek = canGenerateFreeWeek
        self.markFreeWeekUsed = markFreeWeekUsed
    }

    // MARK: Derived

    /// The plan's days in order, each with its meals and open slots.
    public var days: [LedgerDay] {
        guard let plan else { return [] }
        let byID = Dictionary(meals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (0..<max(plan.days, 0)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: plan.startDate) else { return nil }
            let dayMeals = meals
                .filter { calendar.isDate($0.date, inSameDayAs: date) }
                .sorted { Self.slotOrder($0.slot) < Self.slotOrder($1.slot) }
                .map { ledgerMeal($0, source: $0.leftoverOf.flatMap { byID[$0] }) }
            let filled = Set(dayMeals.map(\.meal.slot))
            return LedgerDay(
                date: date,
                isToday: calendar.isDate(date, inSameDayAs: dates.now),
                meals: dayMeals,
                openSlots: Self.plannedSlots.filter { !filled.contains($0) }
            )
        }
    }

    /// The week's food-group bands, once the plan has been verified.
    public var shelfBalance: ShelfBalance? { verification?.shelfBalance }

    /// One sentence naming the first light group, else the first heavy one; `nil` when the week sits comfortably.
    public var balanceSentence: String? {
        shelfBalance.flatMap(LedgerCopy.balanceSentence(for:))
    }

    /// Energy, protein, fibre and sodium per person per day; empty unless the profile opts into numbers.
    public var averages: [NutrientNote] {
        guard profile?.showsNumbers == true else { return [] }
        let shown: [Nutrient] = [.energy, .protein, .fiber, .sodium]
        return shown.compactMap { nutrient in verification?.nutrientNotes.first { $0.nutrient == nutrient } }
    }

    /// The proposed repair's changes in day order, each with why it changes.
    public var repairLines: [RepairLine] {
        guard let proposedRepair else { return [] }
        let title = { (id: RecipeID) in self.recipesByID[id]?.title ?? "" }
        let dayName = { (date: Date) in
            date.formatted(Date.FormatStyle(calendar: self.calendar, timeZone: self.calendar.timeZone).weekday(.wide))
        }
        return proposedRepair.changes.map { change in
            RepairLine(
                id: change.mealID,
                text: LedgerCopy.describe(change, title: title, dayName: dayName),
                reason: LedgerCopy.reason(for: change, lookup: reasonLookup)
            )
        }
    }

    /// Whether the last applied repair can be undone: nothing in the week has changed since.
    public var canUndoRepair: Bool {
        repairUndo.map { $0.after == meals } ?? false
    }

    /// Reason lines for a meal, from its reason codes.
    public func reasons(for meal: PlannedMeal, limit: Int = .max) -> [String] {
        ReasonCopy.lines(for: meal.reasonCodes, lookup: reasonLookup, limit: limit)
    }

    /// Reason lines for a candidate recipe.
    public func reasons(for option: ScoredRecipe, limit: Int = .max) -> [String] {
        ReasonCopy.lines(for: option.reasonCodes, lookup: reasonLookup, limit: limit)
    }

    /// The assistant's note for `meal`, when the last explanation has one.
    public func explanationNote(for meal: PlannedMeal) -> String? {
        guard let index = explainedMealIDs.firstIndex(of: meal.id) else { return nil }
        return explanation?.mealNotes.first { $0.mealIndex == index }?.text
    }

    private var reasonLookup: ReasonCopy.Lookup {
        ReasonCopy.Lookup(
            foodNames: foodsByID.mapValues(\.name),
            mealDates: Dictionary(meals.map { ($0.id, $0.date) }, uniquingKeysWith: { first, _ in first }),
            calendar: calendar
        )
    }

    private func ledgerMeal(_ meal: PlannedMeal, source: PlannedMeal?) -> LedgerMeal {
        let recipe = recipesByID[meal.recipeID]
        let title = recipe?.title ?? ""
        var tag: String?
        if let source, let elapsed = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: source.date), to: calendar.startOfDay(for: meal.date)
        ).day {
            let day = elapsed + 1
            if (2...Self.leftoverKeepDays).contains(day) {
                tag = Copy.Voice.leftoverTag(dish: title, day: day, of: Self.leftoverKeepDays)
            }
        }
        return LedgerMeal(
            meal: meal,
            title: title,
            minutes: recipe.map { $0.prepMinutes + $0.cookMinutes } ?? 0,
            photoFileName: recipe?.photoFileName,
            leftoverTag: tag
        )
    }

    private static func slotOrder(_ slot: MealType) -> Int {
        MealType.allCases.firstIndex(of: slot) ?? 0
    }

    // MARK: Loading

    /// Loads the active plan, its recipes and its verification.
    public func load() async {
        error = nil
        do {
            profile = try await profileRepository.profile()
            let current = try await plans.currentPlan()
            meals = if let current { try await plans.meals(for: current.id) } else { [] }
            plan = current
            try await refresh()
        } catch {
            record(error)
            return
        }
        await checkDay()
    }

    /// The daily check: offers a repair when an earlier day left a meal uncooked or a food the week counted on is gone.
    private func checkDay() async {
        guard let plan, proposedRepair == nil, meals.contains(where: { $0.status == .planned }) else { return }
        if let declinedRepair, declinedRepair.plan == plan.id, calendar.isDate(declinedRepair.day, inSameDayAs: dates.now) { return }
        await proposeRepair(skipped: [])
    }

    /// Reloads recipes and foods for the plan's meals and re-verifies the plan.
    private func refresh() async throws {
        guard let plan else {
            verification = nil
            return
        }
        let catalogue = try await service.catalogue(for: Set(meals.map(\.recipeID)))
        remember(catalogue)
        verification = try await service.verify(meals: meals, days: plan.days, catalogue: catalogue)
    }

    private func remember(_ catalogue: PlanningCatalogue) {
        for candidate in catalogue.candidates { recipesByID[candidate.recipe.id] = candidate.recipe }
        foodsByID.merge(catalogue.foods) { _, new in new }
    }

    // MARK: Planning

    /// Generates a week from today; a free user without a free week left gets the paywall instead.
    public func planWeek() async {
        await generate(locked: [])
    }

    /// Generates a fresh week from today, keeping locked meals when asked.
    public func replan(keepingLocked: Bool) async {
        await generate(locked: keepingLocked ? meals.filter(\.isLocked) : [])
    }

    private func generate(locked: [PlannedMeal], adjustment: WeekAdjustment? = nil) async {
        guard !isPlanning else { return }
        error = nil
        isPlanning = true
        defer { isPlanning = false }
        let plus = await isPlus()
        if !plus {
            guard await canGenerateFreeWeek() else {
                paywallRequested = true
                return
            }
        }
        do {
            let now = dates.now
            let startDate = calendar.startOfDay(for: now)
            let seed = UInt64(max(now.timeIntervalSince1970, 0))
            let result: PlanResult
            var unmetOffsets: [Int] = []
            if let adjustment {
                let adjusted = try await service.planWeek(
                    startDate: startDate, slots: Self.plannedSlots, seed: seed, locked: locked, adjustment: adjustment
                )
                result = adjusted.result
                unmetOffsets = adjusted.unmetDayOffsets
            } else {
                result = try await service.planWeek(startDate: startDate, slots: Self.plannedSlots, seed: seed, locked: locked)
            }
            var newPlan = result.plan
            newPlan.status = .active
            let newMeals = result.meals.map { meal in
                var meal = meal
                meal.planID = newPlan.id
                return meal
            }
            try await archiveCurrentPlan(keeping: Set(newMeals.map(\.id)))
            try await plans.save(newPlan, meals: newMeals)
            plan = newPlan
            meals = newMeals
            verification = result.verification
            explanation = nil
            explainedMealIDs = []
            showsExplanation = false
            unmetAdjustmentDays = unmetOffsets.compactMap { calendar.date(byAdding: .day, value: $0, to: startDate) }
            proposedRepair = nil
            repairSkipped = []
            repairUndo = nil
            if !plus { await markFreeWeekUsed() }
            remember(try await service.catalogue(for: Set(newMeals.map(\.recipeID))))
            savedPlanCount += 1
        } catch {
            record(error)
            return
        }
        await explain()
    }

    /// Archives the stored active plan, leaving out meals that move into the new plan.
    private func archiveCurrentPlan(keeping carried: Set<PlannedMealID>) async throws {
        guard var previous = try await plans.currentPlan() else { return }
        let previousMeals = try await plans.meals(for: previous.id)
        previous.status = .archived
        try await plans.save(previous, meals: previousMeals.filter { !carried.contains($0.id) })
    }

    // MARK: Adjusting

    /// Asks the assistant to turn `adjustDraft` into changes for this week; a Plus feature that needs AI help allowed.
    ///
    /// The proposal waits in `proposedAdjustment` until `applyAdjustment()`; a question back lands in `adjustQuestion`.
    public func requestAdjustment() async {
        let message = adjustDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isAdjusting, !isPlanning else { return }
        dismissAdjustment()
        guard await isPlus() else {
            paywallRequested = true
            return
        }
        isAdjusting = true
        defer { isAdjusting = false }
        do {
            guard let profile = try await profileRepository.profile() else { throw LarderError.notFound }
            guard profile.consents.aiProcessing else {
                adjustNeedsConsent = true
                return
            }
            let diets = try await profileRepository.constraints()
                .filter { $0.axis != .medical && $0.axis != .religious }
                .compactMap { constraint -> DietPattern? in if case .diet(let pattern) = constraint.kind { pattern } else { nil } }
            let edit = try await assistant.adjust(
                request: AdjustRequest(message: message, maxCookMinutes: profile.maxCookMinutes, dietPatterns: Set(diets), goal: profile.goal)
            )
            let adjustment = WeekAdjustment(edit)
            adjustQuestion = edit.clarifyingQuestion
            if !adjustment.isEmpty || adjustment.setAsideCount > 0 { proposedAdjustment = adjustment }
            if adjustQuestion == nil, proposedAdjustment == nil { adjustError = .invalidResponse }
        } catch is CancellationError {
            return
        } catch {
            adjustError = error as? LarderError ?? .assistantUnavailable
        }
    }

    /// Replans the week with the proposed changes, keeping locked dinners; Settings stay as they are.
    public func applyAdjustment() async {
        guard let adjustment = proposedAdjustment, !adjustment.isEmpty else { return }
        proposedAdjustment = nil
        adjustQuestion = nil
        await generate(locked: meals.filter(\.isLocked), adjustment: adjustment)
        if error == nil, !paywallRequested { adjustDraft = "" }
    }

    /// The day a proposed change limited to one day falls on: `offset` days from today, where the next plan starts.
    public func adjustmentDay(_ offset: Int) -> Date? {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: dates.now))
    }

    /// Drops the proposal, the question and any adjustment notice; the typed request stays.
    public func dismissAdjustment() {
        proposedAdjustment = nil
        adjustQuestion = nil
        adjustNeedsConsent = false
        adjustError = nil
        unmetAdjustmentDays = []
    }

    // MARK: Explaining

    /// Shows "Why this week?" and asks the assistant when there is no explanation yet.
    public func requestExplanation() async {
        showsExplanation = true
        if explanation == nil { await explain() }
    }

    /// Hides the explanation.
    public func hideExplanation() {
        showsExplanation = false
    }

    /// Best effort: consent and Plus refusals leave `explanation` empty without an error; other failures
    /// surface only once the user has asked "Why this week?".
    func explain() async {
        guard let plan, !meals.isEmpty else { return }
        isExplaining = true
        defer { isExplaining = false }
        let ordered = meals
            .sorted { ($0.date, Self.slotOrder($0.slot)) < ($1.date, Self.slotOrder($1.slot)) }
            .compactMap { meal in recipesByID[meal.recipeID].map { (meal: meal, title: $0.title) } }
        let request = PlanExplainRequest(
            meals: ordered.map { entry in
                let offset = calendar.dateComponents(
                    [.day], from: calendar.startOfDay(for: plan.startDate), to: calendar.startOfDay(for: entry.meal.date)
                ).day ?? 0
                return PlanExplainRequest.Meal(dayOffset: offset, slot: entry.meal.slot, recipeTitle: entry.title, reasonCodes: entry.meal.reasonCodes)
            },
            foodNames: foodNames(for: ordered.map(\.meal))
        )
        do {
            explanation = try await assistant.explain(plan: request)
            explainedMealIDs = ordered.map(\.meal.id)
        } catch LarderError.consentRequired, LarderError.plusRequired {
            explanation = nil
        } catch {
            if showsExplanation { record(error, fallback: .assistantUnavailable) }
        }
    }

    /// Names of the foods the meals' reason codes mention.
    private func foodNames(for meals: [PlannedMeal]) -> [FoodID: String] {
        var names: [FoodID: String] = [:]
        for code in meals.flatMap(\.reasonCodes) {
            if case .usesExpiring(let food, _) = code, let name = foodsByID[food]?.name { names[food] = name }
        }
        return names
    }

    // MARK: Repairing

    /// Works out a repair of the week as it stands; one without changes clears the proposal.
    private func proposeRepair(skipped: Set<PlannedMealID>) async {
        guard let plan else { return }
        do {
            let repair = try await service.repair(plan: plan, meals: meals, skipped: skipped, slots: Self.plannedSlots)
            guard !repair.changes.isEmpty else {
                proposedRepair = nil
                repairSkipped = []
                return
            }
            var recipes = Set<RecipeID>()
            for change in repair.changes {
                recipes.insert(change.recipeID)
                if case .replaced(let previous) = change.action { recipes.insert(previous) }
            }
            remember(try await service.catalogue(for: recipes))
            repairBase = meals
            repairSkipped = skipped
            proposedRepair = repair
        } catch {
            record(error)
        }
    }

    /// Saves the proposed repair; `undoRepair()` puts the week back until something else changes. When the week
    /// changed after the proposal, a fresh proposal replaces it instead.
    public func applyRepair() async {
        guard let plan, let repair = proposedRepair else { return }
        guard meals == repairBase else {
            await proposeRepair(skipped: repairSkipped)
            return
        }
        error = nil
        let before = meals
        do {
            try await plans.save(plan, meals: repair.result.meals)
        } catch {
            record(error)
            return
        }
        meals = repair.result.meals
        proposedRepair = nil
        repairSkipped = []
        repairUndo = (before, repair.result.meals)
        await reverify()
    }

    /// Puts back the week from before the last applied repair, if nothing changed since.
    public func undoRepair() async {
        guard let plan, let undo = repairUndo, undo.after == meals else {
            repairUndo = nil
            return
        }
        error = nil
        do {
            try await plans.save(plan, meals: undo.before)
        } catch {
            record(error)
            return
        }
        repairUndo = nil
        meals = undo.before
        await reverify()
    }

    /// Keeps the week as it is; loading does not offer a repair again today.
    public func dismissRepair() {
        if let plan { declinedRepair = (plan.id, dates.now) }
        proposedRepair = nil
        repairSkipped = []
    }

    // MARK: Meal actions

    /// Marks a meal as cooked and takes what it used off the shelves, scaled to its servings; a leftover takes
    /// nothing, since its food went with the meal it came from. A meal already cooked is left alone. `cookUndo`
    /// offers to take it back.
    public func markCooked(_ meal: PlannedMeal) async {
        guard let current = meals.first(where: { $0.id == meal.id }), current.status != .cooked else { return }
        error = nil
        let draw: ShelfDraw
        do {
            draw = try await depletion.deplete(cooking: current)
        } catch {
            record(error)
            return
        }
        guard await update(current, { $0.status = .cooked }) else {
            await putBack(draw)
            return
        }
        cookUndo = CookedMealUndo(meal: current, title: recipesByID[current.recipeID]?.title ?? "", draw: draw)
    }

    /// Takes what cooking `recipe` for `servings` used off the shelves, for a recipe cooked outside the plan.
    /// `cookUndo` offers to take it back.
    public func cookOffPlan(_ recipe: Recipe, servings: Int) async {
        error = nil
        do {
            let draw = try await depletion.deplete(cooking: recipe, servings: servings)
            cookUndo = CookedMealUndo(meal: nil, title: recipe.title, draw: draw)
        } catch {
            record(error)
        }
    }

    /// Puts back what the last cooking took and returns its meal to how it was.
    public func undoCooked() async {
        guard let undo = cookUndo else { return }
        cookUndo = nil
        error = nil
        await putBack(undo.draw)
        if let meal = undo.meal {
            await update(meal) { $0.status = meal.status }
        }
    }

    /// Lets the last cooking stand.
    public func dismissCookUndo() {
        cookUndo = nil
    }

    private func putBack(_ draw: ShelfDraw) async {
        do {
            try await depletion.restore(draw)
        } catch {
            record(error)
        }
    }

    /// Marks a meal as skipped; it dims, stops counting towards the shelf, and the rest of the week gets a repair to
    /// apply or not.
    public func skip(_ meal: PlannedMeal) async {
        guard await update(meal, { $0.status = .skipped }) else { return }
        await reverify()
        await proposeRepair(skipped: (proposedRepair == nil ? [] : repairSkipped).union([meal.id]))
    }

    /// Pins a meal so replanning keeps it.
    public func lock(_ meal: PlannedMeal) async {
        await update(meal) { $0.isLocked = true }
    }

    /// Lets replanning change a meal again.
    public func unlock(_ meal: PlannedMeal) async {
        await update(meal) { $0.isLocked = false }
    }

    /// Slides a meal to another day; a meal already in that day's slot trades places with it.
    public func moveMeal(_ meal: PlannedMeal, to date: Date) async {
        guard let current = meals.first(where: { $0.id == meal.id }),
              !calendar.isDate(current.date, inSameDayAs: date)
        else { return }
        if let occupant = meals.first(where: { $0.id != meal.id && $0.slot == meal.slot && calendar.isDate($0.date, inSameDayAs: date) }) {
            guard await update(occupant, { $0.date = current.date }) else { return }
        }
        await update(meal) { $0.date = date }
    }

    /// Loads replacements for `meal` into `swapCandidates`.
    public func loadSwapCandidates(for meal: PlannedMeal) async {
        await loadCandidates(for: meal)
    }

    /// Loads recipes for an empty slot into `swapCandidates`.
    public func loadCandidates(forOpenSlot slot: MealType, on date: Date) async {
        guard let plan else { return }
        await loadCandidates(for: PlannedMeal(planID: plan.id, date: date, slot: slot, recipeID: RecipeID(), servings: 0))
    }

    private func loadCandidates(for meal: PlannedMeal) async {
        error = nil
        swapCandidates = []
        do {
            let found = try await service.swapCandidates(for: meal, in: meals)
            for option in found { recipesByID[option.recipeID] = option.candidate.recipe }
            swapCandidates = found
        } catch {
            record(error)
        }
    }

    /// Puts `option` in the meal's place, records the old recipe, and re-verifies the plan.
    ///
    /// Leftovers of the meal follow the new recipe; a swapped leftover becomes a meal of its own.
    public func swap(_ meal: PlannedMeal, with option: ScoredRecipe) async {
        guard let current = meals.first(where: { $0.id == meal.id }), current.recipeID != option.recipeID else { return }
        recipesByID[option.recipeID] = option.candidate.recipe
        let swapped = await update(current) { meal in
            meal.swapHistory.append(meal.recipeID)
            meal.recipeID = option.recipeID
            meal.reasonCodes = option.reasonCodes
            meal.leftoverOf = nil
        }
        guard swapped else { return }
        for leftover in meals where leftover.leftoverOf == current.id {
            guard await update(leftover, { $0.recipeID = option.recipeID }) else { return }
        }
        swapCandidates = []
        await reverify()
    }

    /// Fills an empty slot with `option` and re-verifies the plan.
    public func fill(_ slot: MealType, on date: Date, with option: ScoredRecipe) async {
        guard let plan else { return }
        error = nil
        recipesByID[option.recipeID] = option.candidate.recipe
        let meal = PlannedMeal(
            planID: plan.id,
            date: date,
            slot: slot,
            recipeID: option.recipeID,
            servings: profile?.householdSize ?? 1,
            reasonCodes: option.reasonCodes
        )
        do {
            try await plans.save(plan, meals: meals + [meal])
            meals.append(meal)
        } catch {
            record(error)
            return
        }
        swapCandidates = []
        await reverify()
    }

    /// Drops a leftover from the plan and takes its servings back off the meal it came from.
    public func removeLeftover(_ meal: PlannedMeal) async {
        guard let plan, let current = meals.first(where: { $0.id == meal.id }), let sourceID = current.leftoverOf else { return }
        error = nil
        var remaining = meals.filter { $0.id != current.id }
        if let index = remaining.firstIndex(where: { $0.id == sourceID }) {
            remaining[index].servings = max(remaining[index].servings - current.servings, 1)
        }
        do {
            try await plans.save(plan, meals: remaining)
            meals = remaining
        } catch {
            record(error)
            return
        }
        await reverify()
    }

    /// Persists one changed meal; returns whether it was saved.
    @discardableResult
    private func update(_ meal: PlannedMeal, _ change: (inout PlannedMeal) -> Void) async -> Bool {
        guard let index = meals.firstIndex(where: { $0.id == meal.id }) else { return false }
        error = nil
        var changed = meals[index]
        change(&changed)
        do {
            try await plans.updateMeal(changed)
        } catch {
            record(error)
            return false
        }
        if let index = meals.firstIndex(where: { $0.id == meal.id }) { meals[index] = changed }
        return true
    }

    private func reverify() async {
        do {
            try await refresh()
        } catch {
            record(error)
        }
    }

    /// Clears the current error.
    public func clearError() {
        error = nil
    }

    private func record(_ failure: any Error, fallback: LarderError = .storageFailure) {
        guard !(failure is CancellationError) else { return }
        error = failure as? LarderError ?? fallback
    }
}
