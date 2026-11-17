import Foundation

public final class AuthInterceptor: NetworkInterceptor {

    // MARK: - Properties

    private let tokenProvider: TokenProvider
    private let tokenRefresher: TokenRefresher?
    private let authPolicy: AuthPolicy
    private let headerKey: String
    private let headerPrefix: String
    private let session: URLSession

    private actor RefreshState {
        private var activeTask: Task<Void, Error>?
        /// Callers waiting on the refresh in flight instead of starting their own (tests read it
        /// to release a held refresh only once everyone joined).
        private(set) var joined = 0

        func performRefresh(_ operation: @Sendable @escaping () async throws -> Void) async throws {
            if let activeTask {
                joined += 1
                return try await activeTask.value
            }

            let task = Task { try await operation() }
            activeTask = task

            defer { activeTask = nil }
            try await task.value
        }
    }

    private let refreshState = RefreshState()

    /// How many calls joined a refresh already in flight (tests).
    var refreshJoinedCount: Int {
        get async { await refreshState.joined }
    }

    // MARK: - Initializers
    public init(
        tokenProvider: TokenProvider,
        tokenRefresher: TokenRefresher? = nil,
        authPolicy: AuthPolicy = AuthenticateAllPolicy(),
        session: URLSession = .shared,
        headerKey: String = "Authorization",
        headerPrefix: String = ""
    ) {
        self.tokenProvider = tokenProvider
        self.tokenRefresher = tokenRefresher
        self.authPolicy = authPolicy
        self.session = session
        self.headerKey = headerKey
        self.headerPrefix = headerPrefix
    }

    // MARK: - Public Methods
    public func intercept(request: URLRequest) async throws -> URLRequest {
        var modifiedRequest = request

        guard authPolicy.requiresAuthentication(for: request) else {
            modifiedRequest.setValue(nil, forHTTPHeaderField: headerKey)
            return modifiedRequest
        }

        do {
            let token = try await tokenProvider.getAccessToken()
            modifiedRequest.setValue("\(headerPrefix)\(token)", forHTTPHeaderField: headerKey)
        } catch is UnauthenticatedTokenProviderError {
            modifiedRequest.setValue(nil, forHTTPHeaderField: headerKey)
        } catch {
            throw AuthInterceptorError.tokenUnavailable
        }

        return modifiedRequest
    }

    public func intercept<T: Decodable>(response: inout NetworkResponse<T>) async throws {
        guard response.statusCode == .unauthorized,
              authPolicy.requiresAuthentication(for: response.request) else {
            return
        }

        try await performTokenRefresh()
        throw AuthInterceptorError.tokenRefreshed
    }

    // MARK: - Private Methods
    private func performTokenRefresh() async throws {
        guard let tokenRefresher else {
            throw AuthInterceptorError.refreshNotConfigured
        }

        let session = self.session
        try await refreshState.performRefresh {
            try await tokenRefresher.refresh(using: session)
        }
    }
}
