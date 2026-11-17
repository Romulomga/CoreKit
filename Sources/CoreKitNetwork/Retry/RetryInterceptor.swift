import Foundation

final class RetryInterceptor: Sendable {

    // MARK: - Properties
    let policy: RetryPolicy
    private let sleepFunction: @Sendable (TimeInterval) async throws -> Void

    // MARK: - Initializers
    init(
        policy: RetryPolicy = .default,
        sleepFunction: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.policy = policy
        self.sleepFunction = sleepFunction
    }

    // MARK: - Public Methods
    /// Runs `execute` under `policy`, or under the one this interceptor was built with.
    func executeWithRetry<T>(
        policy override: RetryPolicy? = nil,
        execute: @Sendable () async throws -> T
    ) async throws -> T {
        let policy = override ?? self.policy

        for attempt in 0..<policy.maxAttempts {
            do {
                return try await execute()
            } catch {
                if !Self.shouldRetry(error, policy: policy) || attempt >= policy.maxAttempts - 1 {
                    throw error
                }

                let delay = Self.calculateDelay(for: attempt, error: error, policy: policy)
                try await sleepFunction(delay)
            }
        }

        throw RetryInterceptorError.maxAttemptsExceeded
    }

    // MARK: - Private Methods
    private static func calculateDelay(for attempt: Int, error: Error, policy: RetryPolicy) -> TimeInterval {
        let statusCode: HTTPStatusCode?

        if let responseError = error as? NetworkResponseError {
            statusCode = responseError.httpStatusCode
        } else {
            statusCode = nil
        }

        return policy.delay(for: attempt, statusCode: statusCode)
    }

    private static func shouldRetry(_ error: Error, policy: RetryPolicy) -> Bool {
        if let urlError = error as? URLError {
            return policy.shouldRetry(error: urlError)
        }

        if case .transport(let urlError) = error as? NetworkClientError {
            return policy.shouldRetry(error: urlError)
        }

        if let responseError = error as? NetworkResponseError {
            return policy.shouldRetry(statusCode: responseError.httpStatusCode)
        }

        return false
    }
}
