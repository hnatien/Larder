import Foundation

/// Errors shared across modules.
public enum LarderError: Error, Hashable, Sendable {
    /// The requested record does not exist.
    case notFound
    /// The local store failed to read or write.
    case storageFailure
    /// The user has not consented to cloud AI processing.
    case consentRequired
    /// No assistant backend can be reached right now.
    case assistantUnavailable
    /// The user's assistant allowance for this period is used up.
    case quotaExceeded
    /// The assistant answered with something that failed validation.
    case invalidResponse
    /// The feature needs an active Larder Plus subscription.
    case plusRequired
    /// The model declined the request; `category` is the refusal category when the proxy reports one.
    case declined(category: String?)
}
