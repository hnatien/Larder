import Foundation
import LarderCore

/// A failure talking to the Larder proxy.
public enum ProxyError: Error, Hashable, Sendable {
    /// The proxy answered with a non-success status and, when present, its `error` code and refusal `category`.
    case http(status: Int, code: String?, category: String? = nil)
    /// A request body could not be encoded or a response body could not be decoded.
    case decoding
    /// The request did not complete.
    case transport(URLError)
    /// No session token could be obtained because no attestation is configured.
    case noSession
    /// The device could not attest or assert its App Attest key.
    case attestation(AppAttestError)

    /// The shared error the UI acts on.
    public func toLarderError() -> LarderError {
        switch self {
        case .http(400, _, _):
            .invalidResponse
        case .http(402, _, _):
            .plusRequired
        case .http(422, "declined", let category):
            .declined(category: category)
        case .http(422, _, _):
            .invalidResponse
        case .http(429, "quota_exceeded", _):
            .quotaExceeded
        case .http(let status, _, _) where status == 401 || status == 403 || status == 429 || status >= 500:
            .assistantUnavailable
        case .http:
            .invalidResponse
        case .decoding:
            .invalidResponse
        case .transport, .noSession, .attestation:
            .assistantUnavailable
        }
    }
}
