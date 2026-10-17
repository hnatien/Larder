import Foundation

/// Offline evaluation of the Larder planner against baselines over synthetic households (docs/EVALUATION.md).
@main
struct LarderBench {
    struct Options {
        var seed: UInt64 = 42
        var seeds = 1
        var households = 100
        var weeks = 4
        var outputDirectory = URL(fileURLWithPath: "bench-results")
        var dataDirectory = SeedCatalogue.defaultDirectory
        var llmPlans: URL?
        var exportHouseholds: URL?
        var checkBaseline: URL?
        var writeBaseline: URL?

        /// Seeds `seed`, `seed + 1`, … in run order.
        var seedList: [UInt64] {
            (0..<seeds).map { seed &+ UInt64($0) }
        }

        var baselineConfiguration: Baseline.Configuration {
            Baseline.Configuration(seed: seed, seeds: seeds, households: households, weeks: weeks)
        }
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
        USAGE: LarderBench [--seed <n>] [--seeds <n>] [--households <n>] [--weeks <n>] [--out <dir>] [--data <dir>]
                           [--llm-plans <file.json>] [--export-households <file.json>]
                           [--check-baseline <file.json>] [--write-baseline <file.json>]

          --seed               Base seed for households, plans and behaviour (default 42)
          --seeds              Run seeds seed, seed+1, … each with its own households, 1...100 (default 1)
          --households         Synthetic households, 1...10000 (default 100)
          --weeks              Rolling weeks per household, 1...52 (default 4)
          --out                Directory for the run's CSV (default ./bench-results)
          --data               Directory holding seed-foods.json and seed-recipes.json
          --llm-plans          Score plans produced elsewhere as an extra "llm" arm (format in Arms.swift)
          --export-households  Write the generated households (profile, constraints, pantry) as JSON
          --check-baseline     Fail (exit 1) when the planner regresses against this baseline (Baseline.swift)
          --write-baseline     Write this run's planner figures as a new baseline
        """

    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            // The report is on buffered stdout; flush it so the error reads after it, not before.
            fflush(stdout)
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
        let baseline = try options.checkBaseline.map(Baseline.load)
        // Refuse a mismatched baseline before spending the run on it.
        try baseline?.require(options.baselineConfiguration)
        var arms: [any Arm] = [PlannerArm(), GreedyArm(), NoPantryArm(), RandomArm()]
        if let url = options.llmPlans {
            arms.append(try FileArm.load(from: url, catalogue: catalogue))
        }

        var runs: [HouseholdRun] = []
        for seed in options.seedList {
            let simulation = Simulation(catalogue: catalogue, seed: seed, weeks: options.weeks)
            let households = HouseholdGenerator.generate(
                count: options.households, seed: seed, catalogue: catalogue,
                start: simulation.startDate, calendar: simulation.calendar
            )
            if let url = options.exportHouseholds {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(households).write(to: url)
            }
            runs += await evaluate(households, arms: arms, simulation: simulation)
        }
        let elapsed = (clock.now - started) / .seconds(1)

        try FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)
        let seeds = options.seeds > 1 ? "\(options.seed)x\(options.seeds)" : "\(options.seed)"
        let csvURL = options.outputDirectory.appending(
            path: "larder-bench-seed\(seeds)-h\(options.households)-w\(options.weeks).csv"
        )
        try Report.csv(runs).write(to: csvURL, atomically: true, encoding: .utf8)

        let seedText = options.seeds > 1 ? "seeds \(options.seed)…\(options.seedList.last ?? options.seed)" : "seed \(options.seed)"
        print("## LarderBench: \(seedText), \(options.households) households, \(options.weeks) weeks\n")
        print("Seed data: \(catalogue.candidates.count) recipes, \(catalogue.foods.count) foods. Dinners only, 7-day weeks.")
        print("Wall time \(String(format: "%.1f", elapsed)) s. Per-household rows: \(csvURL.path)\n")
        print(Report.markdown(runs, arms: arms.map(\.name)))
        print("Paired by household over \(options.seeds * options.households) households (bootstrap over households within each seed):\n")
        print(Report.paired(runs, arm: Baseline.arm, against: arms.map(\.name).filter { $0 != Baseline.arm }), terminator: "")

        if let url = options.writeBaseline {
            try Baseline(runs: runs, configuration: options.baselineConfiguration).write(to: url)
            print("\nWrote the baseline to \(url.path)")
        }
        if let baseline {
            print("\n" + (try baseline.markdown(runs, configuration: options.baselineConfiguration)), terminator: "")
            let failures = try baseline.failures(runs, configuration: options.baselineConfiguration)
            guard failures.isEmpty else { throw Baseline.Failure.regressed(failures) }
            print("\nRegression gate passed.")
        }
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
            case "--seeds":
                options.seeds = try integer(value, flag: flag, in: 1...100)
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
            case "--check-baseline":
                options.checkBaseline = URL(fileURLWithPath: value)
            case "--write-baseline":
                options.writeBaseline = URL(fileURLWithPath: value)
            default:
                throw UsageError.message("Unknown option \(flag)")
            }
        }
        // Both files are keyed by household index alone, which repeats across seeds.
        if options.seeds > 1, options.llmPlans != nil || options.exportHouseholds != nil {
            throw UsageError.message("--llm-plans and --export-households take a single seed")
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
