import Foundation
import LarderCore

/// Foods, ten dinner recipes, a pantry and a profile, adapted from LarderCoreTests/PlanningFixtures.swift.
enum Fixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    static let locale = Locale(identifier: "en_US")

    /// Monday 19 October 2026, 17:00 GMT.
    static let now = date(2026, 10, 19, hour: 17)
    static let today = calendar.startOfDay(for: now)

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) else {
            preconditionFailure("Invalid fixture date \(year)-\(month)-\(day)")
        }
        return date
    }

    /// Midnight `offset` days from today.
    static func day(_ offset: Int) -> Date {
        today.addingTimeInterval(Double(offset) * 86_400)
    }

    /// A food verified free of every allergen except `contains`.
    static func food(
        _ name: String,
        _ group: FoodGroup,
        kcal: Double,
        protein: Double,
        fibre: Double,
        sodium: Double,
        contains: Set<Allergen> = [],
        tags: Set<FoodTag> = []
    ) -> Food {
        Food(
            name: name,
            source: .seedApproximate,
            nutrientsPer100g: Nutrients(energyKcal: kcal, proteinG: protein, fiberG: fibre, sodiumMg: sodium),
            foodGroup: group,
            allergens: AllergenTags(Dictionary(uniqueKeysWithValues: Allergen.allCases.map {
                ($0, contains.contains($0) ? AllergenPresence.contains : .verifiedFree)
            })),
            tags: tags
        )
    }

    static let chicken = food("Chicken thigh", .protein, kcal: 177, protein: 24, fibre: 0, sodium: 90, tags: [.meat, .poultry])
    static let beef = food("Beef mince", .protein, kcal: 250, protein: 26, fibre: 0, sodium: 75, tags: [.meat, .beef])
    static let salmon = food("Salmon fillet", .protein, kcal: 208, protein: 20, fibre: 0, sodium: 60, contains: [.fish], tags: [.fish])
    static let eggs = food("Eggs", .protein, kcal: 143, protein: 13, fibre: 0, sodium: 140, contains: [.egg], tags: [.egg])
    static let tofu = food("Firm tofu", .legumes, kcal: 144, protein: 15, fibre: 2.3, sodium: 14, contains: [.soy])
    static let chickpeas = food("Chickpeas", .legumes, kcal: 139, protein: 7, fibre: 7.6, sodium: 240)
    static let lentils = food("Red lentils", .legumes, kcal: 116, protein: 9, fibre: 7.9, sodium: 2)
    static let blackBeans = food("Black beans", .legumes, kcal: 132, protein: 8.9, fibre: 8.7, sodium: 1)
    static let rice = food("Rice", .grains, kcal: 130, protein: 2.7, fibre: 0.4, sodium: 1)
    static let pasta = food("Pasta", .grains, kcal: 158, protein: 5.8, fibre: 1.8, sodium: 1, contains: [.wheat, .gluten], tags: [.glutenGrain])
    static let cornTortilla = food("Corn tortillas", .grains, kcal: 218, protein: 5.7, fibre: 6.3, sodium: 45)
    static let spinach = food("Spinach, raw", .produce, kcal: 23, protein: 2.9, fibre: 2.2, sodium: 79)
    static let tomato = food("Tomatoes", .produce, kcal: 18, protein: 0.9, fibre: 1.2, sodium: 5)
    static let onion = food("Onion", .produce, kcal: 40, protein: 1.1, fibre: 1.7, sodium: 4)
    static let broccoli = food("Broccoli", .produce, kcal: 34, protein: 2.8, fibre: 2.6, sodium: 33)
    static let sweetPotato = food("Sweet potato", .produce, kcal: 86, protein: 1.6, fibre: 3, sodium: 55)
    static let mushroom = food("Mushrooms", .produce, kcal: 22, protein: 3.1, fibre: 1, sodium: 5)
    static let oliveOil = food("Olive oil", .fats, kcal: 884, protein: 0, fibre: 0, sodium: 2)
    static let parmesan = food("Parmesan", .dairy, kcal: 392, protein: 36, fibre: 0, sodium: 1600, contains: [.milk], tags: [.dairy])
    static let coconutMilk = food("Coconut milk", .fats, kcal: 230, protein: 2.3, fibre: 2.2, sodium: 15)

    static let foods: [Food] = [
        chicken, beef, salmon, eggs, tofu, chickpeas, lentils, blackBeans, rice, pasta, cornTortilla,
        spinach, tomato, onion, broccoli, sweetPotato, mushroom, oliveOil, parmesan, coconutMilk,
    ]
    static let foodsByID = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })

    struct Dish {
        var recipe: Recipe
        var lines: [Ingredient]
    }

    static func dish(_ title: String, cuisine: String, servings: Int, prep: Int, cook: Int, _ parts: [(Food, Double)]) -> Dish {
        let recipe = Recipe(
            title: title,
            origin: .generated,
            servings: servings,
            prepMinutes: prep,
            cookMinutes: cook,
            tags: RecipeTags(cuisine: cuisine, mealTypes: [.dinner], equipment: [.stovetop])
        )
        let lines = parts.map { food, grams in
            Ingredient(
                recipeID: recipe.id, rawText: food.name, quantity: grams, unit: .gram,
                foodID: food.id, gramsResolved: grams, matchConfidence: 1
            )
        }
        return Dish(recipe: recipe, lines: lines)
    }

    static let chickenTikka = dish("Chicken tikka with rice", cuisine: "Indian", servings: 4, prep: 15, cook: 25,
                                   [(chicken, 600), (rice, 300), (tomato, 400), (onion, 150), (oliveOil, 30)])
    static let beefRagu = dish("Beef ragu with pasta", cuisine: "Italian", servings: 4, prep: 15, cook: 40,
                               [(beef, 500), (pasta, 400), (tomato, 400), (onion, 150), (parmesan, 40)])
    static let salmonTraybake = dish("Salmon and sweet potato traybake", cuisine: "British", servings: 2, prep: 10, cook: 25,
                                     [(salmon, 300), (sweetPotato, 400), (broccoli, 200), (oliveOil, 20)])
    static let spinachOmelette = dish("Spinach omelette", cuisine: "French", servings: 2, prep: 5, cook: 10,
                                      [(eggs, 300), (spinach, 150), (parmesan, 30)])
    static let tofuBowl = dish("Tofu and broccoli rice bowl", cuisine: "Japanese", servings: 2, prep: 10, cook: 15,
                               [(tofu, 300), (rice, 150), (broccoli, 200), (oliveOil, 15)])
    static let chickpeaCurry = dish("Chickpea and spinach curry", cuisine: "Indian", servings: 8, prep: 15, cook: 30,
                                    [(chickpeas, 800), (tomato, 800), (spinach, 300), (onion, 300), (coconutMilk, 400), (rice, 600)])
    static let lentilSoup = dish("Red lentil soup", cuisine: "Moroccan", servings: 8, prep: 10, cook: 35,
                                 [(lentils, 500), (tomato, 800), (onion, 300), (sweetPotato, 400), (oliveOil, 40)])
    static let beanTacos = dish("Black bean tacos", cuisine: "Mexican", servings: 4, prep: 10, cook: 15,
                                [(blackBeans, 500), (cornTortilla, 300), (tomato, 300), (onion, 100)])
    static let mushroomRisotto = dish("Mushroom risotto", cuisine: "Italian", servings: 4, prep: 10, cook: 30,
                                      [(rice, 320), (mushroom, 400), (onion, 100), (parmesan, 60), (oliveOil, 20)])
    static let spinachRice = dish("Spinach fried rice", cuisine: "Chinese", servings: 2, prep: 5, cook: 15,
                                  [(rice, 300), (spinach, 150), (eggs, 100), (oliveOil, 15)])

    static let dishes = [
        chickenTikka, beefRagu, salmonTraybake, spinachOmelette, tofuBowl,
        chickpeaCurry, lentilSoup, beanTacos, mushroomRisotto, spinachRice,
    ]
    static let recipes = dishes.map(\.recipe)
    static let lines = Dictionary(uniqueKeysWithValues: dishes.map { ($0.recipe.id, $0.lines) })

    static func pantryItem(_ food: Food, grams: Double, bestBy: Date? = nil) -> PantryItem {
        PantryItem(foodID: food.id, rawName: food.name, quantityGrams: grams, location: .fridge, bestBy: bestBy, source: .manual, addedOn: now)
    }

    /// Spinach is best by tomorrow, so it should lead Tonight.
    static let pantry: [PantryItem] = [
        pantryItem(spinach, grams: 300, bestBy: now.addingTimeInterval(86_400)),
        pantryItem(chicken, grams: 600, bestBy: now.addingTimeInterval(5 * 86_400)),
        pantryItem(rice, grams: 1_000),
        pantryItem(tomato, grams: 500),
        pantryItem(onion, grams: 500),
        pantryItem(oliveOil, grams: 500),
        pantryItem(chickpeas, grams: 800),
    ]

    static func profile(household: Int = 2, showsNumbers: Bool = false, maxCookMinutes: Int = 60) -> UserProfile {
        UserProfile(
            birthYear: 1988,
            heightCm: 170,
            weightKg: 70,
            activityLevel: .moderate,
            goal: .lessWaste,
            householdSize: household,
            currencyCode: "USD",
            maxCookMinutes: maxCookMinutes,
            showsNumbers: showsNumbers
        )
    }

    static func plan(start: Date = today, days: Int = 7, status: PlanStatus = .active) -> MealPlan {
        MealPlan(startDate: start, days: days, constraintsSnapshot: "", solverVersion: "test", seed: 1, status: status)
    }

    static func meal(
        _ dish: Dish,
        in plan: MealPlan,
        day offset: Int,
        slot: MealType = .dinner,
        servings: Int = 2,
        status: MealStatus = .planned,
        leftoverOf: PlannedMealID? = nil,
        reasons: [ReasonCode] = []
    ) -> PlannedMeal {
        PlannedMeal(
            planID: plan.id,
            date: calendar.date(byAdding: .day, value: offset, to: plan.startDate) ?? plan.startDate,
            slot: slot,
            recipeID: dish.recipe.id,
            servings: servings,
            leftoverOf: leftoverOf,
            status: status,
            reasonCodes: reasons
        )
    }
}
