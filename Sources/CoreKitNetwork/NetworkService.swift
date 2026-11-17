import Foundation

/// The app's HTTP client over `URLSession`: JSON in and out, the token on every request that needs it (refreshed once on
/// a 401, shared by every request that hit it), reads retried with backoff, no request sent while offline, and a log
/// that never writes a credential where it outlives the session.
///
/// Every choice an app may want to make is a parameter whose default is the behaviour above: timeouts, the auth header,
/// the retry policy, extra interceptors, the logger, which headers and URL segments are masked.
public final class NetworkService: NetworkServing {

    /// Headers masked in every log, whatever the app adds: the usual credential and cookie headers.
    public static let defaultRedactedHeaders: Set<String> = [
        "Authorization", "Cookie", "Set-Cookie",
        "X-API-Key", "X-Auth-Token", "X-Access-Token", "X-TOKEN",
        "Proxy-Authorization", "WWW-Authenticate"
    ]

    // MARK: - Properties
    private let client: NetworkClient
    private let retryInterceptor: RetryInterceptor
    private let baseURL: URL
    private let networkMonitor: NetworkMonitoring?
    private let failureObserver: (@Sendable (any Error) -> Void)?
    private let requestTimeout: TimeInterval

    // MARK: - Initializers
    /// - Parameters:
    ///   - retryPolicy: the policy of every request that does not bring its own.
    ///   - sessionConfiguration: the base of the session's configuration (tests pass one with a
    ///     `URLProtocol`); the service still sets its timeouts, cache policy and headers on it.
    ///   - isVerbose: Debug only: every request with headers and bodies, when the traffic itself is
    ///     what is being debugged (the app passes its `--network-verbose` launch argument).
    ///   - failureObserver: sees every error a request finally throws (after retries, cancellation
    ///     included), so the app can react to a class of failure in one place (an expired session)
    ///     instead of in every caller. It must not block: it runs on the request's task.
    ///   - requestTimeout: how long a request may wait for data; `resourceTimeout`, the whole transfer.
    ///   - interceptors: the app's own, run after auth and before logging (so the log shows what they
    ///     added): a header every request carries, a request signature, a response it inspects.
    ///   - logger: where the log goes; `nil` keeps the console in debug and the unified log in release.
    ///   - redactedHeaders: headers masked in the log, besides `headerKey`, which always is.
    ///   - urlRedaction: what of the URL never reaches the debug mirror in the system log; the query
    ///     never does.
    public init(
        baseURL: URL,
        tokenProvider: TokenProvider? = nil,
        tokenRefresher: TokenRefresher? = nil,
        authPolicy: AuthPolicy = AuthenticateAllPolicy(),
        decoder: JSONDecoder? = nil,
        encoder: JSONEncoder? = nil,
        retryPolicy: RetryPolicy = .default,
        logLevel: LogLevel? = nil,
        monitor: NetworkMonitoring? = NetworkMonitor(),
        headerKey: String = "Authorization",
        headerPrefix: String = "",
        sessionConfiguration: URLSessionConfiguration = .default,
        isVerbose: Bool = false,
        failureObserver: (@Sendable (any Error) -> Void)? = nil,
        requestTimeout: TimeInterval = 40,
        resourceTimeout: TimeInterval = 60,
        interceptors appInterceptors: [any NetworkInterceptor] = [],
        logger customLogger: (any NetworkLogger)? = nil,
        redactedHeaders: Set<String> = NetworkService.defaultRedactedHeaders,
        urlRedaction: URLRedaction = URLRedaction()
    ) {
        self.baseURL = baseURL
        self.networkMonitor = monitor
        self.failureObserver = failureObserver
        self.requestTimeout = requestTimeout

        let configuration = sessionConfiguration

        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.httpAdditionalHeaders = (configuration.httpAdditionalHeaders ?? [:])
            .merging(["Accept": "application/json"]) { _, new in new }
        configuration.networkServiceType = .responsiveData

        let session = URLSession(configuration: configuration)

        // Debug logs one line per response and the details of a failure; `isVerbose` brings back
        // every request with headers and bodies.
        let resolvedLogLevel: LogLevel
        #if DEBUG
        resolvedLogLevel = logLevel ?? (isVerbose ? .debug : .info)
        #else
        resolvedLogLevel = logLevel ?? .info
        #endif

        #if DEBUG
        let builtInLogger: NetworkLogger = ConsoleNetworkLogger(urlRedaction: urlRedaction)
        #else
        let builtInLogger: NetworkLogger = OSLogNetworkLogger()
        #endif

        let logger = customLogger ?? builtInLogger

        let includeSensitiveData: Bool
        #if DEBUG
        includeSensitiveData = true
        #else
        includeSensitiveData = false
        #endif

        let loggingInterceptor = LoggingInterceptor(
            logger: logger,
            logLevel: resolvedLogLevel,
            includeSensitiveData: includeSensitiveData,
            sensitiveDataOnFailureOnly: !isVerbose,
            redactedHeaders: redactedHeaders.union([headerKey])
        )

        self.retryInterceptor = RetryInterceptor(policy: retryPolicy)

        if let monitor {
            monitor.start()
        }

        var interceptors: [NetworkInterceptor] = appInterceptors + [loggingInterceptor]

        if let tokenProvider {
            let authInterceptor = AuthInterceptor(
                tokenProvider: tokenProvider,
                tokenRefresher: tokenRefresher,
                authPolicy: authPolicy,
                session: session,
                headerKey: headerKey,
                headerPrefix: headerPrefix
            )
            interceptors.insert(authInterceptor, at: 0)
        }

        if let monitor {
            interceptors.insert(ReachabilityInterceptor(monitor: monitor), at: 0)
        }

        self.client = NetworkClient(
            session: session,
            decoder: decoder,
            encoder: encoder,
            interceptors: interceptors
        )
    }

    /// Internal initializer for testing — allows injecting a pre-configured client.
    init(
        baseURL: URL,
        client: NetworkClient,
        retryPolicy: RetryPolicy = .default,
        monitor: NetworkMonitoring? = nil,
        failureObserver: (@Sendable (any Error) -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.client = client
        self.retryInterceptor = RetryInterceptor(policy: retryPolicy)
        self.networkMonitor = monitor
        self.failureObserver = failureObserver
        self.requestTimeout = 40
    }

    // MARK: - Public Methods
    @discardableResult
    public func request<Response: Decodable & Sendable>(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        queryParameters: [String: String]? = nil,
        body: (any Encodable & Sendable)? = nil,
        retryPolicy: RetryPolicy? = nil,
        responseType: Response.Type
    ) async throws -> Response {
        let response = try await performRequest(
            path: path,
            method: method,
            headers: headers,
            queryParameters: queryParameters,
            body: body,
            retryPolicy: retryPolicy,
            responseType: responseType
        )

        guard let body = response.decodedBody else {
            throw NetworkClientError.decodingFailed("Response body was nil")
        }

        return body
    }

    public func request(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        queryParameters: [String: String]? = nil,
        body: (any Encodable & Sendable)? = nil,
        retryPolicy: RetryPolicy? = nil
    ) async throws {
        let _: EmptyResponse = try await request(
            path: path,
            method: method,
            headers: headers,
            queryParameters: queryParameters,
            body: body,
            retryPolicy: retryPolicy,
            responseType: EmptyResponse.self
        )
    }

    public func requestWithResponse<Response: Decodable & Sendable>(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        queryParameters: [String: String]? = nil,
        body: (any Encodable & Sendable)? = nil,
        retryPolicy: RetryPolicy? = nil,
        responseType: Response.Type
    ) async throws -> NetworkResponse<Response> {
        try await performRequest(
            path: path,
            method: method,
            headers: headers,
            queryParameters: queryParameters,
            body: body,
            retryPolicy: retryPolicy,
            responseType: responseType
        )
    }

    public func startMonitoring() {
        networkMonitor?.start()
    }

    public func stopMonitoring() {
        networkMonitor?.stop()
    }

    // MARK: - Private Methods
    private func performRequest<Response: Decodable & Sendable>(
        path: String,
        method: HTTPMethod,
        headers: [String: String],
        queryParameters: [String: String]?,
        body: (any Encodable & Sendable)?,
        retryPolicy: RetryPolicy?,
        responseType: Response.Type
    ) async throws -> NetworkResponse<Response> {
        let networkRequest = NetworkRequest(
            baseURL: baseURL,
            path: path,
            method: method,
            headers: headers,
            queryParameters: queryParameters,
            body: body,
            timeout: requestTimeout
        )

        do {
            let policy = retryPolicy ?? retryInterceptor.policy

            guard policy.shouldRetry(method: method) else {
                return try await client.request(networkRequest, responseType: responseType)
            }

            let client = self.client
            return try await retryInterceptor.executeWithRetry(policy: policy) {
                try await client.request(
                    networkRequest,
                    responseType: responseType
                )
            }
        } catch {
            failureObserver?(error)
            throw error
        }
    }
}
