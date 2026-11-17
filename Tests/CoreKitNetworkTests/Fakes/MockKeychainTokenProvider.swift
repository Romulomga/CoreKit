import Foundation
import os
@testable import CoreKitNetwork

final class MockKeychainTokenProvider: TokenProvider {

    private struct State {
        var accessToken: String?
        var getAccessTokenCallCount = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    init(accessToken: String? = "mock-access-token") {
        state = OSAllocatedUnfairLock(initialState: State(accessToken: accessToken))
    }

    var getAccessTokenCallCount: Int {
        state.withLock { $0.getAccessTokenCallCount }
    }

    func getAccessToken() async throws -> String {
        let token = state.withLock { state in
            state.getAccessTokenCallCount += 1
            return state.accessToken
        }
        guard let token else { throw MockTokenError.noValue }
        return token
    }

    enum MockTokenError: Error {
        case forced
        case noValue
    }
}
