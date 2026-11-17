import Foundation

/// `retryPolicy` overrides the service's policy for one request (`nil` keeps it): a read with a
/// side effect on the server passes `RetryPolicy.none`, spelled out: a bare `.none` is `Optional.none`
/// (nil, the service policy) and the request would be retried.
public protocol NetworkServing: Sendable {

    @discardableResult
    func request<Response: Decodable & Sendable>(
        path: String,
        method: HTTPMethod,
        headers: [String: String],
        queryParameters: [String: String]?,
        body: (any Encodable & Sendable)?,
        retryPolicy: RetryPolicy?,
        responseType: Response.Type
    ) async throws -> Response

    func request(
        path: String,
        method: HTTPMethod,
        headers: [String: String],
        queryParameters: [String: String]?,
        body: (any Encodable & Sendable)?,
        retryPolicy: RetryPolicy?
    ) async throws

    func requestWithResponse<Response: Decodable & Sendable>(
        path: String,
        method: HTTPMethod,
        headers: [String: String],
        queryParameters: [String: String]?,
        body: (any Encodable & Sendable)?,
        retryPolicy: RetryPolicy?,
        responseType: Response.Type
    ) async throws -> NetworkResponse<Response>
}

// MARK: - Default Parameters
public extension NetworkServing {

    @discardableResult
    func request<Response: Decodable & Sendable>(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        queryParameters: [String: String]? = nil,
        body: (any Encodable & Sendable)? = nil,
        retryPolicy: RetryPolicy? = nil,
        responseType: Response.Type
    ) async throws -> Response {
        try await request(
            path: path,
            method: method,
            headers: headers,
            queryParameters: queryParameters,
            body: body,
            retryPolicy: retryPolicy,
            responseType: responseType
        )
    }

    func request(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        queryParameters: [String: String]? = nil,
        body: (any Encodable & Sendable)? = nil,
        retryPolicy: RetryPolicy? = nil
    ) async throws {
        try await request(
            path: path,
            method: method,
            headers: headers,
            queryParameters: queryParameters,
            body: body,
            retryPolicy: retryPolicy
        )
    }

    func requestWithResponse<Response: Decodable & Sendable>(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        queryParameters: [String: String]? = nil,
        body: (any Encodable & Sendable)? = nil,
        retryPolicy: RetryPolicy? = nil,
        responseType: Response.Type
    ) async throws -> NetworkResponse<Response> {
        try await requestWithResponse(
            path: path,
            method: method,
            headers: headers,
            queryParameters: queryParameters,
            body: body,
            retryPolicy: retryPolicy,
            responseType: responseType
        )
    }
}
