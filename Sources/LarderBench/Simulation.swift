import Foundation
import LarderCore

/// A household's pantry over the simulation, with every gram that leaves it booked as used or expired.
struct PantryLedger {
    private(set) var items: [PantryItem]
    let foods: [FoodID: Food]
    private let startingItems: Set<PantryItemID>
    /// Perishable grams cooked before their best-by, and perishable grams thrown out at it.
    private(set) var usedPerishable = 0.0
    private(set) var expiredPerishable = 0.0
    /// The same, for perishables already in the kitchen when the simulation started.
    private(set) var usedStarting = 0.0
    private(set) var expiredStarting = 0.0
    /// Every expired gram, perishable or not.
    private(set) var expiredTotal = 0.0
    private var nextID = 0
    private let idPrefix: String

    init(items: [PantryItem], foods: [FoodID: Food], idPrefix: String) {
        self.items = items
        self.foods = foods
        self.idPrefix = idPrefix
        startingItems = Set(items.filter { item in item.foodID.flatMap { foods[$0] }.map(Shelf.isPerishable) == true }.map(\.id))
    }

    mutating func add(_ food: Food, grams: Double, bestBy: Date?, on date: Date, source: PantrySource) {
        guard grams.isFinite, grams > 0 else { return }
        nextID += 1
        items.append(PantryItem(
            id: PantryItemID(rawValue: SeedCatalogue.uuid(for: "\(idPrefix)/\(nextID)")),
            foodID: food.id,
            rawName: food.name,
            quantityGrams: grams,
            location: StorageLocation.usual(forItemNamed: food.name, food: food),
            bestBy: bestBy,
            source: source,
            addedOn: date
        ))
    }

    /// Takes `grams` of `food`, soonest best-by first; returns the grams the pantry could not supply.
    @discardableResult
    mutating func consume(_ food: FoodID, grams: Double) -> Double {
        var remaining = grams
        let order = items.indices
            .filter { items[$0].foodID == food && items[$0].quantityGrams > 0 }
            .sorted { lhs, rhs in
                let left = items[lhs].bestBy ?? .distantFuture
                let right = items[rhs].bestBy ?? .distantFuture
                return left != right ? left < right : lhs < rhs
            }
        for index in order where remaining > 0 {
            let taken = min(items[index].quantityGrams, remaining)
            items[index].quantityGrams -= taken
            remaining -= taken
            book(items[index], grams: taken, expired: false)
        }
        items.removeAll { $0.quantityGrams <= 1e-9 }
        return remaining
    }

    /// Throws out everything whose best-by is before `date`.
    mutating func expire(before date: Date) {
        for item in items {
            if let bestBy = item.bestBy, bestBy < date { book(item, grams: item.quantityGrams, expired: true) }
        }
        items.removeAll { item in item.bestBy.map { $0 < date } ?? false }
    }

    private mutating func book(_ item: PantryItem, grams: Double, expired: Bool) {
        if expired { expiredTotal += grams }
        guard let food = item.foodID.flatMap({ foods[$0] }), Shelf.isPerishable(food) else { return }
        if expired { expiredPerishable += grams } else { usedPerishable += grams }
        if startingItems.contains(item.id) {
            if expired { expiredStarting += grams } else { usedStarting += grams }
        }
    }
}

/// What happened to one household under one arm over the whole run.
struct HouseholdRun: Sendable {
    var household: Household
    var arm: String
    var weeks: [WeekRecord]
    var pantryUse: Double?
    var startingPantryUse: Double?
    var expiredGrams: Double
    var expiredPerishableGrams: Double
}

/// One simulated week of one household under one arm.
struct WeekRecord: Sendable {
    /// Planned meals with the status the household gave them.
    var plan: [PlannedMeal]
    var unfilledSlots: Int
    var groceryLines: Int
    var hardViolations: Int
    var nutrientNotes: [NutrientNote]
    var solveSeconds: Double
    var tonightMeals: Int
    /// Lower-cased cuisine of each meal cooked from scratch in the plan; "none" for a recipe without one.
    var cuisines: [String]
}

/// Runs households through rolling weeks: plan, shop, cook day by day with deviations, expire, then plan again.
struct Simulation: Sendable {
    let catalogue: SeedCatalogue
    let seed: UInt64
    let weeks: Int
    let startDate: Date
    let calendar: Calendar
    let slots: [MealType] = [.dinner]
    static let daysPerWeek = 7
    /// History windows, as `PlanningService` uses them.
    static let recentDays = 28
    static let recentCuisineDays = 7
    static let tasteDays = 90

    /// Monday 19 October 2026, midnight GMT.
    static let defaultStart: Date = {
        var components = DateComponents(year: 2026, month: 10, day: 19)
        components.timeZone = .gmt
        return gregorian.date(from: components) ?? Date(timeIntervalSince1970: 1_792_368_000)
    }()

    static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    init(catalogue: SeedCatalogue, seed: UInt64, weeks: Int, startDate: Date = defaultStart, calendar: Calendar = gregorian) {
        self.catalogue = catalogue
        self.seed = seed
        self.weeks = weeks
        self.startDate = startDate
        self.calendar = calendar
    }

    func run(_ household: Household, arm: any Arm) -> HouseholdRun {
        var ledger = PantryLedger(
            items: household.pantry, foods: catalogue.foods, idPrefix: "run/\(seed)/\(household.index)/\(arm.name)"
        )
        let compiled = household.compiled
        let impulseFoods = HouseholdGenerator.usableFoods(catalogue: catalogue, compiled: compiled).filter(Shelf.isPerishable)
        var history: [PlannedMeal] = []
        var records: [WeekRecord] = []

        for week in 0..<weeks {
            let weekStart = day(week * Self.daysPerWeek)
            let input = WeekInput(
                household: household,
                week: week,
                startDate: weekStart,
                days: Self.daysPerWeek,
                slots: slots,
                candidates: catalogue.candidates,
                compiled: compiled,
                context: context(household: household, pantry: ledger.items, history: history, now: weekStart),
                seed: SeedMix.mix(seed, UInt64(household.index), UInt64(week)),
                planID: MealPlanID(rawValue: SeedCatalogue.uuid(for: "plan/\(seed)/\(household.index)/\(week)/\(arm.name)")),
                calendar: calendar
            )
            let clock = ContinuousClock()
            let started = clock.now
            let weekPlan = arm.plan(input)
            let solveSeconds = (clock.now - started) / .seconds(1)
            let report = verify(weekPlan.meals, compiled: compiled)

            // Shop once for the week, net of the pantry, in whole packs.
            let grocery = GroceryListBuilder().build(
                meals: weekPlan.meals, recipes: catalogue.recipes, ingredients: catalogue.ingredients,
                foods: catalogue.foods, pantry: ledger.items
            )
            var shop = Draws(seed: SeedMix.mix(seed, 0x5348_4F50, UInt64(household.index), UInt64(week)))
            for item in grocery.items {
                guard let needed = item.neededGrams, let food = item.foodID.flatMap({ catalogue.foods[$0] }) else { continue }
                let pack = Shelf.packGrams(food.foodGroup)
                ledger.add(
                    food, grams: (needed / pack).rounded(.up) * pack,
                    bestBy: calendar.date(byAdding: .day, value: shop.integer(Shelf.boughtShelfLife(food.foodGroup)), to: weekStart),
                    on: weekStart, source: .receipt
                )
            }
            // The extra-purchase draw comes from its own stream so it does not depend on the grocery list's length.
            var extras = Draws(seed: SeedMix.mix(seed, 0x4558_5452, UInt64(household.index), UInt64(week)))
            if extras.chance(household.behaviour.extraPurchaseProbability), !impulseFoods.isEmpty {
                for food in extras.sample(impulseFoods, count: extras.integer(1...3)) {
                    ledger.add(
                        food, grams: Shelf.packGrams(food.foodGroup),
                        bestBy: calendar.date(byAdding: .day, value: extras.integer(Shelf.boughtShelfLife(food.foodGroup)), to: weekStart),
                        on: weekStart, source: .receipt
                    )
                }
            }

            var eaten: [PlannedMeal] = []
            var tonight: [PlannedMeal] = []
            var cookedAsPlanned = Set<PlannedMealID>()
            for offset in 0..<Self.daysPerWeek {
                let date = day(week * Self.daysPerWeek + offset)
                // Rolls depend only on household, week and day, so every arm meets the same deviations.
                var rolls = Draws(seed: SeedMix.mix(seed, 0x4441_59, UInt64(household.index), UInt64(week), UInt64(offset)))
                let skipRoll = rolls.unit()
                let tonightRoll = rolls.unit()
                for var meal in weekPlan.meals.filter({ calendar.isDate($0.date, inSameDayAs: date) }) {
                    if let source = meal.leftoverOf {
                        meal.status = cookedAsPlanned.contains(source) ? .cooked : .skipped
                    } else if skipRoll < household.behaviour.skipProbability {
                        meal.status = .skipped
                    } else if tonightRoll < household.behaviour.tonightProbability,
                              let pick = TonightPicker.pick(
                                  candidates: catalogue.candidates,
                                  admission: { compiled.admits($0, foods: catalogue.foods) },
                                  context: context(household: household, pantry: ledger.items, history: history + eaten, now: date),
                                  limit: 1
                              ).first,
                              pick.recipeID != meal.recipeID {
                        meal.status = .skipped
                        var replacement = PlannedMeal(
                            id: PlannedMealID(rawValue: SeedCatalogue.uuid(for: "tonight/\(meal.id.rawValue.uuidString)")),
                            planID: meal.planID, date: date, slot: meal.slot, recipeID: pick.recipeID,
                            servings: compiled.householdSize, status: .cooked, swapHistory: [meal.recipeID]
                        )
                        cook(replacement, ledger: &ledger)
                        replacement.reasonCodes = pick.reasonCodes
                        tonight.append(replacement)
                        eaten.append(replacement)
                        // The planned meal is replaced, not skipped: keep it out of the history so taste only learns the swap.
                        continue
                    } else {
                        meal.status = .cooked
                        cookedAsPlanned.insert(meal.id)
                        cook(meal, ledger: &ledger)
                    }
                    eaten.append(meal)
                }
                ledger.expire(before: day(week * Self.daysPerWeek + offset + 1))
            }

            let tonightReport = verify(tonight, compiled: compiled)
            var planned = weekPlan.meals
            for index in planned.indices {
                planned[index].status = eaten.first { $0.id == planned[index].id }?.status ?? .skipped
            }
            records.append(WeekRecord(
                plan: planned,
                unfilledSlots: weekPlan.unfilledSlots,
                groceryLines: grocery.items.count,
                hardViolations: report.hardViolations.count + tonightReport.hardViolations.count,
                nutrientNotes: report.nutrientNotes,
                solveSeconds: solveSeconds,
                tonightMeals: tonight.count,
                cuisines: planned.filter { $0.leftoverOf == nil }.map { meal in
                    catalogue.recipes[meal.recipeID]?.tags.cuisine?.lowercased() ?? "none"
                }
            ))
            history += eaten
        }

        let resolved = ledger.usedPerishable + ledger.expiredPerishable
        let startingResolved = ledger.usedStarting + ledger.expiredStarting
        return HouseholdRun(
            household: household,
            arm: arm.name,
            weeks: records,
            pantryUse: resolved > 0 ? ledger.usedPerishable / resolved : nil,
            startingPantryUse: startingResolved > 0 ? ledger.usedStarting / startingResolved : nil,
            expiredGrams: ledger.expiredTotal,
            expiredPerishableGrams: ledger.expiredPerishable
        )
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: startDate) ?? startDate
    }

    /// Takes a cooked meal's ingredient grams out of the pantry, resolved exactly as the grocery list resolves them.
    private func cook(_ meal: PlannedMeal, ledger: inout PantryLedger) {
        var asPlanned = meal
        asPlanned.status = .planned
        asPlanned.leftoverOf = nil
        let needs = GroceryListBuilder().build(
            meals: [asPlanned], recipes: catalogue.recipes, ingredients: catalogue.ingredients,
            foods: catalogue.foods, pantry: []
        )
        for item in needs.items {
            guard let food = item.foodID, let grams = item.neededGrams else { continue }
            ledger.consume(food, grams: grams)
        }
    }

    private func verify(_ meals: [PlannedMeal], compiled: CompiledConstraints) -> VerificationReport {
        PlanVerifier.verify(
            meals: meals,
            candidates: catalogue.candidates,
            foods: catalogue.foods,
            constraints: compiled.constraints,
            targets: compiled.targets,
            days: Self.daysPerWeek,
            householdSize: compiled.householdSize,
            slots: Set(slots)
        )
    }

    /// The scoring context the app would build on `now`: recency from the last 28 days, cuisines from the last 7 and
    /// taste learned from the last 90 (mirrors `PlanningService.context`).
    func context(household: Household, pantry: [PantryItem], history: [PlannedMeal], now: Date) -> ScoringContext {
        let recentStart = calendar.date(byAdding: .day, value: -Self.recentDays, to: now) ?? now
        let cuisineStart = calendar.date(byAdding: .day, value: -Self.recentCuisineDays, to: now) ?? now
        let tasteStart = calendar.date(byAdding: .day, value: -Self.tasteDays, to: now) ?? now
        var recentlyPlanned: [RecipeID: Date] = [:]
        var recentCuisines: [String: Date] = [:]
        for meal in history where meal.date > recentStart && meal.date <= now {
            recentlyPlanned[meal.recipeID] = max(recentlyPlanned[meal.recipeID] ?? meal.date, meal.date)
            if meal.date > cuisineStart, let cuisine = catalogue.recipes[meal.recipeID]?.tags.cuisine {
                let key = cuisine.lowercased()
                recentCuisines[key] = max(recentCuisines[key] ?? meal.date, meal.date)
            }
        }
        return ScoringContext(
            pantry: pantry,
            foods: catalogue.foods,
            now: now,
            recentlyPlanned: recentlyPlanned,
            recentCuisines: recentCuisines,
            taste: TasteAffinity.learn(
                from: history.filter { $0.date > tasteStart && $0.date <= now },
                candidates: catalogue.candidates, foods: catalogue.foods, now: now
            ),
            goal: household.profile.goal,
            maxCookMinutes: household.profile.maxCookMinutes,
            weeklyBudget: household.profile.weeklyBudget
        )
    }
}
