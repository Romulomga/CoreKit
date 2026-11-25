import Foundation

/// A monitor that always says there is no network: the debug flag that shows how a screen behaves offline (the
/// simulator has no airplane mode from the command line). Twin of the CoreKit-Android `OfflineNetworkMonitor`.
public struct OfflineNetworkMonitor: NetworkMonitoring {

    public init() {}

    public var isConnected: Bool { false }

    public var connectionType: ConnectionType { .unknown }

    public func start() {}

    public func stop() {}

    public func requireConnection() throws {
        throw NetworkMonitorError.notConnected
    }
}
