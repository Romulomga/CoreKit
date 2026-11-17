import Foundation

public struct NetworkResponse<T: Decodable & Sendable>: Sendable {
    
    // MARK: - Properties
    public let data: Data
    public let statusCode: HTTPStatusCode
    public let headers: [String: String]
    public let request: URLRequest
    public let duration: TimeInterval
    public var decodedBody: T?

    public var isSuccessful: Bool {
        statusCode.isSuccess
    }
    
    public var isClientError: Bool {
        statusCode.isClientError
    }
    
    public var isServerError: Bool {
        statusCode.isServerError
    }
    
    // MARK: - Initializers
    public init(
        data: Data,
        statusCode: HTTPStatusCode,
        headers: [String: String],
        request: URLRequest,
        duration: TimeInterval = 0,
        decodedBody: T? = nil
    ) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
        self.request = request
        self.duration = duration
        self.decodedBody = decodedBody
    }
    
    // MARK: - Public Methods
    public func validate() throws {
        guard isSuccessful else {
            throw NetworkResponseError.from(statusCode: statusCode, data: data)
        }
    }
}
