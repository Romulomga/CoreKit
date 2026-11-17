import Foundation

public enum NetworkMonitorError: LocalizedError {
    case notConnected
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No network connection available"
        }
    }
}
