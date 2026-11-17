import Testing
import Foundation
@testable import CoreKitNetwork

@Suite("NetworkRequest")
struct NetworkRequestTests {

    private let baseURL = URL(string: "https://api.example.com")!

    // MARK: - URL Construction

    @Test("URL construction with base URL and path produces correct absolute string")
    func urlConstructionBasic() {
        let request = NetworkRequest(baseURL: baseURL, path: "v1/users")

        #expect(request.url?.absoluteString == "https://api.example.com/v1/users")
    }

    @Test("URL with query parameters includes all parameters")
    func urlWithQueryParameters() {
        let request = NetworkRequest(
            baseURL: baseURL,
            path: "v1/users",
            queryParameters: ["page": "1", "limit": "10"]
        )

        let urlString = request.url?.absoluteString ?? ""
        #expect(urlString.contains("page=1"))
        #expect(urlString.contains("limit=10"))
    }

    @Test("A plus sign in a query value is percent-encoded, not read as a space")
    func queryPlusIsPercentEncoded() {
        let request = NetworkRequest(
            baseURL: baseURL,
            path: "v1/posts",
            queryParameters: ["sort": "+pricePerSquareMeter", "phone": "+5521999998888", "term": "a b"]
        )

        let query = request.url?.query(percentEncoded: true) ?? ""
        #expect(query.contains("sort=%2BpricePerSquareMeter"))
        #expect(query.contains("phone=%2B5521999998888"))
        #expect(query.contains("term=a%20b"))
        #expect(!query.contains("+"))
    }

    @Test("URL without query parameters has no query string")
    func urlWithoutQueryParameters() {
        let request = NetworkRequest(baseURL: baseURL, path: "v1/users")

        #expect(request.url?.absoluteString == "https://api.example.com/v1/users")
    }

    // MARK: - Default Values

    @Test("Default values are set correctly when only baseURL and path are provided")
    func defaultValues() {
        let request = NetworkRequest(baseURL: baseURL, path: "v1/users")

        #expect(request.method == .get)
        #expect(request.headers.isEmpty)
        #expect(request.queryParameters == nil)
        #expect(request.bodyEncoding == .json)
        #expect(request.timeout == 40.0)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    // MARK: - withHeader

    @Test("withHeader adds a new header to the request")
    func withHeaderAddsHeader() {
        let request = NetworkRequest(baseURL: baseURL, path: "v1/users")
        let updated = request.withHeader("X-Custom", value: "test")

        #expect(updated.headers["X-Custom"] == "test")
    }

    @Test("withHeader preserves existing headers")
    func withHeaderPreservesExistingHeaders() {
        let request = NetworkRequest(baseURL: baseURL, path: "v1/users", headers: ["A": "1"])
        let updated = request.withHeader("B", value: "2")

        #expect(updated.headers["A"] == "1")
        #expect(updated.headers["B"] == "2")
    }

    // MARK: - withHeaders

    @Test("withHeaders merges new headers with existing ones")
    func withHeadersMerges() {
        let request = NetworkRequest(baseURL: baseURL, path: "v1/users", headers: ["A": "1"])
        let updated = request.withHeaders(["B": "2", "C": "3"])

        #expect(updated.headers["A"] == "1")
        #expect(updated.headers["B"] == "2")
        #expect(updated.headers["C"] == "3")
    }

    @Test("withHeaders overrides existing header values")
    func withHeadersOverridesExisting() {
        let request = NetworkRequest(baseURL: baseURL, path: "v1/users", headers: ["A": "1"])
        let updated = request.withHeaders(["A": "2"])

        #expect(updated.headers["A"] == "2")
    }

    // MARK: - withTimeout

    @Test("withTimeout sets the new timeout value")
    func withTimeoutSetsTimeout() {
        let request = NetworkRequest(baseURL: baseURL, path: "v1/users")
        let updated = request.withTimeout(120)

        #expect(updated.timeout == 120)
    }

    @Test("withTimeout preserves other properties")
    func withTimeoutPreservesOtherProperties() {
        let request = NetworkRequest(baseURL: baseURL, path: "v1/users", method: .post)
        let updated = request.withTimeout(60)

        #expect(updated.method == .post)
    }
}
