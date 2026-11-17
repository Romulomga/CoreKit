import Foundation

public enum NetworkClientError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case encodingFailed
    case decodingFailed(String)
    case requestCancelled
    case transport(URLError)
    case unauthorized

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .encodingFailed:
            return "Failed to encode request body"
        case .decodingFailed(let description):
            return "Failed to decode response: \(description)"
        case .requestCancelled:
            return "Request was cancelled"
        case .transport(let error):
            return error.localizedDescription
        case .unauthorized:
            return "Authentication failed after token refresh"
        }
    }
}
