import Foundation
import LarderCore

/// The constraint profile a synthetic household is built around: the three planning-test personas
/// (`Tests/LarderCoreTests/PlanningFixtures.swift`) plus allergen, medical and time-poor variants.
enum Persona: String, CaseIterable, Codable, Sendable {
    case unrestricted
    case nutAllergy
    case coeliac
    case vegan
    /// One of `Persona.allergens`, drawn per household.
    case allergen
    case hypertension
    case kidneyDisease
    /// A 30-minute cooking cap.
    case timePoor

    static let allergens: [Allergen] = [.milk, .egg, .peanut, .sesame, .fish, .crustacean, .soy]
    static let timePoorMinutes = 30
}

/// How a household departs from its plan; each probability applies independently per dinner or per week.
struct Behaviour: Codable, Hashable, Sendable {
    /// A planned dinner is not cooked; its ingredients stay in the pantry.
    var skipProbability: Double
    /// A planned dinner is replaced by the top Tonight pick from what is in the pantry.
    var tonightProbability: Double
    /// The weekly shop also brings home one to three packs of perishables nobody planned for, drawn from foods the
    /// household's admitted dinners use.
    var extraPurchaseProbability: Double
}

/// One synthetic household: who they are, what they must not eat, what is in their kitchen and how they behave.
struct Household: Codable, Sendable {
    var index: Int
    var persona: Persona
    /// Persona plus any layered variant, for example `vegan+timePoor` or `allergen(sesame)`.
    var label: String
    var profile: UserProfile
    var constraints: [DietaryConstraint]
    var targets: [NutrientTarget]
    var pantry: [PantryItem]
    var behaviour: Behaviour

    var compiled: CompiledConstraints {
        ConstraintCompiler.compile(profile: profile, constraints: constraints, targets: targets)
    }
}

/// Seeded, platform-stable draws; the standard library's `random(in:using:)` is not promised to stay stable across releases.
struct Draws {
    private var generator: SeededRandom

    init(seed: UInt64) {
        generator = SeededRandom(seed: seed)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double {
        Double(generator.next() >> 11) / Double(UInt64(1) << 53)
    }

    mutating func uniform(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * unit()
    }

    /// Uniform integer in `range`.
    mutating func integer(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(generator.next() % UInt64(range.count))
    }

    mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }

    mutating func element<Element>(of array: [Element]) -> Element {
        array[integer(0...(array.count - 1))]
    }

    /// `count` distinct elements in draw order (a partial Fisher-Yates shuffle).
    mutating func sample<Element>(_ array: [Element], count: Int) -> [Element] {
        var pool = array
        let take = min(count, pool.count)
        for index in 0..<take {
            pool.swapAt(index, integer(index...(pool.count - 1)))
        }
        return Array(pool.prefix(take))
    }

    /// One value from a discrete distribution given as (value, weight) pairs.
    mutating func weighted<Value>(_ options: [(Value, Double)]) -> Value {
        let total = options.reduce(0) { $0 + $1.1 }
        var roll = unit() * total
        for (value, weight) in options {
            if roll < weight { return value }
            roll -= weight
        }
        return options[options.count - 1].0
    }
}

/// Order-sensitive mixing of seed parts into one seed, so every household, week and day gets its own stream.
enum SeedMix {
    static func mix(_ parts: UInt64...) -> UInt64 {
        var state: UInt64 = 0x243F_6A88_85A3_08D3
        for part in parts {
            var generator = SeededRandom(seed: state ^ part)
            state = generator.next()
        }
        return state
    }
}

/// Shelf lives, pack sizes and quantities by food group; perishable means produce, protein or dairy.
enum Shelf {
    static let perishableGroups: Set<FoodGroup> = [.produce, .protein, .dairy]

    static func isPerishable(_ food: Food) -> Bool {
        perishableGroups.contains(food.foodGroup)
    }

    /// Days a newly bought pack keeps; protein allows for some of it going into the freezer.
    static func boughtShelfLife(_ group: FoodGroup) -> ClosedRange<Int> {
        switch group {
        case .produce: 4...10
        case .protein: 4...8
        case .dairy: 7...14
        case .grains, .legumes, .fats, .other: 60...365
        }
    }

    /// Days left on an item already in the kitchen when the simulation starts.
    static func startingShelfLife(_ group: FoodGroup) -> ClosedRange<Int> {
        switch group {
        case .produce: 1...9
        case .protein: 1...5
        case .dairy: 3...14
        case .grains, .legumes, .fats, .other: 30...365
        }
    }

    /// Grams per pack; shops sell packs, so a purchase rounds up and the remainder is what the pantry must use up.
    static func packGrams(_ group: FoodGroup) -> Double {
        switch group {
        case .produce: 250
        case .protein: 400
        case .dairy: 500
        case .grains, .legumes: 500
        case .fats: 250
        case .other: 100
        }
    }

    static func startingGrams(_ group: FoodGroup) -> ClosedRange<Int> {
        switch group {
        case .produce: 150...600
        case .protein: 250...700
        case .dairy: 200...1000
        case .grains, .legumes, .fats: 200...1000
        case .other: 30...300
        }
    }
}

/// Builds `count` households from `seed`; household `i` depends only on `seed` and `i`.
enum HouseholdGenerator {
    static func generate(count: Int, seed: UInt64, catalogue: SeedCatalogue, start: Date, calendar: Calendar) -> [Household] {
        (0..<count).map { household(index: $0, seed: seed, catalogue: catalogue, start: start, calendar: calendar) }
    }

    static func household(index: Int, seed: UInt64, catalogue: SeedCatalogue, start: Date, calendar: Calendar) -> Household {
        var draws = Draws(seed: SeedMix.mix(seed, 0x484F_5553, UInt64(index)))
        let persona = draws.element(of: Persona.allCases)
        var kinds: [(ConstraintKind, ConstraintAxis)] = []
        var label = persona.rawValue
        var maxMinutes = draws.element(of: [40, 45, 60, 60, 90])
        switch persona {
        case .unrestricted: break
        case .nutAllergy: kinds.append((.allergen(.treeNut), .medical))
        case .coeliac: kinds.append((.medical(.coeliacDisease), .medical))
        case .vegan: kinds.append((.diet(.vegan), .ethical))
        case .allergen:
            let allergen = draws.element(of: Persona.allergens)
            kinds.append((.allergen(allergen), .medical))
            label = "allergen(\(allergen.rawValue))"
        case .hypertension: kinds.append((.medical(.hypertension), .medical))
        case .kidneyDisease: kinds.append((.medical(.chronicKidneyDisease), .medical))
        case .timePoor: maxMinutes = Persona.timePoorMinutes
        }
        // A fifth of households layer a second, compatible variant on top.
        if draws.chance(0.2) {
            let layer = draws.element(of: [Persona.hypertension, .timePoor])
            if layer != persona {
                if layer == .timePoor {
                    maxMinutes = Persona.timePoorMinutes
                } else {
                    kinds.append((.medical(.hypertension), .medical))
                }
                label += "+\(layer.rawValue)"
            }
        }

        let profile = UserProfile(
            birthYear: draws.integer(1950...2004),
            sex: draws.element(of: Sex.allCases),
            heightCm: draws.uniform(155, 192),
            weightKg: draws.uniform(50, 105),
            activityLevel: draws.element(of: ActivityLevel.allCases),
            goal: draws.element(of: Goal.allCases),
            householdSize: draws.weighted([(1, 0.25), (2, 0.35), (3, 0.15), (4, 0.2), (5, 0.05)]),
            currencyCode: "GBP",
            maxCookMinutes: maxMinutes
        )
        let constraints = kinds.enumerated().map { offset, entry in
            DietaryConstraint(
                id: DietaryConstraintID(rawValue: SeedCatalogue.uuid(for: "household/\(seed)/\(index)/constraint/\(offset)")),
                axis: entry.1,
                kind: entry.0,
                strictness: .hard,
                source: .user,
                lastConfirmed: start
            )
        }
        let targets = NutrientTargets.defaults(
            for: profile, constraints: constraints, referenceYear: calendar.component(.year, from: start)
        )
        let behaviour = Behaviour(
            skipProbability: draws.uniform(0.05, 0.25),
            tonightProbability: draws.uniform(0, 0.2),
            extraPurchaseProbability: draws.uniform(0.1, 0.6)
        )
        let compiled = ConstraintCompiler.compile(profile: profile, constraints: constraints, targets: targets)
        let pantry = startingPantry(
            draws: &draws, catalogue: catalogue, compiled: compiled, start: start, calendar: calendar,
            seed: seed, index: index
        )
        return Household(
            index: index, persona: persona, label: label, profile: profile, constraints: constraints,
            targets: targets, pantry: pantry, behaviour: behaviour
        )
    }

    /// Foods the household's admitted dinners use, garnish excluded, in file order.
    static func usableFoods(catalogue: SeedCatalogue, compiled: CompiledConstraints) -> [Food] {
        var used = Set<FoodID>()
        for candidate in catalogue.candidates where candidate.fits(.dinner) {
            guard case .admitted = compiled.admits(candidate, foods: catalogue.foods) else { continue }
            for line in candidate.ingredients where !line.isGarnish {
                if let foodID = line.foodID { used.insert(foodID) }
            }
        }
        return catalogue.foodList.filter { used.contains($0.id) }
    }

    /// Six to twelve perishables and five to ten staples, drawn from foods the household's admitted dinners use,
    /// so what is in the kitchen is something the household would plausibly cook with.
    private static func startingPantry(
        draws: inout Draws,
        catalogue: SeedCatalogue,
        compiled: CompiledConstraints,
        start: Date,
        calendar: Calendar,
        seed: UInt64,
        index: Int
    ) -> [PantryItem] {
        let usable = usableFoods(catalogue: catalogue, compiled: compiled)
        let perishables = draws.sample(usable.filter(Shelf.isPerishable), count: draws.integer(6...12))
        let staples = draws.sample(usable.filter { !Shelf.isPerishable($0) }, count: draws.integer(5...10))
        return (perishables + staples).enumerated().map { offset, food in
            let days = draws.integer(Shelf.startingShelfLife(food.foodGroup))
            return PantryItem(
                id: PantryItemID(rawValue: SeedCatalogue.uuid(for: "household/\(seed)/\(index)/pantry/\(offset)")),
                foodID: food.id,
                rawName: food.name,
                quantityGrams: Double(draws.integer(Shelf.startingGrams(food.foodGroup))),
                location: StorageLocation.usual(forItemNamed: food.name, food: food),
                bestBy: calendar.date(byAdding: .day, value: days, to: start),
                source: .manual,
                addedOn: start
            )
        }
    }
}
