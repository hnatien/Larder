import Foundation

/// Allergens covering the US major nine and the EU fourteen (Regulation 1169/2011).
public enum Allergen: String, CaseIterable, Hashable, Codable, CodingKeyRepresentable, Sendable {
    case milk
    case egg
    case fish
    case crustacean
    case mollusc
    case treeNut
    case peanut
    case wheat
    case gluten
    case soy
    case sesame
    case celery
    case mustard
    case lupin
    case sulphites
}

/// What is known about one allergen in a food.
public enum AllergenPresence: String, Hashable, Codable, Sendable {
    case contains
    case mayContain
    /// No data. Never treat as safe.
    case unknown
    case verifiedFree
}

/// Per-allergen presence for a food; allergens without an entry are `.unknown`.
public struct AllergenTags: Hashable, Codable, Sendable {
    public var entries: [Allergen: AllergenPresence]

    /// Creates tags from explicit per-allergen presence.
    public init(_ entries: [Allergen: AllergenPresence] = [:]) {
        self.entries = entries
    }

    /// The recorded presence of `allergen`, or `.unknown` when nothing is recorded.
    public func presence(of allergen: Allergen) -> AllergenPresence {
        entries[allergen] ?? .unknown
    }
}
