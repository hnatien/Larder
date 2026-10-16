import Foundation
import LarderCore

/// The only profile facts that may reach the proxy: derived, non-identifying and never sensitive.
public struct ProfileSummary: Hashable, Codable, Sendable {
    public var goal: Goal
    public var householdSize: Int
    public var maxCookMinutes: Int
    public var showsNumbers: Bool

    /// Builds a summary from the full profile. No constraint is copied, so medical and religious axes can never leak through it.
    public static func make(profile: UserProfile, constraints: [DietaryConstraint]) -> ProfileSummary {
        ProfileSummary(
            goal: profile.goal,
            householdSize: min(max(profile.householdSize, 1), 12),
            maxCookMinutes: min(max(profile.maxCookMinutes, 5), 480),
            showsNumbers: profile.showsNumbers
        )
    }
}
