import Testing
import Foundation
@testable import CoreKitNetwork

@Suite("RetryPolicy")
struct RetryPolicyTests {

    // MARK: - shouldRetry(method:)

    @Test("Should retry allowed method")
    func shouldRetryAllowedMethod() {
        let policy = RetryPolicy.default
        #expect(policy.shouldRetry(method: .get) == true)
    }

    @Test("Should not retry disallowed method")
    func shouldNotRetryDisallowedMethod() {
        let policy = RetryPolicy.default
        #expect(policy.shouldRetry(method: .post) == false)
    }

    @Test("Default policy never resends a mutation")
    func defaultPolicyRetriesOnlyReads() {
        let policy = RetryPolicy.default
        #expect(policy.allowedMethods == [.get, .head, .options])
        for method: HTTPMethod in [.post, .put, .patch, .delete] {
            #expect(policy.shouldRetry(method: method) == false)
        }
    }

    // MARK: - shouldRetry(statusCode:)

    @Test("Should retry retryable status code")
    func shouldRetryRetryableStatusCode() {
        let policy = RetryPolicy.default
        #expect(policy.shouldRetry(statusCode: HTTPStatusCode(rawValue: 503)) == true)
    }

    @Test("Every 5xx is retryable, plus 408 and 429")
    func retriesWholeServerErrorRange() {
        let policy = RetryPolicy.default
        for code in [408, 429, 500, 501, 502, 503, 504, 505, 507, 511, 555, 599] {
            #expect(policy.shouldRetry(statusCode: HTTPStatusCode(rawValue: code)), "\(code)")
        }
        for code in [400, 401, 403, 404, 409, 422, 499, 600] {
            #expect(!policy.shouldRetry(statusCode: HTTPStatusCode(rawValue: code)), "\(code)")
        }
    }

    @Test("Should not retry non-retryable status code")
    func shouldNotRetryNonRetryableStatusCode() {
        let policy = RetryPolicy.default
        #expect(policy.shouldRetry(statusCode: HTTPStatusCode(rawValue: 404)) == false)
    }

    // MARK: - shouldRetry(error:)

    @Test("Should retry retryable URLError")
    func shouldRetryRetryableURLError() {
        let policy = RetryPolicy.default
        #expect(policy.shouldRetry(error: URLError(.timedOut)) == true)
    }

    @Test("No connection fails at once: offline is not retried")
    func offlineIsNotRetried() {
        #expect(!RetryPolicy.default.shouldRetry(error: URLError(.notConnectedToInternet)))
        #expect(RetryPolicy.default.shouldRetry(error: URLError(.networkConnectionLost)))
    }

    @Test("Should not retry non-retryable URLError")
    func shouldNotRetryNonRetryableURLError() {
        let policy = RetryPolicy.default
        #expect(policy.shouldRetry(error: URLError(.badURL)) == false)
    }

    // MARK: - delay(for:statusCode:)

    @Test("Delay grows exponentially")
    func delayExponentialGrowth() {
        let policy = RetryPolicy(
            baseDelay: 1.0,
            jitterRange: 0.0...0.0
        )

        #expect(policy.delay(for: 0, statusCode: nil) == 1.0)
        #expect(policy.delay(for: 1, statusCode: nil) == 2.0)
        #expect(policy.delay(for: 2, statusCode: nil) == 4.0)
    }

    @Test("Delay is capped at maxDelay")
    func delayCappedAtMaxDelay() {
        let policy = RetryPolicy(
            baseDelay: 1.0,
            maxDelay: 5.0,
            jitterRange: 0.0...0.0
        )

        #expect(policy.delay(for: 10, statusCode: nil) == 5.0)
    }

    @Test("Delay applies 2x multiplier for 429 status code")
    func delay429Multiplier() {
        let policy = RetryPolicy(
            baseDelay: 1.0,
            jitterRange: 0.0...0.0
        )

        #expect(policy.delay(for: 0, statusCode: HTTPStatusCode(rawValue: 429)) == 2.0)
    }

    // MARK: - Static policies

    @Test("Default policy has expected values")
    func defaultPolicyValues() {
        let policy = RetryPolicy.default

        #expect(policy.maxAttempts == 3)
        #expect(policy.baseDelay == 1.0)
        #expect(policy.maxDelay == 30.0)
    }

    @Test("None policy has no allowed methods")
    func nonePolicyNoAllowedMethods() {
        let policy = RetryPolicy.none

        #expect(policy.allowedMethods.isEmpty)
        #expect(policy.shouldRetry(method: .get) == false)
    }
}
