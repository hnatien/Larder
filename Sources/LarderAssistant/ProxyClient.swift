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
        guard let clientSecret = await configuration.clientSecretProvider() else {
            return .failure(.noSession)
        }
        do throws(ProxyError) {
            let body = SessionRequestBody(attestation: .init(kind: "dev", clientSecret: clientSecret))
            let payload: Data
            do {
                payload = try encoder.encode(body)
            } catch {
                throw .decoding
            }
            var request = URLRequest(url: configuration.baseURL.appending(path: "v1/session"))
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload
            let (data, status) = try await perform(request)
            guard (200..<300).contains(status) else {
                throw Self.httpError(status: status, data: data)
            }
            guard
                let response = try? JSONDecoder().decode(SessionResponseBody.self, from: data),
                let expiresAt = Self.parseTimestamp(response.expiresAt)
            else {
                throw .decoding
            }
            let token = SessionToken(value: response.token, expiresAt: expiresAt)
            cachedToken = token
            return .success(token)
        } catch {
            return .failure(error)
        }
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
