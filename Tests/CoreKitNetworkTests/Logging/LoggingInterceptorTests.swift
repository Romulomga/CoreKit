import Testing
import Foundation
@testable import CoreKitNetwork

@Suite("LoggingInterceptor")
struct LoggingInterceptorTests {

    private let testURL = URL(string: "https://example.com/test")!

    // MARK: - Helpers

    private func makeRequest(
        headers: [String: String]? = nil,
        body: Data? = nil
    ) -> URLRequest {
        var request = URLRequest(url: testURL)
        request.allHTTPHeaderFields = headers
        request.httpBody = body
        return request
    }

    private func makeResponse(
        statusCode: Int = 200,
        headers: [String: String] = [:],
        data: Data = Data()
    ) -> NetworkResponse<EmptyResponse> {
        NetworkResponse<EmptyResponse>(
            data: data,
            statusCode: HTTPStatusCode(rawValue: statusCode),
            headers: headers,
            request: URLRequest(url: testURL),
            duration: 0.1
        )
    }

    // MARK: - Tests

    @Test("Redacts Authorization header when sensitive data is enabled")
    func redactsAuthorizationHeader() async throws {
        let logger = MockNetworkLogger()
        let interceptor = LoggingInterceptor(
            logger: logger,
            logLevel: .debug,
            includeSensitiveData: true
        )

        let request = makeRequest(headers: ["Authorization": "Bearer secret-token"])
        _ = try await interceptor.intercept(request: request)

        #expect(logger.entries.count == 1)
        let metadata = logger.entries[0].metadata
        #expect(metadata["headers"] != nil)
        #expect(metadata["headers"]!.contains("[REDACTED]"))
    }

    @Test("Redacts headers case-insensitively")
    func redactsCaseInsensitive() async throws {
        let logger = MockNetworkLogger()
        let interceptor = LoggingInterceptor(
            logger: logger,
            logLevel: .debug,
            includeSensitiveData: true
        )

        let request = makeRequest(headers: ["authorization": "Bearer secret-token"])
        _ = try await interceptor.intercept(request: request)

        #expect(logger.entries.count == 1)
        let metadata = logger.entries[0].metadata
        #expect(metadata["headers"] != nil)
        #expect(metadata["headers"]!.contains("[REDACTED]"))
    }

    @Test("Includes sensitive data when enabled")
    func includesSensitiveDataWhenEnabled() async throws {
        let logger = MockNetworkLogger()
        let interceptor = LoggingInterceptor(
            logger: logger,
            logLevel: .debug,
            includeSensitiveData: true
        )

        let request = makeRequest(
            headers: ["Content-Type": "application/json"],
            body: Data("{\"key\":\"value\"}".utf8)
        )
        _ = try await interceptor.intercept(request: request)

        #expect(logger.entries.count == 1)
        let metadata = logger.entries[0].metadata
        #expect(metadata["headers"] != nil)
        #expect(metadata["body"] != nil)
        #expect(metadata["headers_count"] == nil)
        #expect(metadata["body_size"] == nil)
    }

    @Test("Excludes sensitive data when disabled")
    func excludesSensitiveDataWhenDisabled() async throws {
        let logger = MockNetworkLogger()
        let interceptor = LoggingInterceptor(
            logger: logger,
            logLevel: .debug,
            includeSensitiveData: false
        )

        let request = makeRequest(
            headers: ["Content-Type": "application/json"],
            body: Data("{\"key\":\"value\"}".utf8)
        )
        _ = try await interceptor.intercept(request: request)

        #expect(logger.entries.count == 1)
        let metadata = logger.entries[0].metadata
        #expect(metadata["headers_count"] != nil)
        #expect(metadata["body_size"] != nil)
        #expect(metadata["headers"] == nil)
        #expect(metadata["body"] == nil)
    }

    @Test("Skips logging when level is below interceptor threshold")
    func skipsLoggingBelowLevel() async throws {
        let logger = MockNetworkLogger()
        let interceptor = LoggingInterceptor(
            logger: logger,
            logLevel: .warning,
            includeSensitiveData: false
        )

        let request = makeRequest()
        _ = try await interceptor.intercept(request: request)

        #expect(logger.entries.isEmpty)
    }

    @Test("Logs response as error for client errors")
    func logsResponseAsErrorForClientErrors() async throws {
        let logger = MockNetworkLogger()
        let interceptor = LoggingInterceptor(
            logger: logger,
            logLevel: .debug,
            includeSensitiveData: false
        )

        var response = makeResponse(statusCode: 400)
        try await interceptor.intercept(response: &response)

        #expect(logger.entries.count == 1)
        #expect(logger.entries[0].level == .error)
        #expect(logger.entries[0].message.contains("\u{2717}"))
    }

    @Test("Logs response as info for success")
    func logsResponseAsInfoForSuccess() async throws {
        let logger = MockNetworkLogger()
        let interceptor = LoggingInterceptor(
            logger: logger,
            logLevel: .debug,
            includeSensitiveData: false
        )

        var response = makeResponse(statusCode: 200)
        try await interceptor.intercept(response: &response)

        #expect(logger.entries.count == 1)
        #expect(logger.entries[0].level == .info)
        #expect(logger.entries[0].message.contains("\u{2713}"))
    }

    @Test("Redacts Cookie header when sensitive data is enabled")
    func redactsCookieHeader() async throws {
        let logger = MockNetworkLogger()
        let interceptor = LoggingInterceptor(
            logger: logger,
            logLevel: .debug,
            includeSensitiveData: true
        )

        let request = makeRequest(headers: [
            "Cookie": "session=abc123; secret=xyz",
            "Accept": "application/json"
        ])
        _ = try await interceptor.intercept(request: request)

        #expect(logger.entries.count == 1)
        let headersString = logger.entries[0].metadata["headers"]!
        #expect(headersString.contains("[REDACTED]"))
        #expect(!headersString.contains("abc123"))
        #expect(headersString.contains("application/json"))
    }

    @Test("Truncates response body longer than 500 characters")
    func truncatesLongResponseBody() async throws {
        let logger = MockNetworkLogger()
        let interceptor = LoggingInterceptor(
            logger: logger,
            logLevel: .debug,
            includeSensitiveData: true
        )

        let longBody = String(repeating: "a", count: 600)
        var response = makeResponse(statusCode: 200, data: Data(longBody.utf8))
        try await interceptor.intercept(response: &response)

        #expect(logger.entries.count == 1)
        let bodyString = logger.entries[0].metadata["body"]!
        #expect(bodyString.contains("(truncated)"))
        #expect(bodyString.count < 600)
    }

    @Test("Does not truncate response body of 500 characters or less")
    func doesNotTruncateShortResponseBody() async throws {
        let logger = MockNetworkLogger()
        let interceptor = LoggingInterceptor(
            logger: logger,
            logLevel: .debug,
            includeSensitiveData: true
        )

        let shortBody = String(repeating: "b", count: 500)
        var response = makeResponse(statusCode: 200, data: Data(shortBody.utf8))
        try await interceptor.intercept(response: &response)

        #expect(logger.entries.count == 1)
        let bodyString = logger.entries[0].metadata["body"]!
        #expect(!bodyString.contains("(truncated)"))
        #expect(bodyString == shortBody)
    }

    @Test("Redacts both Authorization and Cookie in response headers")
    func redactsMultipleHeadersInResponse() async throws {
        let logger = MockNetworkLogger()
        let interceptor = LoggingInterceptor(
            logger: logger,
            logLevel: .debug,
            includeSensitiveData: true
        )

        var response = makeResponse(
            statusCode: 200,
            headers: [
                "Authorization": "Bearer secret",
                "Cookie": "session=abc",
                "X-Request-Id": "req-123"
            ]
        )
        try await interceptor.intercept(response: &response)

        #expect(logger.entries.count == 1)
        let headersString = logger.entries[0].metadata["headers"]!
        #expect(!headersString.contains("secret"))
        #expect(!headersString.contains("abc"))
        #expect(headersString.contains("req-123"))
    }
}
