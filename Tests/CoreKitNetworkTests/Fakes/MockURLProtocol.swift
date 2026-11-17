import Foundation
import os

// MARK: - MockURLProtocol

typealias MockURLHandler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

/// `@unchecked`: `URLProtocol` is a non-Sendable Foundation class and the loading system creates and
/// calls instances on its own threads. This subclass adds no stored state of its own: the handlers
/// live in a lock-protected `static let`.
final class MockURLProtocol: URLProtocol, @unchecked Sendable { // swiftlint:disable:this unchecked_sendable_needs_reason

    /// Per-session handlers keyed by session configuration identifier.
    private static let handlers = OSAllocatedUnfairLock<[String: MockURLHandler]>(initialState: [:])

    static func setHandler(for sessionId: String, handler: @escaping MockURLHandler) {
        handlers.withLock { $0[sessionId] = handler }
    }

    static func removeHandler(for sessionId: String) {
        _ = handlers.withLock { $0.removeValue(forKey: sessionId) }
    }

    private static func handler(for sessionId: String?) -> MockURLHandler? {
        guard let sessionId else { return nil }
        return handlers.withLock { $0[sessionId] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let sessionId = request.value(forHTTPHeaderField: "X-Mock-Session-Id")
        guard let handler = MockURLProtocol.handler(for: sessionId) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - MockSession

/// Encapsulates a URLSession backed by MockURLProtocol with an isolated handler.
/// Each test creates its own MockSession to avoid race conditions between parallel suites.
final class MockSession: Sendable {

    let session: URLSession
    let id: String

    init() {
        self.id = UUID().uuidString
        self.session = URLSession(configuration: Self.configuration(id: id))
    }

    /// The configuration behind `session`, for a service that builds its own session from one.
    var configuration: URLSessionConfiguration {
        Self.configuration(id: id)
    }

    private static func configuration(id: String) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Mock-Session-Id": id]
        return config
    }

    deinit {
        MockURLProtocol.removeHandler(for: id)
    }

    var handler: MockURLHandler? {
        get { nil } // write-only for clarity
        set {
            if let newValue {
                MockURLProtocol.setHandler(for: id, handler: newValue)
            } else {
                MockURLProtocol.removeHandler(for: id)
            }
        }
    }
}
