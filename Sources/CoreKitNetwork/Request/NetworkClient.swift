import Foundation
import os

internal final class NetworkClient: Sendable {

    // MARK: - Properties
    private let session: URLSession
    private let codec: OSAllocatedUnfairLock<CodecState>
    private let interceptors: [NetworkInterceptor]
    private let taskManager = TaskManager()
    private static let maxTokenRefreshRetries = 1

    private final class CodecState: Sendable {
        let decoder: JSONDecoder
        let encoder: JSONEncoder

        init(decoder: JSONDecoder, encoder: JSONEncoder) {
            self.decoder = decoder
            self.encoder = encoder
        }
    }

    // MARK: - Task Manager Actor
    private actor TaskManager {
        private var activeCancellations: [UUID: @Sendable () -> Void] = [:]

        func register(_ id: UUID, cancel: @escaping @Sendable () -> Void) {
            activeCancellations[id] = cancel
        }

        func remove(_ id: UUID) {
            activeCancellations.removeValue(forKey: id)
        }

        func cancelAll() {
            activeCancellations.values.forEach { $0() }
            activeCancellations.removeAll()
        }
    }

    // MARK: - Initializers
    init(
        session: URLSession,
        decoder: JSONDecoder? = nil,
        encoder: JSONEncoder? = nil,
        interceptors: [NetworkInterceptor] = []
    ) {
        self.session = session
        self.codec = OSAllocatedUnfairLock(
            initialState: CodecState(
                decoder: decoder ?? NetworkClient.defaultDecoder(),
                encoder: encoder ?? NetworkClient.defaultEncoder()
            )
        )
        self.interceptors = interceptors
    }

    // MARK: - Public Methods
    @discardableResult
    func request<T: Decodable>(
        _ endpoint: NetworkRequest,
        responseType: T.Type
    ) async throws -> NetworkResponse<T> {
        let taskId = UUID()

        let innerTask = Task {
            try await self.performRequest(endpoint, responseType: responseType, taskId: taskId)
        }

        await taskManager.register(taskId) { innerTask.cancel() }

        return try await withTaskCancellationHandler {
            defer { Task { await self.taskManager.remove(taskId) } }
            return try await innerTask.value
        } onCancel: {
            innerTask.cancel()
            Task { await self.taskManager.remove(taskId) }
        }
    }

    @discardableResult
    func request(_ endpoint: NetworkRequest) async throws -> NetworkResponse<EmptyResponse> {
        try await request(endpoint, responseType: EmptyResponse.self)
    }

    func buildURLRequest(from endpoint: NetworkRequest) throws -> URLRequest {
        guard let url = endpoint.url else {
            throw NetworkClientError.invalidURL
        }

        var request = URLRequest(
            url: url,
            cachePolicy: endpoint.cachePolicy,
            timeoutInterval: endpoint.timeout
        )

        request.httpMethod = endpoint.method.rawValue

        endpoint.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body = endpoint.body {
            switch endpoint.bodyEncoding {
            case .json:
                request.httpBody = try codec.withLock { state in
                    try state.encoder.encode(body)
                }
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            case .urlEncoded:
                request.httpBody = try encodeURLParameters(body)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                }
            }
        }

        return request
    }

    func cancelAllRequests() async {
        await taskManager.cancelAll()
    }

    // MARK: - Private Methods
    private func performRequest<T: Decodable>(
        _ endpoint: NetworkRequest,
        responseType: T.Type,
        taskId: UUID,
        refreshAttempt: Int = 0
    ) async throws -> NetworkResponse<T> {
        try Task.checkCancellation()

        var request = try buildURLRequest(from: endpoint)
        for interceptor in interceptors {
            request = try await interceptor.intercept(request: request)
        }

        let start = Date()

        let (data, urlResponse): (Data, URLResponse)

        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch is CancellationError {
            throw NetworkClientError.requestCancelled
        } catch let urlError as URLError {
            if urlError.code == .cancelled {
                throw NetworkClientError.requestCancelled
            }
            throw NetworkClientError.transport(urlError)
        }

        let duration = Date().timeIntervalSince(start)

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw NetworkClientError.invalidResponse
        }

        var response = NetworkResponse<T>(
            data: data,
            statusCode: HTTPStatusCode(rawValue: httpResponse.statusCode),
            headers: httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                if let key = entry.key as? String {
                    result[key] = "\(entry.value)"
                }
            },
            request: request,
            duration: duration
        )

        do {
            // On the way back the order is reversed (an onion): the last one in on the request is the first out on
            // the response. Logging goes in last so it records the request with the auth header already set and,
            // reversed, it sees the response before the `AuthInterceptor` can throw `tokenRefreshed` on a 401.
            // Without that, a 401 never reaches the console.
            for interceptor in interceptors.reversed() {
                try await interceptor.intercept(response: &response)
            }

            try response.validate()

            if T.self == EmptyResponse.self {
                response.decodedBody = EmptyResponse() as? T
            } else {
                response.decodedBody = try codec.withLock { state in
                    try state.decoder.decode(T.self, from: data)
                }
            }

            return response
        } catch AuthInterceptorError.tokenRefreshed {
            guard refreshAttempt < Self.maxTokenRefreshRetries else {
                throw NetworkClientError.unauthorized
            }
            return try await performRequest(endpoint, responseType: responseType, taskId: taskId, refreshAttempt: refreshAttempt + 1)
        } catch let error as DecodingError {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "CoreKit", category: "Decoding")
                .error("Decoding failed: \(error.detailedDescription)")
            throw NetworkClientError.decodingFailed(error.detailedDescription)
        }
    }

    private func encodeURLParameters(_ parameters: any Encodable & Sendable) throws -> Data {
        let data = try codec.withLock { state in
            try state.encoder.encode(parameters)
        }
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkClientError.encodingFailed
        }

        var components = URLComponents()
        components.setQueryItemsEncodingPlus(dictionary.map { key, value in
            URLQueryItem(name: key, value: "\(value)")
        })

        guard let query = components.percentEncodedQuery else {
            throw NetworkClientError.encodingFailed
        }

        return query.data(using: .utf8) ?? Data()
    }

    // Format styles are Sendable values: no lock, no box (`ISO8601DateFormatter` is not Sendable).
    private static let isoStyle = Date.ISO8601FormatStyle()
    private static let isoFractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static func defaultDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            if let date = (try? isoStyle.parse(dateString)) ?? (try? isoFractionalStyle.parse(dateString)) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Could not parse date: \(dateString)"
            )
        }

        return decoder
    }

    private static func defaultEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

// MARK: - Empty Response
struct EmptyResponse: Codable, Sendable {
    internal init() {}
}
