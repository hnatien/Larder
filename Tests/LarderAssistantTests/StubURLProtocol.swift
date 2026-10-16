import Foundation
import Synchronization
import Testing

/// A request as the stub saw it.
struct RecordedRequest: Sendable {
    var path: String
    var method: String
    var headers: [String: String]
    var body: Data
    var timeout: TimeInterval

    func json() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: body)
        return try #require(object as? [String: Any])
    }

    var bodyText: String { String(decoding: body, as: UTF8.self) }
}

/// Scripted replies for one test, keyed by a unique host so parallel tests never share state.
final class Stub: Sendable {
    enum Reply: Sendable {
        case json(Int, String)
        case failure(URLError)
    }

    let host = "\(UUID().uuidString.lowercased()).larder.test"
    private let state = Mutex<(requests: [RecordedRequest], replies: [String: [Reply]])>(([], [:]))

    init() {
        StubURLProtocol.register(self)
    }

    var baseURL: URL {
        URL(string: "https://\(host)") ?? URL(fileURLWithPath: "/")
    }

    var requests: [RecordedRequest] { state.withLock { $0.requests } }

    func requests(to path: String) -> [RecordedRequest] { requests.filter { $0.path == path } }

    /// Queues replies for `path`; the last one repeats.
    func on(_ path: String, _ replies: Reply...) {
        state.withLock { $0.replies[path] = replies }
    }

    func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    fileprivate func handle(_ request: RecordedRequest) -> Reply {
        state.withLock { state in
            state.requests.append(request)
            guard var queue = state.replies[request.path], let reply = queue.first else {
                return .failure(URLError(.resourceUnavailable))
            }
            if queue.count > 1 {
                queue.removeFirst()
                state.replies[request.path] = queue
            }
            return reply
        }
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let registry = Mutex<[String: Stub]>([:])

    static func register(_ stub: Stub) {
        registry.withLock { $0[stub.host] = stub }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host(), let stub = Self.registry.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let recorded = RecordedRequest(
            path: url.path(),
            method: request.httpMethod ?? "",
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? Self.read(request.httpBodyStream),
            timeout: request.timeoutInterval
        )
        switch stub.handle(recorded) {
        case .json(let status, let body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])
            if let response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
