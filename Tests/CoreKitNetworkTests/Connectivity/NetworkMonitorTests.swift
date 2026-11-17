import Testing
import Foundation
@testable import CoreKitNetwork

@Suite("NetworkMonitor")
struct NetworkMonitorTests {

    // MARK: - Error description

    @Test("NetworkMonitorError.notConnected has correct errorDescription")
    func notConnectedErrorDescription() {
        #expect(NetworkMonitorError.notConnected.errorDescription == "No network connection available")
    }

    // MARK: - Default state

    @Test("Default connectionType is .unknown before start")
    func defaultConnectionType() {
        let monitor = NetworkMonitor()
        #expect(monitor.connectionType == .unknown)
    }

    @Test("Default isConnected is true before start")
    func defaultIsConnected() {
        let monitor = NetworkMonitor()
        #expect(monitor.isConnected == true)
    }

    // MARK: - Lifecycle

    @Test("start() and stop() lifecycle completes without crash")
    func startAndStopLifecycle() {
        let monitor = NetworkMonitor()
        monitor.start()
        monitor.stop()
    }

    @Test("Calling stop() without start() does not crash")
    func stopWithoutStart() {
        let monitor = NetworkMonitor()
        monitor.stop()
    }

    @Test("Calling start() multiple times does not crash")
    func multipleStartCalls() {
        let monitor = NetworkMonitor()
        monitor.start()
        monitor.start()
        monitor.stop()
    }

    // MARK: - requireConnection

    @Test("requireConnection does not throw when isConnected is true")
    func requireConnectionSucceedsWhenConnected() {
        let monitor = NetworkMonitor()
        // Default isConnected is true before start
        #expect(throws: Never.self) {
            try monitor.requireConnection()
        }
    }

    // MARK: - onStatusChange callback

    @Test("setOnStatusChange accepts a handler without crash")
    func setOnStatusChangeAcceptsHandler() {
        let monitor = NetworkMonitor()
        monitor.setOnStatusChange { _, _ in }
        monitor.setOnStatusChange(nil)
    }

    // MARK: - NetworkMonitoring conformance

    @Test("NetworkMonitor conforms to NetworkMonitoring protocol")
    func conformsToProtocol() {
        let monitor: NetworkMonitoring = NetworkMonitor()
        #expect(monitor.connectionType == .unknown)
    }
}
