// swift-tools-version: 6.2
import PackageDescription

let uiSettings: [SwiftSetting] = [.defaultIsolation(MainActor.self)]
let featureDependencies: [Target.Dependency] = [
    "LarderCore", "LarderDesign", "LarderPersistence", "LarderAssistant",
]
let featureNames = ["FeatureShelves", "FeatureLedger", "FeatureRecipes", "FeatureGrocery", "FeatureAccount"]

let sourceTargets: [Target] = [
    .target(name: "LarderCore"),
    .target(
        name: "LarderPersistence",
        dependencies: ["LarderCore", .product(name: "GRDB", package: "GRDB.swift")]
    ),
    .target(name: "LarderAssistant", dependencies: ["LarderCore"]),
    .target(name: "LarderOnDeviceAI", dependencies: ["LarderCore", "LarderAssistant"], swiftSettings: uiSettings),
    .target(
        name: "LarderDesign",
        dependencies: ["LarderCore"],
        resources: [.process("Resources")],
        swiftSettings: uiSettings
    ),
] + featureNames.map { .target(name: $0, dependencies: featureDependencies, swiftSettings: uiSettings) }

let testResources: [String: [Resource]] = [
    "LarderPersistenceTests": [.copy("Fixtures")],
    "FeatureRecipesTests": [.copy("Fixtures")],
]

let testTargets: [Target] = sourceTargets.map {
    .testTarget(
        name: "\($0.name)Tests",
        dependencies: [.target(name: $0.name)],
        resources: testResources["\($0.name)Tests"]
    )
}

/// The offline evaluation harness: macOS only, Core only, never shipped in the app.
let benchTargets: [Target] = [
    .executableTarget(name: "LarderBench", dependencies: ["LarderCore"]),
]

let package = Package(
    name: "LarderKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: sourceTargets.map { .library(name: $0.name, targets: [$0.name]) },
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.0")
    ],
    targets: sourceTargets + testTargets + benchTargets
)
