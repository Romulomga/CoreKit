import Foundation
import Network
import os

public final class NetworkMonitor: NetworkMonitoring, Sendable {

    // MARK: - Properties

    private let queue: DispatchQueue

    private struct State: Sendable {
        var monitor: NWPathMonitor?
        var isConnected: Bool = true
        var connectionType: ConnectionType = .unknown
        var onStatusChange: (@Sendable (Bool, ConnectionType) -> Void)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public var isConnected: Bool {
        state.withLock { $0.isConnected }
    }

    public var connectionType: ConnectionType {
        state.withLock { $0.connectionType }
    }

    public func setOnStatusChange(_ handler: (@Sendable (Bool, ConnectionType) -> Void)?) {
        state.withLock { $0.onStatusChange = handler }
    }

    // MARK: - Initializers
    public init() {
        self.queue = DispatchQueue(label: "corekit.network.monitor", qos: .utility)
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// Starts once; later calls (the app starts the same monitor from three places) change nothing.
    /// Connectivity stays optimistic until the first path update: the `currentPath` of a monitor
    /// that has not started yet reads as unsatisfied, and the launch requests failed as offline.
    public func start() {
        let newMonitor = NWPathMonitor()

        newMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            let isConnected = path.status == .satisfied
            let connectionType = self.determineConnectionType(from: path)

            let callback = self.state.withLock {
                $0.isConnected = isConnected
                $0.connectionType = connectionType
                return $0.onStatusChange
            }

            callback?(isConnected, connectionType)
        }

        let isRunning = state.withLock { state in
            guard state.monitor == nil else { return true }
            state.monitor = newMonitor
            return false
        }
        guard !isRunning else { return }

        newMonitor.start(queue: queue)
    }

    public func stop() {
        state.withLock { state in
            state.monitor?.cancel()
            state.monitor = nil
        }
    }

    public func requireConnection() throws {
        guard isConnected else {
            throw NetworkMonitorError.notConnected
        }
    }

    // MARK: - Private Methods

    private func determineConnectionType(from path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else {
            return .unknown
        }
    }
}
