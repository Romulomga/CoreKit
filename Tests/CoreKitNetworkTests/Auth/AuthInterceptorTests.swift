import Testing
import Foundation
@testable import CoreKitNetwork

@Suite("AuthInterceptor")
struct AuthInterceptorTests {

    private struct FailingTokenProvider: TokenProvider {
        func getAccessToken() async throws -> String {
            throw MockKeychainTokenProvider.MockTokenError.forced
        }
    }

    private func makeInterceptor(
        tokenProvider: TokenProvider = MockKeychainTokenProvider(),
        tokenRefresher: TokenRefresher? = nil,
        authPolicy: AuthPolicy = AuthenticateAllPolicy(),
        headerKey: String = "Authorization",
        headerPrefix: String = ""
    ) -> AuthInterceptor {
        AuthInterceptor(
            tokenProvider: tokenProvider,
            tokenRefresher: tokenRefresher,
            authPolicy: authPolicy,
            session: URLSession.shared,
            headerKey: headerKey,
            headerPrefix: headerPrefix
        )
    }

    private func makeURLRequest() -> URLRequest {
        URLRequest(url: URL(string: "https://api.example.com/test")!)
    }

    private func makePublicURLRequest() -> URLRequest {
        URLRequest(url: URL(string: "https://api.example.com/v1/public/test")!)
    }

    private func makeAuthURLRequest() -> URLRequest {
        URLRequest(url: URL(string: "https://api.example.com/v1/auth")!)
    }

    private func makeRefreshTokenURLRequest() -> URLRequest {
        URLRequest(url: URL(string: "https://api.example.com/v1/auth/refresh_token")!)
    }

    private var publicAuthPolicy: MockAuthPolicy {
        MockAuthPolicy(unauthenticatedPaths: ["/public/", "/v1/auth"])
    }

    private func make401Response() -> NetworkResponse<EmptyResponse> {
        NetworkResponse<EmptyResponse>(
            data: Data(),
            statusCode: HTTPStatusCode(rawValue: 401),
            headers: [:],
            request: makeURLRequest()
        )
    }

    private func make401PublicResponse() -> NetworkResponse<EmptyResponse> {
        NetworkResponse<EmptyResponse>(
            data: Data(),
            statusCode: HTTPStatusCode(rawValue: 401),
            headers: [:],
            request: makePublicURLRequest()
        )
    }

    private func make401AuthResponse() -> NetworkResponse<EmptyResponse> {
        NetworkResponse<EmptyResponse>(
            data: Data(),
            statusCode: HTTPStatusCode(rawValue: 401),
            headers: [:],
            request: makeAuthURLRequest()
        )
    }

    // MARK: - Request interception

    @Test("Adds access token to Authorization header")
    func addsAuthHeader() async throws {
        let provider = MockKeychainTokenProvider(accessToken: "token-123")
        let interceptor = makeInterceptor(tokenProvider: provider)

        let modified = try await interceptor.intercept(request: makeURLRequest())

        #expect(modified.value(forHTTPHeaderField: "Authorization") == "token-123")
    }

    @Test("Uses custom header key and prefix")
    func customHeaderKeyAndPrefix() async throws {
        let provider = MockKeychainTokenProvider(accessToken: "abc")
        let interceptor = makeInterceptor(tokenProvider: provider, headerKey: "X-Auth", headerPrefix: "Bearer ")

        let modified = try await interceptor.intercept(request: makeURLRequest())

        #expect(modified.value(forHTTPHeaderField: "X-Auth") == "Bearer abc")
    }

    @Test("Skips auth for UnauthenticatedTokenProvider")
    func skipsAuthForUnauthenticated() async throws {
        let interceptor = makeInterceptor(tokenProvider: UnauthenticatedTokenProvider())

        let modified = try await interceptor.intercept(request: makeURLRequest())

        #expect(modified.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Throws tokenUnavailable when token provider fails unexpectedly")
    func throwsWhenTokenProviderFails() async throws {
        let interceptor = makeInterceptor(tokenProvider: FailingTokenProvider())

        await #expect(throws: AuthInterceptorError.tokenUnavailable) {
            _ = try await interceptor.intercept(request: makeURLRequest())
        }
    }

    @Test("Does not add Authorization header for public endpoints")
    func skipsAuthForPublicEndpoints() async throws {
        let provider = MockKeychainTokenProvider(accessToken: "token-123")
        let interceptor = makeInterceptor(tokenProvider: provider, authPolicy: publicAuthPolicy)

        let modified = try await interceptor.intercept(request: makePublicURLRequest())

        #expect(modified.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Does not add Authorization header for auth endpoints")
    func skipsAuthForAuthEndpoints() async throws {
        let provider = MockKeychainTokenProvider(accessToken: "token-123")
        let interceptor = makeInterceptor(tokenProvider: provider, authPolicy: publicAuthPolicy)

        let modified = try await interceptor.intercept(request: makeAuthURLRequest())

        #expect(modified.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Does not add Authorization header for refresh token endpoints")
    func skipsAuthForRefreshTokenEndpoints() async throws {
        let provider = MockKeychainTokenProvider(accessToken: "token-123")
        let interceptor = makeInterceptor(tokenProvider: provider, authPolicy: publicAuthPolicy)

        let modified = try await interceptor.intercept(request: makeRefreshTokenURLRequest())

        #expect(modified.value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: - Response interception & token refresh

    @Test("Throws AuthInterceptorError.tokenRefreshed after successful refresh on 401")
    func triggersRefreshOn401() async throws {
        let refresher = MockTokenRefresher()
        let interceptor = makeInterceptor(tokenRefresher: refresher)
        var response = make401Response()

        do {
            try await interceptor.intercept(response: &response)
            Issue.record("Expected AuthInterceptorError.tokenRefreshed to be thrown")
        } catch let error as AuthInterceptorError {
            #expect(error == .tokenRefreshed)
        } catch {
            Issue.record("Expected AuthInterceptorError.tokenRefreshed, got \(error)")
        }

        #expect(refresher.refreshCallCount == 1)
    }

    @Test("Throws refreshNotConfigured when no refresher is set")
    func throwsRefreshNotConfigured() async throws {
        let interceptor = makeInterceptor(tokenRefresher: nil)
        var response = make401Response()

        do {
            try await interceptor.intercept(response: &response)
            Issue.record("Expected AuthInterceptorError.refreshNotConfigured to be thrown")
        } catch let error as AuthInterceptorError {
            #expect(error == .refreshNotConfigured)
        } catch {
            Issue.record("Expected AuthInterceptorError.refreshNotConfigured, got \(error)")
        }
    }

    @Test("Propagates error from token refresher")
    func propagatesRefresherError() async throws {
        let refresher = MockTokenRefresher()
        refresher.error = NSError(domain: "test", code: 42)
        let interceptor = makeInterceptor(tokenRefresher: refresher)
        var response = make401Response()

        await #expect(throws: Error.self) {
            try await interceptor.intercept(response: &response)
        }

        #expect(refresher.refreshCallCount == 1)
    }

    @Test("Does nothing for non-401 responses")
    func noRefreshForNon401() async throws {
        let provider = MockKeychainTokenProvider()
        let interceptor = makeInterceptor(tokenProvider: provider)

        var response = NetworkResponse<EmptyResponse>(
            data: Data(),
            statusCode: HTTPStatusCode(rawValue: 200),
            headers: [:],
            request: makeURLRequest()
        )

        try await interceptor.intercept(response: &response)

        #expect(provider.getAccessTokenCallCount == 0)
    }

    @Test("Does not refresh for 401 responses on public endpoints")
    func noRefreshForPublic401() async throws {
        let refresher = MockTokenRefresher()
        let interceptor = makeInterceptor(tokenRefresher: refresher, authPolicy: publicAuthPolicy)
        var response = make401PublicResponse()

        try await interceptor.intercept(response: &response)

        #expect(refresher.refreshCallCount == 0)
    }

    @Test("Does not refresh for 401 responses on auth endpoints")
    func noRefreshForAuth401() async throws {
        let refresher = MockTokenRefresher()
        let interceptor = makeInterceptor(tokenRefresher: refresher, authPolicy: publicAuthPolicy)
        var response = make401AuthResponse()

        try await interceptor.intercept(response: &response)

        #expect(refresher.refreshCallCount == 0)
    }

    @Test("Does nothing for other client error responses")
    func noRefreshFor403() async throws {
        let refresher = MockTokenRefresher()
        let interceptor = makeInterceptor(tokenRefresher: refresher)

        var response = NetworkResponse<EmptyResponse>(
            data: Data(),
            statusCode: HTTPStatusCode(rawValue: 403),
            headers: [:],
            request: makeURLRequest()
        )

        try await interceptor.intercept(response: &response)

        #expect(refresher.refreshCallCount == 0)
    }

    // MARK: - Concurrent refresh deduplication

    @Test("Concurrent 401 responses deduplicate into a single refresh call")
    func concurrentRefreshDeduplication() async throws {
        let refresher = MockTokenRefresher()
        // Held until the other two calls joined it: a fixed sleep let a late caller start a
        // second refresh on a loaded runner.
        let (released, release) = AsyncStream<Void>.makeStream()
        refresher.onRefresh = { _ in
            for await _ in released { break }
        }

        let interceptor = makeInterceptor(tokenRefresher: refresher)

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                // Bounded: if the dedup broke, release anyway and let the count expectation fail.
                var polls = 5_000
                while polls > 0, await interceptor.refreshJoinedCount < 2 {
                    try? await Task.sleep(for: .milliseconds(1))
                    polls -= 1
                }
                release.yield()
                release.finish()
            }
            for _ in 0..<3 {
                group.addTask {
                    var response = NetworkResponse<EmptyResponse>(
                        data: Data(),
                        statusCode: HTTPStatusCode(rawValue: 401),
                        headers: [:],
                        request: URLRequest(url: URL(string: "https://api.example.com/test")!)
                    )
                    do {
                        try await interceptor.intercept(response: &response)
                    } catch is AuthInterceptorError {
                        // Expected: tokenRefreshed
                    } catch {
                        // Other errors are acceptable too
                    }
                }
            }
        }

        #expect(refresher.refreshCallCount == 1)
    }
}
