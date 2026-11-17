import Foundation
import os
@testable import CoreKitNetwork

final class MockTokenRefresher: TokenRefresher {

    private struct State {
        var refreshCallCount = 0
        var error: (any Error)?
        var onRefresh: (@Sendable (URLSession) async throws -> Void)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var refreshCallCount: Int {
        state.withLock { $0.refreshCallCount }
    }

    var error: (any Error)? {
        get { state.withLock { $0.error } }
        set { state.withLock { $0.error = newValue } }
    }

    var onRefresh: (@Sendable (URLSession) async throws -> Void)? {
        get { state.withLock { $0.onRefresh } }
        set { state.withLock { $0.onRefresh = newValue } }
    }

    func refresh(using session: URLSession) async throws {
        let (error, onRefresh) = state.withLock { state in
            state.refreshCallCount += 1
            return (state.error, state.onRefresh)
        }
        if let error { throw error }
        try await onRefresh?(session)
    }
}
