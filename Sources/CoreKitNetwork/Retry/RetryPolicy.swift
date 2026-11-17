import Foundation

public struct RetryPolicy: Sendable {

    // MARK: - Properties
    public let maxAttempts: Int
    public let retryableStatusCodes: Set<Int>
    public let retryableURLErrorCodes: Set<URLError.Code>
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let allowedMethods: Set<HTTPMethod>
    public let jitterRange: ClosedRange<Double>

    // MARK: - Initializers
    /// Only reads retry by default: a method that is idempotent in HTTP (`PUT`, `DELETE`) may still
    /// have side effects on a given server, so a mutation is never resent blindly. A read with a side
    /// effect opts out per request (`.none`). No connection at all (`notConnectedToInternet`) fails
    /// at once instead of waiting through the backoff: the caller shows "offline" and retries when the
    /// connection comes back; a lost connection or a timeout may be transient and is retried.
    public init(
        maxAttempts: Int = 3,
        retryableStatusCodes: Set<Int> = Set([408, 429]).union(500...599),
        retryableURLErrorCodes: Set<URLError.Code> = [.timedOut, .networkConnectionLost],
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        allowedMethods: Set<HTTPMethod> = [.get, .head, .options],
        jitterRange: ClosedRange<Double> = -0.25...0.25
    ) {
        self.maxAttempts = maxAttempts
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableURLErrorCodes = retryableURLErrorCodes
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.allowedMethods = allowedMethods
        self.jitterRange = jitterRange
    }

    // MARK: - Helpers
    public static var `default`: RetryPolicy { RetryPolicy() }

    /// No retries; uses a single attempt per request.
    public static var none: RetryPolicy {
        RetryPolicy(allowedMethods: [])
    }

    public func shouldRetry(method: HTTPMethod) -> Bool {
        allowedMethods.contains(method)
    }

    public func shouldRetry(statusCode: HTTPStatusCode) -> Bool {
        retryableStatusCodes.contains(statusCode.rawValue)
    }

    public func shouldRetry(error: URLError) -> Bool {
        retryableURLErrorCodes.contains(error.code)
    }

    public func delay(for attempt: Int, statusCode: HTTPStatusCode?) -> TimeInterval {
        let cappedAttempt = max(0, attempt)
        let multiplier: Double = statusCode?.rawValue == 429 ? 2.0 : 1.0
        let exponentialDelay = baseDelay * multiplier * pow(2.0, Double(cappedAttempt))

        let jitter = exponentialDelay * Double.random(in: jitterRange)
        let delayWithJitter = exponentialDelay + jitter

        return min(delayWithJitter, maxDelay)
    }
}
