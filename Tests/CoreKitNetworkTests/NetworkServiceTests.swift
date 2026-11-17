import Testing
import Foundation
import os
@testable import CoreKitNetwork

private struct TestUser: Codable, Sendable {
    let name: String
}

@Suite("NetworkService")
struct NetworkServiceTests {

    private let baseURL = URL(string: "https://api.example.com")!

    private func makeService(
        mock: MockSession,
        retryPolicy: RetryPolicy = .none,
        monitor: NetworkMonitoring? = nil
    ) -> NetworkService {
        let client = NetworkClient(session: mock.session)
        return NetworkService(
            baseURL: baseURL,
            client: client,
            retryPolicy: retryPolicy,
            monitor: monitor
        )
    }

    private func makeServiceWithReachability(
        mock: MockSession,
        monitor: MockNetworkMonitor
    ) -> NetworkService {
        let interceptor = ReachabilityInterceptor(monitor: monitor)
        let client = NetworkClient(session: mock.session, interceptors: [interceptor])
        return NetworkService(
            baseURL: baseURL,
            client: client,
            retryPolicy: .none,
            monitor: monitor
        )
    }

    // MARK: - request with responseType

    @Test("request returns decoded body on success")
    func requestReturnsDecodedBody() async throws {
        let mock = MockSession()
        mock.handler = { _ in
            let json = Data(#"{"name":"Alice"}"#.utf8)
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/users/1")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let service = makeService(mock: mock)

        let user: TestUser = try await service.request(
            path: "v1/users/1",
            responseType: TestUser.self
        )

        #expect(user.name == "Alice")
    }

    @Test("request throws on server error")
    func requestThrowsOnServerError() async {
        let mock = MockSession()
        mock.handler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/users")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = makeService(mock: mock)

        await #expect(throws: NetworkResponseError.self) {
            try await service.request(
                path: "v1/users",
                responseType: EmptyResponse.self
            )
        }
    }

    // MARK: - request without responseType (EmptyResponse)

    @Test("request without responseType succeeds on 200")
    func requestWithoutResponseTypeSucceeds() async throws {
        let mock = MockSession()
        mock.handler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/action")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = makeService(mock: mock)

        try await service.request(path: "v1/action", method: .post)
    }

    @Test("request without responseType throws on error status")
    func requestWithoutResponseTypeThrows() async {
        let mock = MockSession()
        mock.handler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/action")!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = makeService(mock: mock)

        await #expect(throws: NetworkResponseError.self) {
            try await service.request(path: "v1/action", method: .delete)
        }
    }

    // MARK: - requestWithResponse

    @Test("requestWithResponse returns full NetworkResponse")
    func requestWithResponseReturnsFullResponse() async throws {
        let mock = MockSession()
        mock.handler = { _ in
            let json = Data(#"{"name":"Bob"}"#.utf8)
            let response = HTTPURLResponse(
                url: URL(string: "https://api.example.com/v1/users/2")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["X-Request-Id": "req-1"]
            )!
            return (response, json)
        }

        let service = makeService(mock: mock)

        let response = try await service.requestWithResponse(
            path: "v1/users/2",
            responseType: TestUser.self
        )

        #expect(response.decodedBody?.name == "Bob")
        #expect(response.statusCode == .ok)
        #expect(response.headers["X-Request-Id"] == "req-1")
    }

    // MARK: - Retry behavior

    @Test("POST requests skip retry even with retry policy")
    func postRequestSkipsRetry() async {
        let callCount = SyncCounter()
        let mock = MockSession()
        mock.handler = { _ in
            callCount.increment()
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/action")!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = makeService(
            mock: mock,
            retryPolicy: RetryPolicy(maxAttempts: 3, baseDelay: 0.01, maxDelay: 0.02)
        )

        await #expect(throws: NetworkResponseError.self) {
            try await service.request(path: "v1/action", method: .post)
        }

        #expect(callCount.count == 1)
    }

    @Test("A request's own policy overrides the service's: a GET with .none goes out once")
    func perRequestPolicyOverridesService() async {
        let callCount = SyncCounter()
        let mock = MockSession()
        mock.handler = { request in
            callCount.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = makeService(
            mock: mock,
            retryPolicy: RetryPolicy(maxAttempts: 3, baseDelay: 0.001, maxDelay: 0.002)
        )

        await #expect(throws: NetworkResponseError.self) {
            try await service.request(path: "v1/side-effect", retryPolicy: RetryPolicy.none, responseType: TestUser.self)
        }
        #expect(callCount.count == 1)

        await #expect(throws: NetworkResponseError.self) {
            try await service.request(path: "v1/read", responseType: TestUser.self)
        }
        #expect(callCount.count == 4)
    }

    // MARK: - Failure observer

    @Test("The failure observer sees the final error once, after the retries")
    func failureObserverSeesFinalError() async {
        let seen = SyncErrors()
        let callCount = SyncCounter()
        let mock = MockSession()
        mock.handler = { request in
            callCount.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = NetworkService(
            baseURL: baseURL,
            client: NetworkClient(session: mock.session),
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.001, maxDelay: 0.002),
            failureObserver: { seen.append($0) }
        )

        await #expect(throws: NetworkResponseError.self) {
            try await service.request(path: "v1/users", responseType: TestUser.self)
        }

        #expect(callCount.count == 2)
        #expect(seen.count == 1)
        #expect((seen.first as? NetworkResponseError)?.httpStatusCode.rawValue == 503)
    }

    @Test("The failure observer sees a 401 through the public initializer, and never a success")
    func failureObserverSeesUnauthorized() async throws {
        let seen = SyncErrors()
        let mock = MockSession()
        mock.handler = { request in
            let status = request.url?.path.contains("private") == true ? 401 : 200
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"name":"ok"}"#.utf8))
        }

        let service = NetworkService(
            baseURL: baseURL,
            monitor: nil,
            sessionConfiguration: mock.configuration,
            failureObserver: { seen.append($0) }
        )

        let user: TestUser = try await service.request(path: "v1/public", responseType: TestUser.self)
        #expect(user.name == "ok")
        #expect(seen.count == 0)

        await #expect(throws: NetworkResponseError.self) {
            try await service.request(path: "v1/private", responseType: TestUser.self)
        }
        guard case .unauthorized? = seen.first as? NetworkResponseError else {
            Issue.record("Expected .unauthorized, got \(String(describing: seen.first))")
            return
        }
    }

    @Test("GET requests are retried according to retry policy")
    func getRequestRetriesOnFailure() async throws {
        let callCount = SyncCounter()
        let mock = MockSession()
        mock.handler = { _ in
            let count = callCount.increment()
            if count < 3 {
                let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/users")!, statusCode: 503, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            let json = Data(#"{"name":"recovered"}"#.utf8)
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/users")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let service = makeService(
            mock: mock,
            retryPolicy: RetryPolicy(maxAttempts: 3, baseDelay: 0.01, maxDelay: 0.02)
        )

        let user: TestUser = try await service.request(
            path: "v1/users",
            responseType: TestUser.self
        )

        #expect(user.name == "recovered")
        #expect(callCount.count == 3)
    }

    // MARK: - Monitoring

    @Test("startMonitoring and stopMonitoring call through to monitor")
    func monitoringLifecycle() {
        let mock = MockSession()
        let monitor = MockNetworkMonitor()
        let service = makeService(mock: mock, monitor: monitor)

        #expect(monitor.startCallCount == 0)
        #expect(monitor.stopCallCount == 0)

        service.startMonitoring()

        #expect(monitor.startCallCount == 1)
        #expect(monitor.stopCallCount == 0)

        service.stopMonitoring()

        #expect(monitor.startCallCount == 1)
        #expect(monitor.stopCallCount == 1)
    }

    @Test("Service works without monitor")
    func serviceWorksWithoutMonitor() async throws {
        let mock = MockSession()
        mock.handler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/health")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = makeService(mock: mock, monitor: nil)

        try await service.request(path: "v1/health")
    }

    @Test("Request fails with NetworkMonitorError when offline with ReachabilityInterceptor")
    func requestFailsWhenOffline() async {
        let mock = MockSession()
        mock.handler = { _ in
            Issue.record("Handler should not be called when offline")
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/users")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let monitor = MockNetworkMonitor(isConnected: false)
        let service = makeServiceWithReachability(mock: mock, monitor: monitor)

        await #expect(throws: NetworkMonitorError.self) {
            try await service.request(path: "v1/users", responseType: TestUser.self)
        }
    }

    @Test("Request succeeds when online with ReachabilityInterceptor")
    func requestSucceedsWhenOnline() async throws {
        let mock = MockSession()
        mock.handler = { _ in
            let json = Data(#"{"name":"online"}"#.utf8)
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/users")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let monitor = MockNetworkMonitor(isConnected: true)
        let service = makeServiceWithReachability(mock: mock, monitor: monitor)

        let user: TestUser = try await service.request(path: "v1/users", responseType: TestUser.self)
        #expect(user.name == "online")
    }

    // MARK: - Query parameters and headers

    @Test("request passes query parameters correctly")
    func requestPassesQueryParameters() async throws {
        let mock = MockSession()
        mock.handler = { request in
            let urlString = request.url?.absoluteString ?? ""
            #expect(urlString.contains("page=1"))
            #expect(urlString.contains("limit=20"))

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"name":"test"}"#.utf8))
        }

        let service = makeService(mock: mock)

        let _: TestUser = try await service.request(
            path: "v1/users",
            queryParameters: ["page": "1", "limit": "20"],
            responseType: TestUser.self
        )
    }

    @Test("request passes custom headers correctly")
    func requestPassesHeaders() async throws {
        let mock = MockSession()
        mock.handler = { request in
            #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "my-key")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"name":"test"}"#.utf8))
        }

        let service = makeService(mock: mock)

        let _: TestUser = try await service.request(
            path: "v1/users",
            headers: ["X-Api-Key": "my-key"],
            responseType: TestUser.self
        )
    }
}

// MARK: - Helpers

// MARK: - What the app chooses

/// Adds a header to every request, as an app's own interceptor would.
private struct HeaderStamp: NetworkInterceptor {
    func intercept(request: URLRequest) async throws -> URLRequest {
        var stamped = request
        stamped.setValue("ios", forHTTPHeaderField: "X-Client")
        return stamped
    }
}

@Suite("NetworkService options")
struct NetworkServiceOptionsTests {

    private let baseURL = URL(string: "https://api.example.com")!

    private static func ok(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"name":"ok"}"#.utf8))
    }

    @Test func theAppsInterceptorsRunOnEveryRequest() async throws {
        let seen = SyncHeaders()
        let mock = MockSession()
        mock.handler = { request in
            seen.append(request.value(forHTTPHeaderField: "X-Client"))
            return Self.ok(request)
        }

        let service = NetworkService(baseURL: baseURL, monitor: nil, sessionConfiguration: mock.configuration, interceptors: [HeaderStamp()])

        let _: TestUser = try await service.request(path: "v1/users", responseType: TestUser.self)

        #expect(seen.values == ["ios"])
    }

    @Test func theAppsLoggerReceivesTheLogAndItsTokenHeaderIsMasked() async throws {
        let mock = MockSession()
        mock.handler = { Self.ok($0) }
        let logger = MockNetworkLogger()

        let service = NetworkService(
            baseURL: baseURL,
            tokenProvider: MockKeychainTokenProvider(accessToken: "secret-token"),
            monitor: nil,
            headerKey: "X-Session",
            sessionConfiguration: mock.configuration,
            isVerbose: true,
            logger: logger
        )

        let _: TestUser = try await service.request(path: "v1/users", responseType: TestUser.self)

        let request = try #require(logger.entries.first { $0.message.contains("REQUEST") })
        let headers = try #require(request.metadata["headers"])

        #expect(headers.contains("[REDACTED]"))
        #expect(!headers.contains("secret-token"))
    }

    @Test func theRequestTimeoutReachesEveryRequest() async throws {
        let timeouts = SyncTimeouts()
        let mock = MockSession()
        mock.handler = { request in
            timeouts.append(request.timeoutInterval)
            return Self.ok(request)
        }

        let service = NetworkService(baseURL: baseURL, monitor: nil, sessionConfiguration: mock.configuration, requestTimeout: 5)

        let _: TestUser = try await service.request(path: "v1/users", responseType: TestUser.self)

        #expect(timeouts.values == [5])
    }
}

private final class SyncHeaders: Sendable {
    private let state = OSAllocatedUnfairLock<[String?]>(initialState: [])
    var values: [String?] { state.withLock { $0 } }
    func append(_ value: String?) { state.withLock { $0.append(value) } }
}

private final class SyncTimeouts: Sendable {
    private let state = OSAllocatedUnfairLock<[TimeInterval]>(initialState: [])
    var values: [TimeInterval] { state.withLock { $0 } }
    func append(_ value: TimeInterval) { state.withLock { $0.append(value) } }
}

private final class SyncErrors: Sendable {
    private let state = OSAllocatedUnfairLock<[any Error]>(initialState: [])

    var count: Int { state.withLock { $0.count } }
    var first: (any Error)? { state.withLock { $0.first } }

    func append(_ error: any Error) {
        state.withLock { $0.append(error) }
    }
}

private final class SyncCounter: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: 0)

    var count: Int {
        state.withLock { $0 }
    }

    @discardableResult
    func increment() -> Int {
        state.withLock {
            $0 += 1
            return $0
        }
    }
}
