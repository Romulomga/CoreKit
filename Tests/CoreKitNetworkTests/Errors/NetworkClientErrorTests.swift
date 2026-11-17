import Testing
import Foundation
@testable import CoreKitNetwork

@Suite("NetworkClientError")
struct NetworkClientErrorTests {

    @Test("invalidURL returns 'Invalid URL'")
    func invalidURLDescription() {
        #expect(NetworkClientError.invalidURL.errorDescription == "Invalid URL")
    }

    @Test("invalidResponse returns 'Invalid response from server'")
    func invalidResponseDescription() {
        #expect(NetworkClientError.invalidResponse.errorDescription == "Invalid response from server")
    }

    @Test("encodingFailed returns 'Failed to encode request body'")
    func encodingFailedDescription() {
        #expect(NetworkClientError.encodingFailed.errorDescription == "Failed to encode request body")
    }

    @Test("decodingFailed includes the provided description")
    func decodingFailedDescription() {
        let error = NetworkClientError.decodingFailed("missing key")
        #expect(error.errorDescription == "Failed to decode response: missing key")
    }

    @Test("requestCancelled returns 'Request was cancelled'")
    func requestCancelledDescription() {
        #expect(NetworkClientError.requestCancelled.errorDescription == "Request was cancelled")
    }

    @Test("transport delegates to URLError's localizedDescription")
    func transportDescription() {
        let error = NetworkClientError.transport(URLError(.timedOut))
        #expect(error.errorDescription != nil)
    }

    @Test("unauthorized returns 'Authentication failed after token refresh'")
    func unauthorizedDescription() {
        #expect(NetworkClientError.unauthorized.errorDescription == "Authentication failed after token refresh")
    }
}
