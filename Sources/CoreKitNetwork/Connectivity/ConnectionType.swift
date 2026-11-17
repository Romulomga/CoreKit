import Foundation

public enum ConnectionType: Sendable {
    case wifi
    case cellular
    case ethernet
    case unknown
    
    public var description: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return "Cellular"
        case .ethernet:
            return "Ethernet"
        case .unknown:
            return "Unknown"
        }
    }
}
