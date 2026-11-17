import Testing
import Foundation
import os
@testable import CoreKitNetwork

private struct TestBody: Codable, Sendable {
    let name: String
}

private struct TestDateBody: Codable, Sendable {
    let createdAt: Date
}

/// An interceptor that throws on the way back, as the `AuthInterceptor` does on a 401 to ask for a refresh.
private struct ThrowingOnResponse: NetworkInterceptor {
    struct Failure: Error {}

    func intercept<T: Decodable>(response: inout NetworkResponse<T>) async throws {
        throw Failure()
    }
}

@Suite("NetworkClient")
struct NetworkClientTests {

    private let baseURL = URL(string: "https://api.example.com")!

    /// Logging goes in last so it records the request with the auth header set. If the way back kept the same order, a
    /// 401 would leave through the `AuthInterceptor` before being logged and the response would vanish from the
    /// console, as happened to a real `PUT` in an app.
    @Test("The response is logged even when another interceptor throws on the way back")
    func responseIsLoggedBeforeAnotherInterceptorThrows() async {
        let mock = MockSession()
        mock.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.example.com/v1/users")!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"detail":"nope"}"#.utf8))
        }
        let logger = MockNetworkLogger()
        let client = NetworkClient(
            session: mock.session,
            interceptors: [ThrowingOnResponse(), LoggingInterceptor(logger: logger, logLevel: .debug)]
        )

        _ = try? await client.request(NetworkRequest(baseURL: baseURL, path: "/v1/users"), responseType: TestBody.self)

        #expect(logger.entries.contains { $0.message.contains("RESPONSE") })
        #expect(logger.entries.contains { $0.metadata["status_code"] == "401" })
    }

    // MARK: - buildURLRequest

    @Test("buildURLRequest sets the correct URL from baseURL and path")
    func buildURLRequestSetsURL() throws {
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/users")
        let client = NetworkClient(session: URLSession.shared)

        let urlRequest = try client.buildURLRequest(from: endpoint)

        #expect(urlRequest.url?.absoluteString == "https://api.example.com/v1/users")
    }

    @Test("buildURLRequest sets the HTTP method")
    func buildURLRequestSetsMethod() throws {
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/users", method: .post)
        let client = NetworkClient(session: URLSession.shared)

        let urlRequest = try client.buildURLRequest(from: endpoint)

        #expect(urlRequest.httpMethod == "POST")
    }

    @Test("buildURLRequest sets custom headers")
    func buildURLRequestSetsHeaders() throws {
        let endpoint = NetworkRequest(
            baseURL: baseURL,
            path: "/v1/users",
            headers: ["X-Custom": "value"]
        )
        let client = NetworkClient(session: URLSession.shared)

        let urlRequest = try client.buildURLRequest(from: endpoint)

        #expect(urlRequest.allHTTPHeaderFields?["X-Custom"] == "value")
    }

    @Test("buildURLRequest encodes JSON body and sets Content-Type")
    func buildURLRequestSetsJSONBody() throws {
        let endpoint = NetworkRequest(
            baseURL: baseURL,
            path: "/v1/users",
            method: .post,
            body: TestBody(name: "test"),
            bodyEncoding: .json
        )
        let client = NetworkClient(session: URLSession.shared)

        let urlRequest = try client.buildURLRequest(from: endpoint)

        #expect(urlRequest.httpBody != nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("buildURLRequest encodes URL-encoded body and sets Content-Type")
    func buildURLRequestSetsURLEncodedBody() throws {
        let endpoint = NetworkRequest(
            baseURL: baseURL,
            path: "/v1/users",
            method: .post,
            body: TestBody(name: "test"),
            bodyEncoding: .urlEncoded
        )
        let client = NetworkClient(session: URLSession.shared)

        let urlRequest = try client.buildURLRequest(from: endpoint)

        #expect(urlRequest.httpBody != nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    }

    @Test("buildURLRequest does not override existing Content-Type header for JSON body")
    func buildURLRequestPreservesExistingContentType() throws {
        let endpoint = NetworkRequest(
            baseURL: baseURL,
            path: "/v1/users",
            method: .post,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: TestBody(name: "test"),
            bodyEncoding: .json
        )
        let client = NetworkClient(session: URLSession.shared)

        let urlRequest = try client.buildURLRequest(from: endpoint)

        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8")
    }

    @Test("buildURLRequest propagates timeout from endpoint")
    func buildURLRequestSetsTimeout() throws {
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/users", timeout: 120)
        let client = NetworkClient(session: URLSession.shared)

        let urlRequest = try client.buildURLRequest(from: endpoint)

        #expect(urlRequest.timeoutInterval == 120)
    }

    @Test("buildURLRequest propagates cachePolicy from endpoint")
    func buildURLRequestSetsCachePolicy() throws {
        let endpoint = NetworkRequest(
            baseURL: baseURL,
            path: "/v1/users",
            cachePolicy: .returnCacheDataElseLoad
        )
        let client = NetworkClient(session: URLSession.shared)

        let urlRequest = try client.buildURLRequest(from: endpoint)

        #expect(urlRequest.cachePolicy == .returnCacheDataElseLoad)
    }

    @Test("buildURLRequest with no body does not set httpBody or Content-Type")
    func buildURLRequestNoBody() throws {
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/users")
        let client = NetworkClient(session: URLSession.shared)

        let urlRequest = try client.buildURLRequest(from: endpoint)

        #expect(urlRequest.httpBody == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test("buildURLRequest URL-encoded body contains expected key-value pair")
    func buildURLRequestURLEncodedBodyContent() throws {
        let endpoint = NetworkRequest(
            baseURL: baseURL,
            path: "/v1/users",
            method: .post,
            body: TestBody(name: "hello"),
            bodyEncoding: .urlEncoded
        )
        let client = NetworkClient(session: URLSession.shared)

        let urlRequest = try client.buildURLRequest(from: endpoint)

        let bodyString = String(data: urlRequest.httpBody!, encoding: .utf8)!
        #expect(bodyString.contains("name=hello"))
    }

    @Test("buildURLRequest URL-encoded body keeps a plus sign instead of turning it into a space")
    func buildURLRequestURLEncodedBodyEncodesPlus() throws {
        let endpoint = NetworkRequest(
            baseURL: baseURL,
            path: "/v1/users",
            method: .post,
            body: TestBody(name: "+5521999998888"),
            bodyEncoding: .urlEncoded
        )
        let client = NetworkClient(session: URLSession.shared)

        let urlRequest = try client.buildURLRequest(from: endpoint)

        let bodyString = try #require(urlRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(bodyString.contains("name=%2B5521999998888"))
    }

    @Test("buildURLRequest throws encodingFailed for URL-encoded array body")
    func buildURLRequestURLEncodedArrayBodyThrows() {
        let endpoint = NetworkRequest(
            baseURL: baseURL,
            path: "/v1/users",
            method: .post,
            body: ["item1", "item2"],
            bodyEncoding: .urlEncoded
        )
        let client = NetworkClient(session: URLSession.shared)

        #expect(throws: NetworkClientError.self) {
            try client.buildURLRequest(from: endpoint)
        }
    }

    // MARK: - request

    @Test("request decodes a successful JSON response")
    func requestSuccessDecodesResponse() async throws {
        let mock = MockSession()
        mock.handler = { _ in
            let json = #"{"name":"test"}"#
            let response = HTTPURLResponse(
                url: URL(string: "https://api.example.com/v1/users")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }

        let client = NetworkClient(session: mock.session)
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/users")

        let response = try await client.request(endpoint, responseType: TestBody.self)

        #expect(response.decodedBody?.name == "test")
        #expect(response.statusCode == .ok)
    }

    @Test("request throws NetworkResponseError on non-success status code")
    func requestThrowsOnErrorStatus() async throws {
        let mock = MockSession()
        mock.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.example.com/v1/users")!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = NetworkClient(session: mock.session)
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/users")

        await #expect(throws: NetworkResponseError.self) {
            try await client.request(endpoint, responseType: EmptyResponse.self)
        }
    }

    @Test("request with EmptyResponse succeeds without JSON body")
    func requestEmptyResponseSucceeds() async throws {
        let mock = MockSession()
        mock.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.example.com/v1/action")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let client = NetworkClient(session: mock.session)
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/action", method: .post)

        let response = try await client.request(endpoint)

        #expect(response.statusCode == .ok)
        #expect(response.decodedBody != nil)
    }

    @Test("request throws NetworkClientError.decodingFailed on invalid JSON")
    func requestThrowsDecodingFailed() async {
        let mock = MockSession()
        mock.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.example.com/v1/users")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("not json".utf8))
        }

        let client = NetworkClient(session: mock.session)
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/users")

        do {
            _ = try await client.request(endpoint, responseType: TestBody.self)
            Issue.record("Expected NetworkClientError.decodingFailed")
        } catch let error as NetworkClientError {
            if case .decodingFailed(let message) = error {
                #expect(!message.isEmpty)
            } else {
                Issue.record("Expected .decodingFailed, got \(error)")
            }
        } catch {
            Issue.record("Expected NetworkClientError, got \(error)")
        }
    }

    @Test("request throws NetworkClientError.transport on URLError")
    func requestThrowsTransportOnURLError() async {
        let mock = MockSession()
        mock.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let client = NetworkClient(session: mock.session)
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/users")

        do {
            _ = try await client.request(endpoint, responseType: TestBody.self)
            Issue.record("Expected NetworkClientError.transport")
        } catch let error as NetworkClientError {
            if case .transport = error {} else {
                Issue.record("Expected .transport, got \(error)")
            }
        } catch {
            Issue.record("Expected NetworkClientError, got \(error)")
        }
    }

    @Test("request throws requestCancelled on URLError.cancelled")
    func requestThrowsRequestCancelledOnCancelledURLError() async {
        let mock = MockSession()
        mock.handler = { _ in
            throw URLError(.cancelled)
        }

        let client = NetworkClient(session: mock.session)
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/users")

        do {
            _ = try await client.request(endpoint, responseType: TestBody.self)
            Issue.record("Expected NetworkClientError.requestCancelled")
        } catch let error as NetworkClientError {
            if case .requestCancelled = error {} else {
                Issue.record("Expected .requestCancelled, got \(error)")
            }
        } catch {
            Issue.record("Expected NetworkClientError, got \(error)")
        }
    }

    @Test("request populates response headers from HTTPURLResponse")
    func requestPopulatesResponseHeaders() async throws {
        let mock = MockSession()
        mock.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.example.com/v1/users")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["X-Request-Id": "abc-123"]
            )!
            return (response, Data(#"{"name":"test"}"#.utf8))
        }

        let client = NetworkClient(session: mock.session)
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/users")

        let response = try await client.request(endpoint, responseType: TestBody.self)

        #expect(response.headers["X-Request-Id"] == "abc-123")
    }

    @Test("request measures duration greater than or equal to zero")
    func requestMeasuresDuration() async throws {
        let mock = MockSession()
        mock.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.example.com/v1/users")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"name":"test"}"#.utf8))
        }

        let client = NetworkClient(session: mock.session)
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/users")

        let response = try await client.request(endpoint, responseType: TestBody.self)

        #expect(response.duration >= 0)
    }

    // MARK: - Token refresh retry

    @Test("request retries once after AuthInterceptorError.tokenRefreshed")
    func requestRetriesAfterTokenRefresh() async throws {
        let callCount = SyncCounter()
        let mock = MockSession()
        mock.handler = { request in
            let count = callCount.increment()
            let statusCode = count == 1 ? 401 : 200
            let data = count == 1
                ? Data()
                : Data(#"{"name":"refreshed"}"#.utf8)

            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let provider = MockKeychainTokenProvider(accessToken: "old-token")
        let refresher = MockTokenRefresher()

        let authInterceptor = AuthInterceptor(
            tokenProvider: provider,
            tokenRefresher: refresher,
            session: mock.session
        )

        let client = NetworkClient(
            session: mock.session,
            interceptors: [authInterceptor]
        )

        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/users")
        let response = try await client.request(endpoint, responseType: TestBody.self)

        #expect(response.decodedBody?.name == "refreshed")
    }

    @Test("request throws unauthorized after exceeding max token refresh retries")
    func requestThrowsUnauthorizedAfterMaxRetries() async {
        let mock = MockSession()
        mock.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let provider = MockKeychainTokenProvider()
        let refresher = MockTokenRefresher()
        let authInterceptor = AuthInterceptor(
            tokenProvider: provider,
            tokenRefresher: refresher,
            session: mock.session
        )

        let client = NetworkClient(
            session: mock.session,
            interceptors: [authInterceptor]
        )

        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/users")

        do {
            _ = try await client.request(endpoint, responseType: EmptyResponse.self)
            Issue.record("Expected NetworkClientError.unauthorized")
        } catch let error as NetworkClientError {
            if case .unauthorized = error {} else {
                Issue.record("Expected .unauthorized, got \(error)")
            }
        } catch {
            Issue.record("Expected NetworkClientError, got \(error)")
        }
    }

    // MARK: - Date decoding

    @Test("request decodes ISO8601 date without fractional seconds")
    func requestDecodesISO8601Date() async throws {
        let mock = MockSession()
        mock.handler = { _ in
            let json = Data(#"{"createdAt":"2025-01-15T10:30:00Z"}"#.utf8)
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/item")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let client = NetworkClient(session: mock.session)
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/item")

        let response = try await client.request(endpoint, responseType: TestDateBody.self)

        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: response.decodedBody!.createdAt)
        #expect(components.year == 2025)
        #expect(components.month == 1)
        #expect(components.day == 15)
    }

    @Test("request decodes ISO8601 date with fractional seconds")
    func requestDecodesISO8601DateWithFractionalSeconds() async throws {
        let mock = MockSession()
        mock.handler = { _ in
            let json = Data(#"{"createdAt":"2025-06-20T14:05:30.123Z"}"#.utf8)
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/item")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let client = NetworkClient(session: mock.session)
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/item")

        let response = try await client.request(endpoint, responseType: TestDateBody.self)

        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: response.decodedBody!.createdAt)
        #expect(components.year == 2025)
        #expect(components.month == 6)
        #expect(components.hour == 14)
    }

    @Test("request throws decodingFailed for invalid date string")
    func requestThrowsDecodingFailedForInvalidDate() async {
        let mock = MockSession()
        mock.handler = { _ in
            let json = Data(#"{"createdAt":"not-a-date"}"#.utf8)
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/item")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let client = NetworkClient(session: mock.session)
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/item")

        do {
            _ = try await client.request(endpoint, responseType: TestDateBody.self)
            Issue.record("Expected NetworkClientError.decodingFailed")
        } catch let error as NetworkClientError {
            if case .decodingFailed(let message) = error {
                #expect(message.contains("not-a-date"))
            } else {
                Issue.record("Expected .decodingFailed, got \(error)")
            }
        } catch {
            Issue.record("Expected NetworkClientError, got \(error)")
        }
    }

    // MARK: - Cancellation

    @Test("cancelAllRequests cancels in-flight requests")
    func cancelAllRequestsCancelsInflight() async {
        let mock = MockSession()
        let requestStarted = SyncFlag()
        // The loader's thread waits here until the cancel went out, instead of a fixed 2 s.
        let cancelSent = DispatchSemaphore(value: 0)

        mock.handler = { _ in
            requestStarted.set()
            _ = cancelSent.wait(timeout: .now() + 10)
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/slow")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"name":"late"}"#.utf8))
        }

        let client = NetworkClient(session: mock.session)
        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/slow")

        // Launch the request in a separate task
        let requestTask = Task {
            try await client.request(endpoint, responseType: TestBody.self)
        }

        // Wait until the handler is entered, then cancel
        while !requestStarted.isSet {
            try? await Task.sleep(for: .milliseconds(5))
        }
        await client.cancelAllRequests()
        cancelSent.signal()

        // The contract the app's `error.isCancellation` relies on: a cancelled request ends as
        // `.requestCancelled`, never as a transport error that would become a toast.
        do {
            _ = try await requestTask.value
            Issue.record("Expected request to be cancelled")
        } catch let error as NetworkClientError {
            if case .requestCancelled = error {} else {
                Issue.record("Expected .requestCancelled, got \(error)")
            }
        } catch {
            Issue.record("Expected NetworkClientError.requestCancelled, got \(error)")
        }
    }

    // MARK: - Interceptors

    @Test("request calls interceptors in order for request phase")
    func requestCallsInterceptorsInOrder() async throws {
        let mock = MockSession()
        mock.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.example.com/v1/test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let order = OrderTracker()

        let interceptor1 = OrderedInterceptor(id: "first", order: order)
        let interceptor2 = OrderedInterceptor(id: "second", order: order)

        let client = NetworkClient(
            session: mock.session,
            interceptors: [interceptor1, interceptor2]
        )

        let endpoint = NetworkRequest(baseURL: baseURL, path: "/v1/test")
        _ = try await client.request(endpoint)

        let recorded = await order.recorded
        #expect(recorded.count >= 2)
        #expect(recorded[0] == "first")
        #expect(recorded[1] == "second")
    }
}

// MARK: - Helpers

private final class SyncCounter: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: 0)

    @discardableResult
    func increment() -> Int {
        state.withLock {
            $0 += 1
            return $0
        }
    }
}

private actor OrderTracker {
    var recorded: [String] = []

    func append(_ id: String) {
        recorded.append(id)
    }
}

private final class OrderedInterceptor: NetworkInterceptor {
    let id: String
    let order: OrderTracker

    init(id: String, order: OrderTracker) {
        self.id = id
        self.order = order
    }

    func intercept(request: URLRequest) async throws -> URLRequest {
        await order.append(id)
        return request
    }

    func intercept<T: Decodable>(response: inout NetworkResponse<T>) async throws {}
}

private final class SyncFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    var isSet: Bool {
        state.withLock { $0 }
    }

    func set() {
        state.withLock { $0 = true }
    }
}
