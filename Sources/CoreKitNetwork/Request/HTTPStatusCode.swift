import Foundation

public struct HTTPStatusCode: Sendable, Equatable, CustomStringConvertible {
    
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let ok = HTTPStatusCode(rawValue: 200)
    public static let created = HTTPStatusCode(rawValue: 201)
    public static let accepted = HTTPStatusCode(rawValue: 202)
    public static let noContent = HTTPStatusCode(rawValue: 204)
    
    public static let badRequest = HTTPStatusCode(rawValue: 400)
    public static let unauthorized = HTTPStatusCode(rawValue: 401)
    public static let forbidden = HTTPStatusCode(rawValue: 403)
    public static let notFound = HTTPStatusCode(rawValue: 404)
    public static let methodNotAllowed = HTTPStatusCode(rawValue: 405)
    public static let conflict = HTTPStatusCode(rawValue: 409)
    public static let unprocessableEntity = HTTPStatusCode(rawValue: 422)
    public static let tooManyRequests = HTTPStatusCode(rawValue: 429)
    
    public static let internalServerError = HTTPStatusCode(rawValue: 500)
    public static let badGateway = HTTPStatusCode(rawValue: 502)
    public static let serviceUnavailable = HTTPStatusCode(rawValue: 503)
    public static let gatewayTimeout = HTTPStatusCode(rawValue: 504)
    
    public var isInformational: Bool {
        (100...199).contains(rawValue)
    }
    
    public var isSuccess: Bool {
        (200...299).contains(rawValue)
    }
    
    public var isRedirection: Bool {
        (300...399).contains(rawValue)
    }
    
    public var isClientError: Bool {
        (400...499).contains(rawValue)
    }
    
    public var isServerError: Bool {
        (500...599).contains(rawValue)
    }
    
    public var description: String {
        "\(rawValue) - \(message)"
    }
    
    private var message: String {
        switch rawValue {
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 422: return "Unprocessable Entity"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return "Unknown"
        }
    }
}
