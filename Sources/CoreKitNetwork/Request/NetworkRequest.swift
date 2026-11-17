import Foundation

struct NetworkRequest: Sendable {
    
    // MARK: - Properties
    let baseURL: URL
    let path: String
    let method: HTTPMethod
    let headers: [String: String]
    let queryParameters: [String: String]?
    let body: (any Encodable & Sendable)?
    let bodyEncoding: BodyEncoding
    let timeout: TimeInterval
    let cachePolicy: URLRequest.CachePolicy
    
    var url: URL? {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        
        if let queryParameters = queryParameters, !queryParameters.isEmpty {
            components?.setQueryItemsEncodingPlus(queryParameters.map { key, value in
                URLQueryItem(name: key, value: value)
            })
        }
        
        return components?.url
    }
    
    // MARK: - Initializers
    init(
        baseURL: URL,
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        queryParameters: [String: String]? = nil,
        body: (any Encodable & Sendable)? = nil,
        bodyEncoding: BodyEncoding = .json,
        timeout: TimeInterval = 40.0,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
    ) {
        self.baseURL = baseURL
        self.path = path
        self.method = method
        self.headers = headers
        self.queryParameters = queryParameters
        self.body = body
        self.bodyEncoding = bodyEncoding
        self.timeout = timeout
        self.cachePolicy = cachePolicy
    }
    
    // MARK: - Public Methods
    func withHeader(_ key: String, value: String) -> NetworkRequest {
        var newHeaders = headers
        newHeaders[key] = value
        
        return NetworkRequest(
            baseURL: baseURL,
            path: path,
            method: method,
            headers: newHeaders,
            queryParameters: queryParameters,
            body: body,
            bodyEncoding: bodyEncoding,
            timeout: timeout,
            cachePolicy: cachePolicy
        )
    }
    
    func withHeaders(_ newHeaders: [String: String]) -> NetworkRequest {
        var mergedHeaders = headers
        newHeaders.forEach { mergedHeaders[$0.key] = $0.value }
        
        return NetworkRequest(
            baseURL: baseURL,
            path: path,
            method: method,
            headers: mergedHeaders,
            queryParameters: queryParameters,
            body: body,
            bodyEncoding: bodyEncoding,
            timeout: timeout,
            cachePolicy: cachePolicy
        )
    }
    
    func withTimeout(_ timeout: TimeInterval) -> NetworkRequest {
        NetworkRequest(
            baseURL: baseURL,
            path: path,
            method: method,
            headers: headers,
            queryParameters: queryParameters,
            body: body,
            bodyEncoding: bodyEncoding,
            timeout: timeout,
            cachePolicy: cachePolicy
        )
    }
}
