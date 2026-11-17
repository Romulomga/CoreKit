import Testing
import Foundation
@testable import CoreKitNetwork

@Suite("RetryInterceptor")
struct RetryInterceptorTests {

    private func makeInterceptor(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 0.01,
        maxDelay: TimeInterval = 0.05,
        sleepFunction: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in }
    ) -> RetryInterceptor {
        RetryInterceptor(
            policy: RetryPolicy(
                maxAttempts: maxAttempts,
                baseDelay: baseDelay,
                maxDelay: maxDelay
            ),
            sleepFunction: sleepFunction
        )
    }

    @Test("Succeeds on first attempt without retry")
    func succeedsFirstTry() async throws {
        let interceptor = makeInterceptor()
        let counter = CallCounter()

        let result = try await interceptor.executeWithRetry {
            await counter.increment()
            return "ok"
        }

        #expect(result == "ok")
        #expect(await counter.count == 1)
    }

    @Test("Retries on URLError.timedOut then succeeds")
    func retriesOnURLError() async throws {
        let interceptor = makeInterceptor()
        let counter = CallCounter()

        let result = try await interceptor.executeWithRetry {
            let c = await counter.increment()
            if c < 2 { throw URLError(.timedOut) }
            return "recovered"
        }

        #expect(result == "recovered")
        #expect(await counter.count == 2)
    }

    @Test("Retries on NetworkClientError.transport wrapping retryable URLError")
    func retriesOnTransportError() async throws {
        let interceptor = makeInterceptor()
        let counter = CallCounter()

        let result = try await interceptor.executeWithRetry {
            let c = await counter.increment()
            if c < 2 { throw NetworkClientError.transport(URLError(.networkConnectionLost)) }
            return "recovered"
        }

        #expect(result == "recovered")
        #expect(await counter.count == 2)
    }

    @Test("Retries on retryable NetworkResponseError (503)")
    func retriesOnRetryableResponseError() async throws {
        let interceptor = makeInterceptor()
        let counter = CallCounter()

        let result = try await interceptor.executeWithRetry {
            let c = await counter.increment()
            if c < 2 { throw NetworkResponseError.serviceUnavailable("down") }
            return "recovered"
        }

        #expect(result == "recovered")
        #expect(await counter.count == 2)
    }

    @Test("Does not retry non-retryable errors")
    func doesNotRetryNonRetryable() async {
        let interceptor = makeInterceptor()
        let counter = CallCounter()

        do {
            _ = try await interceptor.executeWithRetry {
                await counter.increment()
                throw NetworkClientError.invalidURL
            }
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is NetworkClientError)
        }

        #expect(await counter.count == 1)
    }

    @Test("Does not retry non-retryable status codes (404)")
    func doesNotRetryNonRetryableStatusCode() async {
        let interceptor = makeInterceptor()
        let counter = CallCounter()

        do {
            _ = try await interceptor.executeWithRetry {
                await counter.increment()
                throw NetworkResponseError.notFound("gone")
            }
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is NetworkResponseError)
        }

        #expect(await counter.count == 1)
    }

    @Test("Throws original error after exhausting maxAttempts")
    func respectsMaxAttempts() async {
        let interceptor = makeInterceptor(maxAttempts: 3)
        let counter = CallCounter()

        do {
            _ = try await interceptor.executeWithRetry {
                await counter.increment()
                throw URLError(.timedOut)
            }
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is URLError)
        }

        #expect(await counter.count == 3)
    }

    @Test("Single attempt policy does not retry")
    func singleAttempt() async {
        let interceptor = makeInterceptor(maxAttempts: 1)
        let counter = CallCounter()

        do {
            _ = try await interceptor.executeWithRetry {
                await counter.increment()
                throw URLError(.timedOut)
            }
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is URLError)
        }

        #expect(await counter.count == 1)
    }

    // MARK: - Delay / backoff validation

    @Test("Sleep is called with increasing delays on each retry")
    func delayIncreasesPerAttempt() async {
        let delays = DelayRecorder()
        let interceptor = makeInterceptor(
            maxAttempts: 4,
            baseDelay: 1.0,
            maxDelay: 30.0,
            sleepFunction: { delay in await delays.record(delay) }
        )
        let counter = CallCounter()

        do {
            _ = try await interceptor.executeWithRetry {
                let c = await counter.increment()
                if c < 4 { throw URLError(.timedOut) }
                return "ok"
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let recorded = await delays.values
        #expect(recorded.count == 3) // 3 retries before success on 4th attempt

        // Verify exponential growth: each delay should be roughly 2x the previous
        // With jitter ±25%, delay[n] = baseDelay * 2^n * (0.75...1.25)
        // attempt 0: 1.0 * 1 = [0.75, 1.25]
        // attempt 1: 1.0 * 2 = [1.50, 2.50]
        // attempt 2: 1.0 * 4 = [3.00, 5.00]
        for (index, delay) in recorded.enumerated() {
            let base = 1.0 * pow(2.0, Double(index))
            #expect(delay >= base * 0.75, "Delay \(index) (\(delay)) should be >= \(base * 0.75)")
            #expect(delay <= base * 1.25, "Delay \(index) (\(delay)) should be <= \(base * 1.25)")
        }
    }

    @Test("Delay is capped at maxDelay")
    func delayCappedAtMax() async {
        let delays = DelayRecorder()
        let interceptor = makeInterceptor(
            maxAttempts: 5,
            baseDelay: 10.0,
            maxDelay: 15.0,
            sleepFunction: { delay in await delays.record(delay) }
        )

        await #expect(throws: URLError.self) {
            _ = try await interceptor.executeWithRetry {
                throw URLError(.timedOut)
            }
        }

        let recorded = await delays.values
        for delay in recorded {
            #expect(delay <= 15.0, "Delay \(delay) should not exceed maxDelay of 15.0")
        }
    }

    @Test("No sleep is called when succeeding on first try")
    func noDelayOnFirstSuccess() async throws {
        let delays = DelayRecorder()
        let interceptor = makeInterceptor(
            sleepFunction: { delay in await delays.record(delay) }
        )

        _ = try await interceptor.executeWithRetry { "ok" }

        let recorded = await delays.values
        #expect(recorded.isEmpty)
    }

    @Test("Zero maxAttempts throws maxAttemptsExceeded without executing closure")
    func zeroMaxAttemptsThrows() async {
        let interceptor = RetryInterceptor(
            policy: RetryPolicy(maxAttempts: 0),
            sleepFunction: { _ in }
        )
        let counter = CallCounter()

        do {
            _ = try await interceptor.executeWithRetry {
                await counter.increment()
                return "should not reach"
            }
            Issue.record("Expected RetryInterceptorError.maxAttemptsExceeded")
        } catch is RetryInterceptorError {
            // Expected
        } catch {
            Issue.record("Expected RetryInterceptorError, got \(error)")
        }

        #expect(await counter.count == 0)
    }
}

// MARK: - Helpers

private actor CallCounter {
    private(set) var count = 0

    @discardableResult
    func increment() -> Int {
        count += 1
        return count
    }
}

private actor DelayRecorder {
    private(set) var values: [TimeInterval] = []

    func record(_ delay: TimeInterval) {
        values.append(delay)
    }
}
