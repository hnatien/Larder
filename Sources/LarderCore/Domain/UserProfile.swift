import Foundation

/// The local-only profile that planning and targets are computed from.
public struct UserProfile: Hashable, Codable, Sendable {
    public var birthYear: Int
    public var sex: Sex
    public var heightCm: Double
    public var weightKg: Double?
    public var activityLevel: ActivityLevel
    public var goal: Goal
    public var householdSize: Int
    public var weeklyBudget: Decimal?
    /// ISO 4217 currency code for `weeklyBudget`.
    public var currencyCode: String
    public var maxCookMinutes: Int
    public var equipment: Set<Equipment>
    /// Whether nutrient numbers are shown; off by default.
    public var showsNumbers: Bool
    public var consents: Consents

    /// Creates a profile.
    public init(
        birthYear: Int,
        sex: Sex = .unspecified,
        heightCm: Double,
        weightKg: Double? = nil,
        activityLevel: ActivityLevel,
        goal: Goal,
        householdSize: Int,
        weeklyBudget: Decimal? = nil,
        currencyCode: String,
        maxCookMinutes: Int,
        equipment: Set<Equipment> = [],
        showsNumbers: Bool = false,
        consents: Consents = Consents()
    ) {
        self.birthYear = birthYear
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activityLevel = activityLevel
        self.goal = goal
        self.householdSize = householdSize
        self.weeklyBudget = weeklyBudget
        self.currencyCode = currencyCode
        self.maxCookMinutes = maxCookMinutes
        self.equipment = equipment
        self.showsNumbers = showsNumbers
        self.consents = consents
    }
}

/// Sex used for reference intakes; `.unspecified` falls back to sex-neutral values.
public enum Sex: String, CaseIterable, Hashable, Codable, Sendable {
    case female
    case male
    case unspecified
}

/// Habitual physical activity.
public enum ActivityLevel: String, CaseIterable, Hashable, Codable, Sendable {
    case sedentary
    case light
    case moderate
    case active
    case veryActive
}

/// What the user wants planning to optimise for.
public enum Goal: String, CaseIterable, Hashable, Codable, Sendable {
    case eatBetter
    case moreVariety
    case lessWaste
    case saveMoney
    case moreProtein
    case maintain
}

/// Explicit user consents; everything is off until granted.
public struct Consents: Hashable, Codable, Sendable {
    public var aiProcessing: Bool
    public var cloudSync: Bool

    /// Creates consents.
    public init(aiProcessing: Bool = false, cloudSync: Bool = false) {
        self.aiProcessing = aiProcessing
        self.cloudSync = cloudSync
    }
}
