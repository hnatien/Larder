import Foundation

/// A fact about a food that diet, religious and medical rules filter on.
public enum FoodTag: String, CaseIterable, Hashable, Codable, Sendable {
    case meat
    case pork
    case beef
    case poultry
    case fish
    case shellfish
    case egg
    case dairy
    case honey
    case alcohol
    case glutenGrain
    case rawFish
    case unpasteurised
    case highSodium
    case addedSugarSource

    var readableName: String {
        switch self {
        case .meat: "meat"
        case .pork: "pork"
        case .beef: "beef"
        case .poultry: "poultry"
        case .fish: "fish"
        case .shellfish: "shellfish"
        case .egg: "egg"
        case .dairy: "dairy"
        case .honey: "honey"
        case .alcohol: "alcohol"
        case .glutenGrain: "gluten grain"
        case .rawFish: "raw fish"
        case .unpasteurised: "unpasteurised food"
        case .highSodium: "high sodium"
        case .addedSugarSource: "added sugar"
        }
    }
}
