import Foundation

public enum NetworkResponseError: LocalizedError, Sendable {
    case badRequest(String?)
    case unauthorized(String?)
    case forbidden(String?)
    case notFound(String?)
    case conflict(String?)
    case unprocessableEntity(String?)
    case tooManyRequests(String?)
    case internalServerError(String?)
    case serviceUnavailable(String?)
    case unknown(statusCode: Int, message: String?)
    
    public var errorDescription: String? {
        switch self {
        case .badRequest(let message):
            return message ?? "Bad Request (400)"
        case .unauthorized(let message):
            return message ?? "Unauthorized (401)"
        case .forbidden(let message):
            return message ?? "Forbidden (403)"
        case .notFound(let message):
            return message ?? "Not Found (404)"
        case .conflict(let message):
            return message ?? "Conflict (409)"
        case .unprocessableEntity(let message):
            return message ?? "Unprocessable Entity (422)"
        case .tooManyRequests(let message):
            return message ?? "Too Many Requests (429)"
        case .internalServerError(let message):
            return message ?? "Internal Server Error (500)"
        case .serviceUnavailable(let message):
            return message ?? "Service Unavailable (503)"
        case .unknown(let statusCode, let message):
            return message ?? "Error (\(statusCode))"
        }
    }
    
    public var httpStatusCode: HTTPStatusCode {
        switch self {
        case .badRequest: return HTTPStatusCode(rawValue: 400)
        case .unauthorized: return HTTPStatusCode(rawValue: 401)
        case .forbidden: return HTTPStatusCode(rawValue: 403)
        case .notFound: return HTTPStatusCode(rawValue: 404)
        case .conflict: return HTTPStatusCode(rawValue: 409)
        case .unprocessableEntity: return HTTPStatusCode(rawValue: 422)
        case .tooManyRequests: return HTTPStatusCode(rawValue: 429)
        case .internalServerError: return HTTPStatusCode(rawValue: 500)
        case .serviceUnavailable: return HTTPStatusCode(rawValue: 503)
        case .unknown(let statusCode, _): return HTTPStatusCode(rawValue: statusCode)
        }
    }

    public static func from(statusCode: HTTPStatusCode, data: Data) -> NetworkResponseError {
        let message = parseErrorMessage(from: data)
        
        switch statusCode.rawValue {
        case 400:
            return .badRequest(message)
        case 401:
            return .unauthorized(message)
        case 403:
            return .forbidden(message)
        case 404:
            return .notFound(message)
        case 409:
            return .conflict(message)
        case 422:
            return .unprocessableEntity(message)
        case 429:
            return .tooManyRequests(message)
        case 500:
            return .internalServerError(message)
        case 503:
            return .serviceUnavailable(message)
        default:
            return .unknown(statusCode: statusCode.rawValue, message: message)
        }
    }
    
    private static func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }

        let knownKeys = ["title", "detail", "message", "error", "error_description", "errorMessage"]
        for key in knownKeys {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }

        return nil
    }
}
