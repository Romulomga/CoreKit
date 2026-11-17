import Testing
import Foundation
@testable import CoreKitNetwork

@Suite("NetworkResponse")
struct NetworkResponseTests {

    // MARK: - Helpers

    private func makeResponse(
        statusCode: Int,
        data: Data = Data(),
        headers: [String: String] = [:],
        duration: TimeInterval = 0.1
    ) -> NetworkResponse<EmptyResponse> {
        let request = URLRequest(url: URL(string: "https://example.com")!)
        return NetworkResponse<EmptyResponse>(
            data: data,
            statusCode: HTTPStatusCode(rawValue: statusCode),
            headers: headers,
            request: request,
            duration: duration
        )
    }

    // MARK: - Status classification

    @Test("isSuccessful is true for 200")
    func isSuccessfulFor200() {
        let response = makeResponse(statusCode: 200)
        #expect(response.isSuccessful == true)
        #expect(response.isClientError == false)
        #expect(response.isServerError == false)
    }

    @Test("isSuccessful is true for 299")
    func isSuccessfulFor299() {
        let response = makeResponse(statusCode: 299)
        #expect(response.isSuccessful == true)
    }

    @Test("isSuccessful is false for 300")
    func isNotSuccessfulFor300() {
        let response = makeResponse(statusCode: 300)
        #expect(response.isSuccessful == false)
    }

    @Test("isClientError is true for 400")
    func isClientErrorFor400() {
        let response = makeResponse(statusCode: 400)
        #expect(response.isClientError == true)
        #expect(response.isSuccessful == false)
    }

    @Test("isClientError is true for 499")
    func isClientErrorFor499() {
        let response = makeResponse(statusCode: 499)
        #expect(response.isClientError == true)
    }

    @Test("isServerError is true for 500")
    func isServerErrorFor500() {
        let response = makeResponse(statusCode: 500)
        #expect(response.isServerError == true)
        #expect(response.isSuccessful == false)
    }

    @Test("isServerError is true for 599")
    func isServerErrorFor599() {
        let response = makeResponse(statusCode: 599)
        #expect(response.isServerError == true)
    }

    // MARK: - Validate

    @Test("validate succeeds for 200")
    func validateSucceeds() throws {
        let response = makeResponse(statusCode: 200)
        #expect(throws: Never.self) {
            try response.validate()
        }
    }

    @Test("validate throws NetworkResponseError for 404")
    func validateThrowsForError() {
        let response = makeResponse(statusCode: 404)
        #expect(throws: NetworkResponseError.self) {
            try response.validate()
        }
    }

    @Test("validate throws .unauthorized for 401")
    func validateThrowsUnauthorized() {
        let response = makeResponse(statusCode: 401)
        do {
            try response.validate()
            Issue.record("Expected validate() to throw")
        } catch let error as NetworkResponseError {
            if case .unauthorized = error {} else {
                Issue.record("Expected .unauthorized, got \(error)")
            }
        } catch {
            Issue.record("Expected NetworkResponseError, got \(error)")
        }
    }

    @Test("validate throws .badRequest for 400")
    func validateThrowsBadRequest() {
        let response = makeResponse(statusCode: 400)
        do {
            try response.validate()
            Issue.record("Expected validate() to throw")
        } catch let error as NetworkResponseError {
            if case .badRequest = error {} else {
                Issue.record("Expected .badRequest, got \(error)")
            }
        } catch {
            Issue.record("Expected NetworkResponseError, got \(error)")
        }
    }

    @Test("validate throws .internalServerError for 500")
    func validateThrowsInternalServerError() {
        let response = makeResponse(statusCode: 500)
        do {
            try response.validate()
            Issue.record("Expected validate() to throw")
        } catch let error as NetworkResponseError {
            if case .internalServerError = error {} else {
                Issue.record("Expected .internalServerError, got \(error)")
            }
        } catch {
            Issue.record("Expected NetworkResponseError, got \(error)")
        }
    }

    @Test("validate passes error message from response data")
    func validatePassesErrorMessage() {
        let json = #"{"message": "User not found"}"#.data(using: .utf8)!
        let response = makeResponse(statusCode: 404, data: json)
        do {
            try response.validate()
            Issue.record("Expected validate() to throw")
        } catch let error as NetworkResponseError {
            #expect(error.errorDescription == "User not found")
        } catch {
            Issue.record("Expected NetworkResponseError, got \(error)")
        }
    }

    // MARK: - Properties

    @Test("Response preserves data, headers, and duration")
    func responsePreservesProperties() {
        let data = Data("test".utf8)
        let response = makeResponse(statusCode: 200, data: data, headers: ["X-Id": "1"], duration: 1.5)

        #expect(response.data == data)
        #expect(response.headers["X-Id"] == "1")
        #expect(response.duration == 1.5)
    }

    @Test("decodedBody is nil by default")
    func decodedBodyIsNilByDefault() {
        let response = makeResponse(statusCode: 200)
        #expect(response.decodedBody == nil)
    }
}
