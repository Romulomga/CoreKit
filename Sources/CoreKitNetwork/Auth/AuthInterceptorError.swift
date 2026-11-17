import Foundation

public enum AuthInterceptorError: LocalizedError, Equatable {
    case refreshNotConfigured
    case tokenRefreshed
    case tokenUnavailable

    public var errorDescription: String? {
        switch self {
        case .refreshNotConfigured:
            return "Token refresher is not configured"
        case .tokenRefreshed:
            return "Token was refreshed successfully"
        case .tokenUnavailable:
            return "Failed to retrieve access token"
        }
    }
}
