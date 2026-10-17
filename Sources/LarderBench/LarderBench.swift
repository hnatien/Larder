import Foundation

/// Offline evaluation of the Larder planner against baselines over synthetic households (docs/EVALUATION.md).
@main
struct LarderBench {
    struct Options {
        var seed: UInt64 = 42
        var households = 100
        var weeks = 4
        var outputDirectory = URL(fileURLWithPath: "bench-results")
        var dataDirectory = SeedCatalogue.defaultDirectory
        var llmPlans: URL?
        var exportHouseholds: URL?
    }

    enum UsageError: Error, CustomStringConvertible {
        case message(String)

        var description: String {
            switch self {
            case .message(let text): text + "\n\n" + LarderBench.usage
            }
        }
    }

    static let usage = """
        USAGE: LarderBench [--seed <n>] [--households <n>] [--weeks <n>] [--out <dir>] [--data <dir>]
                           [--llm-plans <file.json>] [--export-households <file.json>]

          --seed               Base seed for households, plans and behaviour (default 42)
          --households         Synthetic households, 1...10000 (default 100)
          --weeks              Rolling weeks per household, 1...52 (default 4)
          --out                Directory for the run's CSV (default ./bench-results)
          --data               Directory holding seed-foods.json and seed-recipes.json
          --llm-plans          Score plans produced elsewhere as an extra "llm" arm (format in Arms.swift)
          --export-households  Write the generated households (profile, constraints, pantry) as JSON
        """

    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("LarderBench: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run(arguments: [String]) async throws {
        if arguments.contains("--help") || arguments.contains("-h") {
            print(usage)
            return
        }
        let options = try parse(arguments)
        let clock = ContinuousClock()
        let started = clock.now

        let catalogue = try SeedCatalogue.load(from: options.dataDirectory)
        let simulation = Simulation(catalogue: catalogue, seed: options.seed, weeks: options.weeks)
        let households = HouseholdGenerator.generate(
            count: options.households, seed: options.seed, catalogue: catalogue,
            start: simulation.startDate, calendar: simulation.calendar
        )
        if let url = options.exportHouseholds {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(households).write(to: url)
        }
        var arms: [any Arm] = [PlannerArm(), GreedyArm(), NoPantryArm(), RandomArm()]
        if let url = options.llmPlans {
            arms.append(try FileArm.load(from: url, catalogue: catalogue))
        }

        let runs = await evaluate(households, arms: arms, simulation: simulation)
        let elapsed = (clock.now - started) / .seconds(1)

        try FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)
        let csvURL = options.outputDirectory.appending(
            path: "larder-bench-seed\(options.seed)-h\(options.households)-w\(options.weeks).csv"
        )
        try Report.csv(runs).write(to: csvURL, atomically: true, encoding: .utf8)

        print("## LarderBench: seed \(options.seed), \(options.households) households, \(options.weeks) weeks\n")
        print("Seed data: \(catalogue.candidates.count) recipes, \(catalogue.foods.count) foods. Dinners only, 7-day weeks.")
        print("Wall time \(String(format: "%.1f", elapsed)) s. Per-household rows: \(csvURL.path)\n")
        print(Report.markdown(runs, arms: arms.map(\.name)), terminator: "")
    }

    /// Every household under every arm, households in parallel; results in household then arm order.
    static func evaluate(_ households: [Household], arms: [any Arm], simulation: Simulation) async -> [HouseholdRun] {
        await withTaskGroup(of: (Int, [HouseholdRun]).self) { group in
            for household in households {
                group.addTask {
                    (household.index, arms.map { simulation.run(household, arm: $0) })
                }
            }
            var byHousehold: [Int: [HouseholdRun]] = [:]
            for await (index, runs) in group {
                byHousehold[index] = runs
            }
            return byHousehold.keys.sorted().flatMap { byHousehold[$0] ?? [] }
        }
    }

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var iterator = arguments.makeIterator()
        while let flag = iterator.next() {
            guard let value = iterator.next() else { throw UsageError.message("\(flag) needs a value") }
            switch flag {
            case "--seed":
                guard let seed = UInt64(value) else { throw UsageError.message("--seed must be a non-negative integer") }
                options.seed = seed
            case "--households":
                options.households = try integer(value, flag: flag, in: 1...10_000)
            case "--weeks":
                options.weeks = try integer(value, flag: flag, in: 1...52)
            case "--out":
                options.outputDirectory = URL(fileURLWithPath: value)
            case "--data":
                options.dataDirectory = URL(fileURLWithPath: value)
            case "--llm-plans":
                options.llmPlans = URL(fileURLWithPath: value)
            case "--export-households":
                options.exportHouseholds = URL(fileURLWithPath: value)
            default:
                throw UsageError.message("Unknown option \(flag)")
            }
        }
        return options
    }

    private static func integer(_ value: String, flag: String, in range: ClosedRange<Int>) throws -> Int {
        guard let number = Int(value), range.contains(number) else {
            throw UsageError.message("\(flag) must be an integer in \(range.lowerBound)...\(range.upperBound)")
        }
        return number
    }
}
