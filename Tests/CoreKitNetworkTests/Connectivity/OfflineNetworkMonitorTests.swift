@testable import CoreKitNetwork
import Testing

@Suite struct OfflineNetworkMonitorTests {

    @Test func itNeverSeesTheNetwork() {
        let monitor = OfflineNetworkMonitor()

        monitor.start()

        #expect(!monitor.isConnected)
        #expect(monitor.connectionType == .unknown)
        #expect(throws: NetworkMonitorError.notConnected) { try monitor.requireConnection() }

        monitor.stop()

        #expect(!monitor.isConnected)
    }
}
