import Testing
import Foundation
@testable import CoreKitNetwork

@Suite("ConnectionType")
struct ConnectionTypeTests {

    @Test("All ConnectionType cases return correct descriptions")
    func descriptions() {
        #expect(ConnectionType.wifi.description == "Wi-Fi")
        #expect(ConnectionType.cellular.description == "Cellular")
        #expect(ConnectionType.ethernet.description == "Ethernet")
        #expect(ConnectionType.unknown.description == "Unknown")
    }
}
