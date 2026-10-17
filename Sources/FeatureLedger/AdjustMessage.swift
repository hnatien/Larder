import Foundation
import LarderCore

/// One message of the "Adjust this week" chat: the person's request, or what the assistant or Larder said back.
public nonisolated struct AdjustMessage: Identifiable, Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        /// What the person asked for.
        case request(String)
        /// The assistant's question back, when the request was unclear or asked for something it cannot change here.
        case question(String)
        /// Changes the assistant proposed, and what became of them.
        case proposal(WeekAdjustment, ProposalState)
        /// AI help is off; the person can allow it right here.
        case needsConsent
        /// Why asking or applying failed; `canRetry` when asking the same again may work.
        case failure(LarderError, canRetry: Bool)
        /// The week was replanned with the applied changes; days whose own change nothing could meet kept their dinner.
        case replanned(unmetDays: [Date])
    }

    /// What became of a proposal.
    public enum ProposalState: Hashable, Sendable {
        /// Waiting for Apply and replan or Not now.
        case pending
        case applied
        case dismissed
        /// Carried into the proposal after it, which the person answered with a further request.
        case superseded
    }

    public let id: UUID
    public internal(set) var content: Content

    init(_ content: Content, id: UUID = UUID()) {
        self.id = id
        self.content = content
    }

    /// Whether the person wrote this message.
    public var isRequest: Bool {
        if case .request = content { true } else { false }
    }
}
