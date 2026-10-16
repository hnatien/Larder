import Foundation
@testable import LarderCore

/// Foods, a pantry, fourteen dinner candidates and personas for planning tests.
enum Planning {
    static let now = Fixtures.date(2026, 10, 16)
    static let start = Fixtures.date(2026, 10, 19)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    static func day(_ offset: Double) -> Date {
        now.addingTimeInterval(offset * 86_400)
    }

    /// A food verified free of every allergen except `contains`; `labelled: false` leaves every allergen unknown.
    static func food(
        _ name: String,
        _ group: FoodGroup,
        kcal: Double,
        protein: Double,
        fibre: Double,
        sodium: Double,
        contains: Set<Allergen> = [],
        tags: Set<FoodTag> = [],
        labelled: Bool = true
    ) -> Food {
        let allergens = labelled
            ? Dictionary(uniqueKeysWithValues: Allergen.allCases.map { ($0, contains.contains($0) ? AllergenPresence.contains : .verifiedFree) })
            : [:]
        return Kitchen.food(
            name,
            group: group,
            nutrients: Nutrients(energyKcal: kcal, proteinG: protein, fiberG: fibre, sodiumMg: sodium),
            allergens: allergens,
            tags: tags
        )
    }

    static let chicken = food("chicken thigh", .protein, kcal: 177, protein: 24, fibre: 0, sodium: 90, tags: [.meat, .poultry])
    static let beef = food("beef mince", .protein, kcal: 250, protein: 26, fibre: 0, sodium: 75, tags: [.meat, .beef])
    static let salmon = food("salmon fillet", .protein, kcal: 208, protein: 20, fibre: 0, sodium: 60, contains: [.fish], tags: [.fish])
    static let prawns = food("prawns", .protein, kcal: 99, protein: 24, fibre: 0, sodium: 110, contains: [.crustacean], tags: [.shellfish])
    static let eggs = food("eggs", .protein, kcal: 143, protein: 13, fibre: 0, sodium: 140, contains: [.egg], tags: [.egg])
    static let tofu = food("firm tofu", .legumes, kcal: 144, protein: 15, fibre: 2.3, sodium: 14, contains: [.soy])
    static let chickpeas = food("chickpeas", .legumes, kcal: 139, protein: 7, fibre: 7.6, sodium: 240)
    static let lentils = food("red lentils", .legumes, kcal: 116, protein: 9, fibre: 7.9, sodium: 2)
    static let blackBeans = food("black beans", .legumes, kcal: 132, protein: 8.9, fibre: 8.7, sodium: 1)
    static let rice = food("rice", .grains, kcal: 130, protein: 2.7, fibre: 0.4, sodium: 1)
    static let pasta = food("pasta", .grains, kcal: 158, protein: 5.8, fibre: 1.8, sodium: 1, contains: [.wheat, .gluten], tags: [.glutenGrain])
    static let cornTortilla = food("corn tortillas", .grains, kcal: 218, protein: 5.7, fibre: 6.3, sodium: 45)
    static let soySauce = food(
        "soy sauce", .other, kcal: 53, protein: 8, fibre: 0.8, sodium: 5500,
        contains: [.soy, .wheat, .gluten], tags: [.glutenGrain, .highSodium]
    )
    static let spinach = food("spinach", .produce, kcal: 23, protein: 2.9, fibre: 2.2, sodium: 79)
    static let tomato = food("tomatoes", .produce, kcal: 18, protein: 0.9, fibre: 1.2, sodium: 5)
    static let onion = food("onion", .produce, kcal: 40, protein: 1.1, fibre: 1.7, sodium: 4)
    static let broccoli = food("broccoli", .produce, kcal: 34, protein: 2.8, fibre: 2.6, sodium: 33)
    static let sweetPotato = food("sweet potato", .produce, kcal: 86, protein: 1.6, fibre: 3, sodium: 55)
    static let mushroom = food("mushrooms", .produce, kcal: 22, protein: 3.1, fibre: 1, sodium: 5)
    static let oliveOil = food("olive oil", .fats, kcal: 884, protein: 0, fibre: 0, sodium: 2)
    static let parmesan = food("parmesan", .dairy, kcal: 392, protein: 36, fibre: 0, sodium: 1600, contains: [.milk], tags: [.dairy])
    static let coconutMilk = food("coconut milk", .fats, kcal: 230, protein: 2.3, fibre: 2.2, sodium: 15)
    static let almonds = food("almonds", .fats, kcal: 579, protein: 21, fibre: 12.5, sodium: 1, contains: [.treeNut])
    /// Allergen data missing entirely: never safe under any allergen constraint.
    static let tahini = food("tahini", .fats, kcal: 595, protein: 17, fibre: 9.3, sodium: 115, labelled: false)

    static let allFoods: [Food] = [
        chicken, beef, salmon, prawns, eggs, tofu, chickpeas, lentils, blackBeans, rice, pasta, cornTortilla, soySauce,
        spinach, tomato, onion, broccoli, sweetPotato, mushroom, oliveOil, parmesan, coconutMilk, almonds, tahini,
    ]
    static let foods = Dictionary(uniqueKeysWithValues: allFoods.map { ($0.id, $0) })

    /// A dinner candidate built through `CandidateBuilder`; each line is (food, grams).
    static func dish(
        _ title: String,
        cuisine: String?,
        servings: Int,
        prep: Int,
        cook: Int,
        equipment: Set<Equipment> = [.stovetop],
        diet: Set<DietPattern> = [],
        mealTypes: Set<MealType> = [.dinner],
        _ lines: [(Food, Double)],
        optional: [(Food, Double)] = [],
        garnish: [(Food, Double)] = []
    ) -> RecipeCandidate {
        let recipe = Recipe(
            title: title,
            origin: .generated,
            servings: servings,
            prepMinutes: prep,
            cookMinutes: cook,
            tags: RecipeTags(cuisine: cuisine, mealTypes: mealTypes, equipment: equipment, dietFlags: diet)
        )
        func line(_ entry: (Food, Double), optional: Bool = false, garnish: Bool = false) -> Ingredient {
            Kitchen.line(entry.0.name, entry.1, .gram, food: entry.0, recipe: recipe.id, grams: entry.1, optional: optional, garnish: garnish)
        }
        let ingredients = lines.map { line($0) } + optional.map { line($0, optional: true) } + garnish.map { line($0, garnish: true) }
        return CandidateBuilder.build(recipes: [recipe], ingredients: [recipe.id: ingredients], foods: foods)[0]
    }

    static let chickenTikka = dish(
        "Chicken tikka with rice", cuisine: "Indian", servings: 4, prep: 15, cook: 25,
        [(chicken, 600), (rice, 300), (tomato, 400), (onion, 150), (oliveOil, 30)]
    )
    static let beefRagu = dish(
        "Beef ragu with pasta", cuisine: "Italian", servings: 4, prep: 15, cook: 45,
        [(beef, 500), (pasta, 400), (tomato, 400), (onion, 150), (parmesan, 40)]
    )
    static let salmonTraybake = dish(
        "Salmon and sweet potato traybake", cuisine: "British", servings: 2, prep: 10, cook: 25, equipment: [.oven],
        [(salmon, 300), (sweetPotato, 400), (broccoli, 200), (oliveOil, 20)]
    )
    static let prawnStirFry = dish(
        "Prawn and broccoli stir-fry", cuisine: "Chinese", servings: 2, prep: 10, cook: 10,
        [(prawns, 250), (rice, 150), (broccoli, 200), (oliveOil, 15)]
    )
    static let spinachOmelette = dish(
        "Spinach omelette", cuisine: "French", servings: 1, prep: 5, cook: 10, diet: [.vegetarian],
        [(eggs, 150), (spinach, 80), (parmesan, 15)]
    )
    static let tofuBowl = dish(
        "Tofu and broccoli rice bowl", cuisine: "Japanese", servings: 2, prep: 10, cook: 15, diet: [.vegan, .vegetarian],
        [(tofu, 300), (rice, 150), (broccoli, 200), (oliveOil, 15)]
    )
    static let chickpeaCurry = dish(
        "Chickpea and spinach curry", cuisine: "Indian", servings: 8, prep: 15, cook: 30, diet: [.vegan, .vegetarian],
        [(chickpeas, 800), (tomato, 800), (spinach, 300), (onion, 300), (coconutMilk, 400), (rice, 600)]
    )
    static let lentilSoup = dish(
        "Red lentil soup", cuisine: "Moroccan", servings: 8, prep: 10, cook: 35, diet: [.vegan, .vegetarian],
        [(lentils, 500), (tomato, 800), (onion, 300), (sweetPotato, 400), (oliveOil, 40)]
    )
    static let falafelBowl = dish(
        "Falafel bowl", cuisine: "Lebanese", servings: 4, prep: 15, cook: 20, diet: [.vegan, .vegetarian],
        [(chickpeas, 500), (tahini, 60), (tomato, 300), (onion, 100), (oliveOil, 30)]
    )
    static let romescoChicken = dish(
        "Romesco chicken", cuisine: "Spanish", servings: 4, prep: 10, cook: 30, equipment: [.oven],
        [(chicken, 600), (almonds, 80), (tomato, 300), (sweetPotato, 400), (oliveOil, 30)]
    )
    static let beanTacos = dish(
        "Black bean tacos", cuisine: "Mexican", servings: 4, prep: 10, cook: 15, diet: [.vegan, .vegetarian],
        [(blackBeans, 500), (cornTortilla, 300), (tomato, 300), (onion, 100)]
    )
    static let bulgogiBowl = dish(
        "Beef bulgogi rice bowl", cuisine: "Korean", servings: 2, prep: 15, cook: 15,
        [(beef, 300), (rice, 150), (onion, 100), (spinach, 100)]
    )
    static let mushroomRisotto = dish(
        "Mushroom risotto", cuisine: "Italian", servings: 4, prep: 10, cook: 30, diet: [.vegetarian],
        [(rice, 320), (mushroom, 400), (onion, 100), (parmesan, 60), (oliveOil, 20)]
    )
    static let salmonTeriyaki = dish(
        "Salmon teriyaki", cuisine: "Japanese", servings: 2, prep: 10, cook: 15,
        [(salmon, 300), (soySauce, 40), (rice, 150), (broccoli, 150)]
    )

    static let candidates: [RecipeCandidate] = [
        chickenTikka, beefRagu, salmonTraybake, prawnStirFry, spinachOmelette, tofuBowl, chickpeaCurry,
        lentilSoup, falafelBowl, romescoChicken, beanTacos, bulgogiBowl, mushroomRisotto, salmonTeriyaki,
    ]

    static func pantryItem(_ food: Food, grams: Double, bestBy: Date? = nil) -> PantryItem {
        PantryItem(foodID: food.id, rawName: food.name, quantityGrams: grams, location: .fridge, bestBy: bestBy, source: .manual, addedOn: now)
    }

    static let pantry: [PantryItem] = [
        pantryItem(spinach, grams: 200, bestBy: day(1)),
        pantryItem(chicken, grams: 600, bestBy: day(2)),
        pantryItem(rice, grams: 1000),
        pantryItem(tomato, grams: 500, bestBy: day(9)),
        pantryItem(onion, grams: 500),
        pantryItem(oliveOil, grams: 500),
        pantryItem(chickpeas, grams: 800),
    ]

    static func profile(
        household: Int = 4,
        maxCookMinutes: Int = 60,
        equipment: Set<Equipment> = [],
        goal: Goal = .maintain
    ) -> UserProfile {
        UserProfile(
            birthYear: 1988,
            heightCm: 170,
            weightKg: 70,
            activityLevel: .moderate,
            goal: goal,
            householdSize: household,
            currencyCode: "USD",
            maxCookMinutes: maxCookMinutes,
            equipment: equipment
        )
    }

    static func context(
        pantry: [PantryItem] = pantry,
        goal: Goal = .maintain,
        maxCookMinutes: Int = 60,
        recentlyPlanned: [RecipeID: Date] = [:],
        recentCuisines: [String: Date] = [:],
        liked: Set<RecipeID> = [],
        skipped: Set<RecipeID> = []
    ) -> ScoringContext {
        ScoringContext(
            pantry: pantry,
            foods: foods,
            now: now,
            recentlyPlanned: recentlyPlanned,
            recentCuisines: recentCuisines,
            liked: liked,
            skipped: skipped,
            goal: goal,
            maxCookMinutes: maxCookMinutes
        )
    }

    static func compiled(
        _ constraints: [DietaryConstraint] = [],
        household: Int = 4,
        maxCookMinutes: Int = 60,
        equipment: Set<Equipment> = [],
        targets: [NutrientTarget]? = nil
    ) -> CompiledConstraints {
        let profile = profile(household: household, maxCookMinutes: maxCookMinutes, equipment: equipment)
        return ConstraintCompiler.compile(
            profile: profile,
            constraints: constraints,
            targets: targets ?? NutrientTargets.defaults(for: profile, constraints: constraints, referenceYear: 2026)
        )
    }

    static func request(
        _ constraints: [DietaryConstraint] = [],
        candidates: [RecipeCandidate] = candidates,
        household: Int = 4,
        maxCookMinutes: Int = 60,
        equipment: Set<Equipment> = [],
        targets: [NutrientTarget]? = nil,
        days: Int = 7,
        seed: UInt64 = 1,
        lockedMeals: [PlannedMeal] = [],
        liked: Set<RecipeID> = [],
        pantry: [PantryItem] = pantry
    ) -> PlanRequest {
        PlanRequest(
            startDate: start,
            days: days,
            candidates: candidates,
            compiled: compiled(constraints, household: household, maxCookMinutes: maxCookMinutes, equipment: equipment, targets: targets),
            context: context(pantry: pantry, maxCookMinutes: maxCookMinutes, liked: liked),
            lockedMeals: lockedMeals,
            seed: seed,
            planID: MealPlanID(),
            calendar: calendar
        )
    }

    static func recipe(_ id: RecipeID) -> RecipeCandidate? {
        candidates.first { $0.recipe.id == id }
    }
}

/// Simulated users for feasibility and safety sweeps.
enum Persona: String, CaseIterable, Sendable {
    case nutAllergy
    case coeliac
    case vegan

    var constraints: [DietaryConstraint] {
        switch self {
        case .nutAllergy: [Kitchen.constraint(.allergen(.treeNut))]
        case .coeliac: [Kitchen.constraint(.medical(.coeliacDisease))]
        case .vegan: [Kitchen.constraint(.diet(.vegan), axis: .ethical)]
        }
    }
}
