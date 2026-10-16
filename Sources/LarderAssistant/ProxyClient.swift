import CryptoKit
import Foundation
import LarderCore

/// Talks to the Larder proxy: obtains and caches a session token, then posts assist requests.
public actor ProxyClient {
    private let configuration: ProxyConfiguration
    private let urlSession: URLSession
    private let dateProvider: any DateProvider
    private let encoder: JSONEncoder
    private var cachedToken: SessionToken?
    private var pendingSession: Task<Result<SessionToken, ProxyError>, Never>?

    /// Creates a client; inject a `URLSession` configured with a stub protocol in tests.
    public init(configuration: ProxyConfiguration, urlSession: URLSession, dateProvider: any DateProvider) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.dateProvider = dateProvider
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    /// Returns a bearer token, reusing the cached one until 60 seconds before it expires.
    public func session() async throws(ProxyError) -> String {
        if let cachedToken, cachedToken.isUsable(at: dateProvider.now) {
            return cachedToken.value
        }
        let task: Task<Result<SessionToken, ProxyError>, Never>
        if let pendingSession {
            task = pendingSession
        } else {
            task = Task { await self.requestSession() }
            pendingSession = task
        }
        return try await task.value.get().value
    }

    func send<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ body: Body,
        to route: AssistantRoute,
        as response: Response.Type
    ) async throws(ProxyError) -> Response {
        let payload: Data
        do {
            payload = try encoder.encode(body)
        } catch {
            throw .decoding
        }
        var token = try await session()
        var (data, status) = try await post(payload, to: route, token: token)
        if status == 401 {
            if cachedToken?.value == token {
                cachedToken = nil
            }
            token = try await session()
            (data, status) = try await post(payload, to: route, token: token)
        }
        guard (200..<300).contains(status) else {
            throw Self.httpError(status: status, data: data)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw .decoding
        }
    }

    private func requestSession() async -> Result<SessionToken, ProxyError> {
        defer { pendingSession = nil }
        do throws(ProxyError) {
            let token: SessionToken
            if let appAttest = configuration.appAttest, appAttest.attester.isSupported {
                token = try await appAttestSession(appAttest)
            } else if let clientSecret = await configuration.clientSecretProvider() {
                token = try await postSession(.dev(clientSecret: clientSecret))
            } else {
                throw .noSession
            }
            cachedToken = token
            return .success(token)
        } catch {
            return .failure(error)
        }
    }

    /// Asserts with the stored key. Attests a new key when none is stored, or when the device or the
    /// proxy no longer knows the stored one; the key id is saved only once the proxy has accepted it.
    private func appAttestSession(_ appAttest: AppAttestConfiguration) async throws(ProxyError) -> SessionToken {
        if let keyID = appAttest.keyStore.load() {
            do throws(ProxyError) {
                let challenge = try await fetchChallenge()
                let assertion: Data
                do throws(AppAttestError) {
                    assertion = try await appAttest.attester.generateAssertion(keyID, clientDataHash: Self.clientDataHash(challenge))
                } catch {
                    throw .attestation(error)
                }
                return try await postSession(.appAssert(keyID: keyID, assertion: assertion, challenge: challenge))
            } catch .attestation(.invalidKey), .http(401, "unknown_key", _) {
                appAttest.keyStore.save(nil)
            }
        }
        let keyID: String
        let attestation: Data
        let challenge = try await fetchChallenge()
        do throws(AppAttestError) {
            keyID = try await appAttest.attester.generateKey()
            attestation = try await appAttest.attester.attestKey(keyID, clientDataHash: Self.clientDataHash(challenge))
        } catch {
            throw .attestation(error)
        }
        let token = try await postSession(.appAttest(keyID: keyID, attestationObject: attestation, challenge: challenge))
        appAttest.keyStore.save(keyID)
        return token
    }

    private func fetchChallenge() async throws(ProxyError) -> String {
        let (data, status) = try await perform(sessionRequest(path: "v1/challenge", body: Data("{}".utf8)))
        guard (200..<300).contains(status) else {
            throw Self.httpError(status: status, data: data)
        }
        guard let response = try? JSONDecoder().decode(ChallengeResponseBody.self, from: data) else {
            throw .decoding
        }
        return response.challenge
    }

    private func postSession(_ attestation: SessionRequestBody.Attestation) async throws(ProxyError) -> SessionToken {
        let payload: Data
        do {
            payload = try encoder.encode(SessionRequestBody(attestation: attestation))
        } catch {
            throw .decoding
        }
        let (data, status) = try await perform(sessionRequest(path: "v1/session", body: payload))
        guard (200..<300).contains(status) else {
            throw Self.httpError(status: status, data: data)
        }
        guard
            let response = try? JSONDecoder().decode(SessionResponseBody.self, from: data),
            let expiresAt = Self.parseTimestamp(response.expiresAt)
        else {
            throw .decoding
        }
        return SessionToken(value: response.token, expiresAt: expiresAt)
    }

    private func sessionRequest(path: String, body: Data) -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    /// Apple's `clientDataHash`: SHA-256 of the challenge's UTF-8 bytes, as the proxy recomputes it.
    static func clientDataHash(_ challenge: String) -> Data {
        Data(SHA256.hash(data: Data(challenge.utf8)))
    }

    private func post(_ payload: Data, to route: AssistantRoute, token: String) async throws(ProxyError) -> (Data, Int) {
        var request = URLRequest(url: configuration.baseURL.appending(path: route.path))
        request.httpMethod = "POST"
        request.timeoutInterval = route.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let entitlement = await configuration.entitlementProvider() {
            request.setValue(entitlement, forHTTPHeaderField: "x-larder-entitlement")
        }
        request.httpBody = payload
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws(ProxyError) -> (Data, Int) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let error as URLError {
            throw .transport(error)
        } catch {
            throw .transport(URLError(.unknown))
        }
        guard let http = response as? HTTPURLResponse else {
            throw .transport(URLError(.badServerResponse))
        }
        return (data, http.statusCode)
    }

    private static func httpError(status: Int, data: Data) -> ProxyError {
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        return .http(status: status, code: body?.error, category: body?.category)
    }

    private static func parseTimestamp(_ text: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? withFraction.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
    }
}

private struct SessionToken: Sendable {
    let value: String
    let expiresAt: Date

    func isUsable(at now: Date) -> Bool {
        now < expiresAt.addingTimeInterval(-60)
    }
}

extension AssistantRoute {
    var path: String {
        switch self {
        case .explain: "v1/assist/explain"
        case .parsePantry: "v1/assist/parse-pantry"
        case .parseRecipe: "v1/assist/parse-recipe"
        case .adjust: "v1/assist/adjust"
        }
    }

    var timeout: TimeInterval {
        switch self {
        case .parsePantry, .parseRecipe: 20
        case .explain, .adjust: 45
        }
    }
}
