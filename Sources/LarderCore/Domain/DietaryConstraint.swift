import Foundation

/// A rule the planner must (hard) or should (soft) respect.
public struct DietaryConstraint: Identifiable, Hashable, Codable, Sendable {
    public var id: DietaryConstraintID
    public var axis: ConstraintAxis
    public var kind: ConstraintKind
    public var strictness: Strictness
    public var source: ConstraintSource
    public var lastConfirmed: Date

    /// Creates a constraint.
    public init(
        id: DietaryConstraintID = DietaryConstraintID(),
        axis: ConstraintAxis,
        kind: ConstraintKind,
        strictness: Strictness,
        source: ConstraintSource,
        lastConfirmed: Date
    ) {
        self.id = id
        self.axis = axis
        self.kind = kind
        self.strictness = strictness
        self.source = source
        self.lastConfirmed = lastConfirmed
    }
}

/// Why a constraint exists. Medical and religious constraints are sensitive and stay on device.
public enum ConstraintAxis: String, CaseIterable, Hashable, Codable, Sendable {
    case medical
    case religious
    case ethical
    case preference
    case goal
}

/// What a constraint restricts.
public enum ConstraintKind: Hashable, Codable, Sendable {
    case allergen(Allergen)
    case intolerance(String)
    case diet(DietPattern)
    case medical(MedicalFlag)
    case dislike(DislikeTarget)
    case religious(ReligiousRule)
}

/// A disliked food, matched by identifier when known and by name otherwise.
public enum DislikeTarget: Hashable, Codable, Sendable {
    case food(FoodID)
    case name(String)
}

/// Whether a constraint filters (hard) or only weights (soft).
public enum Strictness: String, CaseIterable, Hashable, Codable, Sendable {
    case hard
    case soft
}

/// Who set a constraint.
public enum ConstraintSource: String, CaseIterable, Hashable, Codable, Sendable {
    case user
    case clinician
    case derived
}

/// An eating pattern a user follows or a recipe satisfies.
public enum DietPattern: String, CaseIterable, Hashable, Codable, Sendable {
    case vegetarian
    case vegan
    case pescatarian
    case mediterranean
    case dash
}

/// A health condition that changes planning rules. Never leaves the device.
public enum MedicalFlag: String, CaseIterable, Hashable, Codable, Sendable {
    case coeliacDisease
    case hypertension
    case type1Diabetes
    case type2Diabetes
    case chronicKidneyDisease
    case pregnancy
    case eatingDisorderHistory
}

/// A religious food rule. Never leaves the device.
public enum ReligiousRule: String, CaseIterable, Hashable, Codable, Sendable {
    case halal
    case kosher
    case noPork
    case noBeef
    case noAlcohol
    case jain
}
