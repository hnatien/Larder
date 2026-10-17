import Foundation
import LarderCore
import Testing
@testable import FeatureLedger

struct WeekAdjustmentTests {
    @Test func keepsChangesThisWeekCanMakeAndSetsAsideTheRest() {
        let edit = ConstraintEdit(
            changes: [
                .addDiet(.vegetarian, dayOffset: 1),
                .addDiet(.vegetarian, dayOffset: 1),
                .setMaxCookMinutes(30, dayOffset: nil),
                .addDislike("  mushrooms "),
                .useUp("rice"),
                .removeDiet(.pescatarian),
                .removeDislike("olives"),
                .addDiet(.vegan, dayOffset: 9),
                .setMaxCookMinutes(0, dayOffset: nil),
                .addDislike(" "),
            ],
            summary: "",
            droppedCount: 2
        )

        let adjustment = WeekAdjustment(edit)

        #expect(adjustment.items == [.diet(.vegetarian, dayOffset: 1), .maxMinutes(30, dayOffset: nil), .avoid("mushrooms"), .useUp("rice")])
        #expect(adjustment.setAsideCount == 6)
        #expect(adjustment.maxCookMinutes == 30)
        #expect(adjustment.dayRules == [1: WeekAdjustment.DayRule(diets: [.vegetarian])])
    }

    @Test func removalsAloneLeaveNothingToApply() {
        let adjustment = WeekAdjustment(ConstraintEdit(changes: [.removeDiet(.vegetarian)], summary: ""))
        #expect(adjustment.isEmpty)
        #expect(adjustment.setAsideCount == 1)
    }

    @Test func weekRulesJoinTheStoredOnesAsHardRulesWithoutRepeats() {
        let stored = [
            DietaryConstraint(axis: .medical, kind: .allergen(.peanut), strictness: .hard, source: .user, lastConfirmed: Fixtures.now),
            DietaryConstraint(axis: .ethical, kind: .diet(.vegetarian), strictness: .hard, source: .user, lastConfirmed: Fixtures.now),
        ]
        let adjustment = WeekAdjustment(ConstraintEdit(
            changes: [.addDiet(.vegetarian, dayOffset: nil), .addDiet(.pescatarian, dayOffset: nil), .addDislike("rice")],
            summary: ""
        ))

        let combined = adjustment.constraints(adding: stored, at: Fixtures.now)

        #expect(Array(combined.prefix(2)) == stored)
        #expect(combined.dropFirst(2).map(\.kind) == [.diet(.pescatarian), .dislike(.name("rice"))])
        #expect(combined.dropFirst(2).allSatisfy { $0.strictness == .hard })
    }

    @Test func aGoalIsAppliedNotSetAsideAndTheLastOneWins() {
        let adjustment = WeekAdjustment(ConstraintEdit(changes: [.setGoal(.saveMoney), .setGoal(.moreProtein)], summary: ""))

        #expect(adjustment.items == [.goal(.saveMoney), .goal(.moreProtein)])
        #expect(adjustment.setAsideCount == 0)
        #expect(adjustment.goal == .moreProtein)
        #expect(WeekAdjustment(ConstraintEdit(changes: [.useUp("rice")], summary: "")).goal == nil)
    }

    @Test func addingKeepsEachChangeOnceAtItsLatestPlaceSoTheLaterLimitWins() {
        let earlier = WeekAdjustment(ConstraintEdit(changes: [.setMaxCookMinutes(30, dayOffset: nil), .useUp("rice")], summary: ""))
        let later = WeekAdjustment(ConstraintEdit(
            changes: [.setMaxCookMinutes(20, dayOffset: nil), .setMaxCookMinutes(30, dayOffset: nil), .removeDiet(.vegan)],
            summary: ""
        ))

        let combined = earlier.adding(later)

        #expect(combined.items == [.useUp("rice"), .maxMinutes(20, dayOffset: nil), .maxMinutes(30, dayOffset: nil)])
        #expect(combined.maxCookMinutes == 30)
        #expect(combined.setAsideCount == 1)
    }

    @Test func useUpMatchesShelfItemsAndFoodNames() {
        let adjustment = WeekAdjustment(ConstraintEdit(changes: [.useUp("rice"), .useUp("spinach")], summary: ""))
        let empty = Fixtures.pantryItem(Fixtures.onion, grams: 0)
        var renamed = Fixtures.pantryItem(Fixtures.spinach, grams: 100)
        renamed.rawName = "Baby leaves"

        let matched = adjustment.useUpFoods(in: [Fixtures.pantryItem(Fixtures.rice, grams: 500), renamed, empty], foods: Fixtures.foodsByID)

        #expect(matched == [Fixtures.rice.id, Fixtures.spinach.id])
    }
}

struct ReplacingMealTests {
    @Test func aReplacedLeftoverStandsAloneAndHandsItsServingsBack() {
        let plan = Fixtures.plan()
        let cooked = Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 0, servings: 4)
        let leftover = Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 1, servings: 2, leftoverOf: cooked.id)
        let option = ScoredRecipe(
            candidate: CandidateBuilder.build(recipes: [Fixtures.tofuBowl.recipe], ingredients: Fixtures.lines, foods: Fixtures.foodsByID)[0],
            score: 1,
            components: ScoreComponents(pantryOverlap: 0, expiryUrgency: 0, timeFit: 0, costProxy: 0, novelty: 0, taste: 0, protein: 0),
            reasonCodes: [.quick(minutes: 25)]
        )

        let meals = PlanningService.replacing(leftover, with: option, in: [cooked, leftover])

        #expect(meals[0].servings == 2)
        #expect(meals[1].recipeID == Fixtures.tofuBowl.recipe.id)
        #expect(meals[1].leftoverOf == nil)
        #expect(meals[1].reasonCodes == [.quick(minutes: 25)])
    }

    @Test func leftoversOfAReplacedMealFollowTheNewRecipe() {
        let plan = Fixtures.plan()
        let cooked = Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 0, servings: 4)
        let leftover = Fixtures.meal(Fixtures.chickpeaCurry, in: plan, day: 1, servings: 2, leftoverOf: cooked.id)
        let option = ScoredRecipe(
            candidate: CandidateBuilder.build(recipes: [Fixtures.lentilSoup.recipe], ingredients: Fixtures.lines, foods: Fixtures.foodsByID)[0],
            score: 1,
            components: ScoreComponents(pantryOverlap: 0, expiryUrgency: 0, timeFit: 0, costProxy: 0, novelty: 0, taste: 0, protein: 0),
            reasonCodes: []
        )

        let meals = PlanningService.replacing(cooked, with: option, in: [cooked, leftover])

        #expect(meals.map(\.recipeID) == [Fixtures.lentilSoup.recipe.id, Fixtures.lentilSoup.recipe.id])
        #expect(meals[0].servings == 4)
        #expect(meals[1].leftoverOf == cooked.id)
    }
}

@MainActor @Suite struct LedgerAdjustTests {
    private static let meatTags: Set<FoodTag> = [.meat, .pork, .beef, .poultry, .fish, .shellfish]

    private func consentingWorld(isPlus: Bool = true) -> World {
        var world = World(isPlus: isPlus)
        world.profiles.stored?.consents.aiProcessing = true
        world.profiles.storedConstraints = [
            DietaryConstraint(axis: .ethical, kind: .diet(.pescatarian), strictness: .hard, source: .user, lastConfirmed: Fixtures.now),
            DietaryConstraint(axis: .religious, kind: .religious(.halal), strictness: .hard, source: .user, lastConfirmed: Fixtures.now),
        ]
        return world
    }

    private func dish(of meal: PlannedMeal) -> Fixtures.Dish? {
        Fixtures.dishes.first { $0.recipe.id == meal.recipeID }
    }

    private func isVegetarian(_ meal: PlannedMeal) -> Bool {
        guard let dish = dish(of: meal) else { return false }
        return dish.lines.allSatisfy { line in
            line.foodID.flatMap { Fixtures.foodsByID[$0] }.map { $0.tags.isDisjoint(with: Self.meatTags) } ?? false
        }
    }

    private func contents(_ model: LedgerModel) -> [AdjustMessage.Content] {
        model.adjustThread.map(\.content)
    }

    @Test func freeUserGetsThePaywallKeepsTheDraftAndTheAssistantIsNotAsked() async {
        let world = consentingWorld(isPlus: false)
        let model = world.ledger()
        model.adjustDraft = "vegetarian Tuesday"
        await model.requestAdjustment()
        #expect(model.paywallRequested)
        #expect(model.adjustDraft == "vegetarian Tuesday")
        #expect(model.adjustThread.isEmpty)
        #expect(await world.assistant.adjustRequests.isEmpty)
    }

    @Test func withoutConsentItAsksForAIHelpFirst() async {
        let world = World()
        let model = world.ledger()
        model.adjustDraft = "vegetarian Tuesday"
        await model.requestAdjustment()
        #expect(contents(model) == [.request("vegetarian Tuesday"), .needsConsent])
        #expect(model.pendingAdjustment == nil)
        #expect(await world.assistant.adjustRequests.isEmpty)
    }

    @Test func allowingAIHelpSavesTheConsentAndAnswersTheSameRequest() async {
        let world = World(isPlus: true)
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [], summary: "", clarifyingQuestion: "Which Tuesday?")))
        let model = world.ledger()
        model.adjustDraft = "vegetarian Tuesday"
        await model.requestAdjustment()

        await model.allowAIHelp()

        #expect(world.profiles.profile()?.consents.aiProcessing == true)
        #expect(contents(model) == [.request("vegetarian Tuesday"), .question("Which Tuesday?")])
        #expect(await world.assistant.adjustRequests.map(\.message) == ["vegetarian Tuesday"])
    }

    @Test func blankRequestDoesNothing() async {
        let world = consentingWorld()
        let model = world.ledger()
        model.adjustDraft = "   "
        await model.requestAdjustment()
        #expect(model.adjustThread.isEmpty)
        #expect(await world.assistant.adjustRequests.isEmpty)
    }

    @Test func requestCarriesOnlyNonSensitiveContextAndProposesChanges() async throws {
        let world = consentingWorld()
        await world.assistant.setAdjustResult(.success(ConstraintEdit(
            changes: [.addDiet(.vegetarian, dayOffset: 1), .useUp("rice")],
            summary: "",
            clarifyingQuestion: "Only Tuesday, or every dinner?"
        )))
        let model = world.ledger()
        model.adjustDraft = "  vegetarian Tuesday, use the rice "
        await model.requestAdjustment()

        let request = try #require(await world.assistant.adjustRequests.first)
        #expect(request == AdjustRequest(message: "vegetarian Tuesday, use the rice", maxCookMinutes: 60, dietPatterns: [.pescatarian], goal: .lessWaste))
        let proposal = WeekAdjustment(ConstraintEdit(changes: [.addDiet(.vegetarian, dayOffset: 1), .useUp("rice")], summary: ""))
        #expect(contents(model) == [
            .request("vegetarian Tuesday, use the rice"),
            .question("Only Tuesday, or every dinner?"),
            .proposal(proposal, .pending),
        ])
        #expect(model.pendingAdjustment == proposal)
        #expect(model.adjustDraft.isEmpty)
        #expect(!model.isAdjusting)
    }

    @Test func aReplyCarriesTheEarlierTurns() async throws {
        let world = consentingWorld()
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [], summary: "", clarifyingQuestion: "Which day?")))
        let model = world.ledger()
        model.adjustDraft = "vegetarian one day"
        await model.requestAdjustment()
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [.addDiet(.vegetarian, dayOffset: 1)], summary: "")))
        model.adjustDraft = "Tuesday"
        await model.requestAdjustment()

        let requests = await world.assistant.adjustRequests
        #expect(requests.map(\.conversation) == [
            [],
            [AdjustRequest.Turn(role: .person, text: "vegetarian one day"), AdjustRequest.Turn(role: .assistant, text: "Which day?")],
        ])
        #expect(requests.last?.message == "Tuesday")
        #expect(model.pendingAdjustment?.items == [.diet(.vegetarian, dayOffset: 1)])
    }

    @Test func aFurtherRequestTakesInThePendingProposal() async throws {
        let world = consentingWorld()
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [.useUp("rice")], summary: "")))
        let model = world.ledger()
        model.adjustDraft = "use the rice"
        await model.requestAdjustment()
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [.addDislike("fish")], summary: "")))
        model.adjustDraft = "and no fish"
        await model.requestAdjustment()

        let first = WeekAdjustment(ConstraintEdit(changes: [.useUp("rice")], summary: ""))
        #expect(contents(model).dropLast() == [.request("use the rice"), .proposal(first, .superseded), .request("and no fish")])
        #expect(model.pendingAdjustment?.items == [.useUp("rice"), .avoid("fish")])
        let second = try #require(await world.assistant.adjustRequests.last)
        #expect(second.conversation.last == AdjustRequest.Turn(role: .assistant, text: "Proposed: Use up the rice"))
    }

    @Test func aQuestionAloneShowsWithoutAProposal() async {
        let world = consentingWorld()
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [], summary: "", clarifyingQuestion: "Which day?")))
        let model = world.ledger()
        model.adjustDraft = "something lighter"
        await model.requestAdjustment()
        #expect(contents(model) == [.request("something lighter"), .question("Which day?")])
        #expect(model.pendingAdjustment == nil)
    }

    @Test func blockedEditsAloneAreReportedAsSetAside() async {
        let world = consentingWorld()
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [], summary: "", droppedCount: 1)))
        let model = world.ledger()
        model.adjustDraft = "I can eat peanuts now"
        await model.requestAdjustment()
        #expect(model.pendingAdjustment?.isEmpty == true)
        #expect(model.pendingAdjustment?.setAsideCount == 1)
        await model.applyAdjustment()
        #expect(await world.plans.saveCount == 0)
    }

    @Test func anEmptyAnswerAsksToRephrase() async {
        let world = consentingWorld()
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [], summary: "")))
        let model = world.ledger()
        model.adjustDraft = "hmm"
        await model.requestAdjustment()
        #expect(contents(model).last == .failure(.invalidResponse, canRetry: false))
    }

    @Test func assistantFailuresStayInTheChat() async {
        let world = consentingWorld()
        await world.assistant.setAdjustResult(.failure(.quotaExceeded))
        let model = world.ledger()
        model.adjustDraft = "quicker dinners"
        await model.requestAdjustment()
        #expect(contents(model) == [.request("quicker dinners"), .failure(.quotaExceeded, canRetry: false)])
        #expect(model.error == nil)
        await model.retryAdjustment()
        #expect(await world.assistant.adjustRequests.count == 1)
    }

    @Test func anUnreachableAssistantCanBeAskedAgainWithoutRepeatingTheRequest() async {
        let world = consentingWorld()
        await world.assistant.setAdjustResult(.failure(.assistantUnavailable))
        let model = world.ledger()
        model.adjustDraft = "quicker dinners"
        await model.requestAdjustment()
        #expect(contents(model).last == .failure(.assistantUnavailable, canRetry: true))
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [.setMaxCookMinutes(30, dayOffset: nil)], summary: "")))

        await model.retryAdjustment()

        #expect(contents(model).filter { if case .request = $0 { true } else { false } } == [.request("quicker dinners")])
        #expect(model.pendingAdjustment?.items == [.maxMinutes(30, dayOffset: nil)])
        #expect(await world.assistant.adjustRequests.map(\.conversation) == [[], []])
    }

    @Test func notNowLeavesTheProposalUnapplied() async {
        let world = consentingWorld()
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [.useUp("rice")], summary: "")))
        let model = world.ledger()
        model.adjustDraft = "use the rice"
        await model.requestAdjustment()

        model.dismissProposal()
        await model.applyAdjustment()

        #expect(contents(model).last == .proposal(WeekAdjustment(ConstraintEdit(changes: [.useUp("rice")], summary: "")), .dismissed))
        #expect(model.pendingAdjustment == nil)
        #expect(await world.plans.saveCount == 0)
    }

    @Test func applyingReplansWithADayRuleAndSaysSo() async throws {
        var world = consentingWorld()
        world.profiles.storedConstraints = []
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [.addDiet(.vegetarian, dayOffset: 1)], summary: "")))
        let model = world.ledger()
        await model.planWeek()
        model.adjustDraft = "vegetarian tomorrow"
        await model.requestAdjustment()
        await model.applyAdjustment()

        let tomorrow = model.meals.filter { Fixtures.calendar.isDate($0.date, inSameDayAs: Fixtures.day(1)) }
        #expect(!tomorrow.isEmpty)
        #expect(tomorrow.allSatisfy(isVegetarian))
        #expect(model.savedPlanCount == 2)
        #expect(model.pendingAdjustment == nil)
        #expect(contents(model).suffix(2) == [
            .proposal(WeekAdjustment(ConstraintEdit(changes: [.addDiet(.vegetarian, dayOffset: 1)], summary: "")), .applied),
            .replanned(unmetDays: []),
        ])
        #expect(model.verification?.hardViolations.isEmpty == true)
    }

    @Test func aLaterApplyKeepsTheChangesAppliedEarlierInTheChat() async throws {
        var world = consentingWorld()
        world.profiles.storedConstraints = []
        let model = world.ledger()
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [.addDislike("rice")], summary: "")))
        model.adjustDraft = "no rice"
        await model.requestAdjustment()
        await model.applyAdjustment()
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [.setMaxCookMinutes(30, dayOffset: nil)], summary: "")))
        model.adjustDraft = "and quick"
        await model.requestAdjustment()
        await model.applyAdjustment()

        #expect(model.savedPlanCount == 2)
        #expect(!model.meals.isEmpty)
        for meal in model.meals {
            let dish = try #require(dish(of: meal))
            #expect(dish.recipe.prepMinutes + dish.recipe.cookMinutes <= 30)
            #expect(!dish.lines.contains { $0.foodID == Fixtures.rice.id })
        }
    }

    @Test func aNewChatStartsWithoutTheEarlierTurns() async throws {
        let world = consentingWorld()
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [], summary: "", clarifyingQuestion: "Which day?")))
        let model = world.ledger()
        model.adjustDraft = "vegetarian one day"
        await model.requestAdjustment()

        model.startNewAdjustment()
        #expect(model.adjustThread.isEmpty)
        model.adjustDraft = "no fish"
        await model.requestAdjustment()

        #expect(await world.assistant.adjustRequests.last?.conversation == [])
    }

    @Test func weekRulesShapeEveryDinner() async throws {
        var world = consentingWorld()
        world.profiles.storedConstraints = []
        await world.assistant.setAdjustResult(.success(ConstraintEdit(
            changes: [.setMaxCookMinutes(30, dayOffset: nil), .addDislike("rice")],
            summary: ""
        )))
        let model = world.ledger()
        model.adjustDraft = "quick, no rice"
        await model.requestAdjustment()
        await model.applyAdjustment()

        #expect(model.plan != nil)
        #expect(!model.meals.isEmpty)
        for meal in model.meals {
            let dish = try #require(dish(of: meal))
            #expect(dish.recipe.prepMinutes + dish.recipe.cookMinutes <= 30)
            #expect(!dish.lines.contains { $0.foodID == Fixtures.rice.id })
        }
    }

    @Test func aWeekGoalPlansAsIfTheProfileHadIt() async throws {
        var world = consentingWorld()
        world.profiles.storedConstraints = []
        let adjustment = WeekAdjustment(ConstraintEdit(changes: [.setGoal(.moreProtein)], summary: ""))

        let adjusted = try await world.service().planWeek(startDate: Fixtures.day(0), seed: 7, locked: [], adjustment: adjustment)
        let usual = try await world.service().planWeek(startDate: Fixtures.day(0), seed: 7, locked: [])
        world.profiles.stored?.goal = .moreProtein
        let protein = try await world.service().planWeek(startDate: Fixtures.day(0), seed: 7, locked: [])

        #expect(adjusted.result.meals.map(\.recipeID) == protein.meals.map(\.recipeID))
        #expect(adjusted.result.meals.map(\.recipeID) != usual.meals.map(\.recipeID))
    }

    @Test func aLockedDinnerKeepsItsPlaceAndItsDayIsReported() async throws {
        var world = consentingWorld()
        world.profiles.storedConstraints = []
        let (_, seeded) = await world.seed { plan in
            [Fixtures.meal(Fixtures.beefRagu, in: plan, day: 2).locked()]
        }
        await world.assistant.setAdjustResult(.success(ConstraintEdit(changes: [.addDiet(.vegetarian, dayOffset: 2)], summary: "")))
        let model = world.ledger()
        await model.load()
        model.adjustDraft = "vegetarian on Wednesday"
        await model.requestAdjustment()
        await model.applyAdjustment()

        #expect(model.meals.contains { $0.id == seeded[0].id && $0.recipeID == Fixtures.beefRagu.recipe.id })
        #expect(model.unmetAdjustmentDays == [Fixtures.day(2)])
        #expect(contents(model).last == .replanned(unmetDays: [Fixtures.day(2)]))
    }
}

private extension PlannedMeal {
    func locked() -> PlannedMeal {
        var meal = self
        meal.isLocked = true
        return meal
    }
}
