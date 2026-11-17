import Foundation

public protocol NetworkMonitoring: Sendable {
    var isConnected: Bool { get }
    var connectionType: ConnectionType { get }
    func start()
    func stop()
    func requireConnection() throws
}
