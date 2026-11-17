import Foundation
import os
@testable import CoreKitNetwork

final class MockNetworkMonitor: NetworkMonitoring {

    private struct State {
        var isConnected: Bool
        var connectionType: ConnectionType
        var startCallCount = 0
        var stopCallCount = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    var isConnected: Bool {
        state.withLock { $0.isConnected }
    }

    var connectionType: ConnectionType {
        state.withLock { $0.connectionType }
    }

    var startCallCount: Int {
        state.withLock { $0.startCallCount }
    }

    var stopCallCount: Int {
        state.withLock { $0.stopCallCount }
    }

    init(isConnected: Bool = true, connectionType: ConnectionType = .wifi) {
        state = OSAllocatedUnfairLock(initialState: State(isConnected: isConnected, connectionType: connectionType))
    }

    func start() {
        state.withLock { $0.startCallCount += 1 }
    }

    func stop() {
        state.withLock { $0.stopCallCount += 1 }
    }

    func requireConnection() throws {
        guard isConnected else {
            throw NetworkMonitorError.notConnected
        }
    }
}
