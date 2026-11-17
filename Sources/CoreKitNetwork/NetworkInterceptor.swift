import Foundation

public protocol NetworkInterceptor: Sendable {
    func intercept(request: URLRequest) async throws -> URLRequest
    func intercept<T: Decodable>(response: inout NetworkResponse<T>) async throws
}

public extension NetworkInterceptor {
    func intercept(request: URLRequest) async throws -> URLRequest {
        return request
    }
    
    func intercept<T: Decodable>(response: inout NetworkResponse<T>) async throws {
    }
}
