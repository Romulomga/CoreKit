import Testing
import Foundation
@testable import CoreKitNetwork

@Suite("NetworkResponseError")
struct NetworkResponseErrorTests {

    // MARK: - Status code mapping

    @Test("Maps 400 to badRequest")
    func maps400() {
        if case .badRequest = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 400), data: Data()) {} else {
            Issue.record("Expected .badRequest")
        }
    }

    @Test("Maps 401 to unauthorized")
    func maps401() {
        if case .unauthorized = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 401), data: Data()) {} else {
            Issue.record("Expected .unauthorized")
        }
    }

    @Test("Maps 403 to forbidden")
    func maps403() {
        if case .forbidden = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 403), data: Data()) {} else {
            Issue.record("Expected .forbidden")
        }
    }

    @Test("Maps 404 to notFound")
    func maps404() {
        if case .notFound = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 404), data: Data()) {} else {
            Issue.record("Expected .notFound")
        }
    }

    @Test("Maps 409 to conflict")
    func maps409() {
        if case .conflict = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 409), data: Data()) {} else {
            Issue.record("Expected .conflict")
        }
    }

    @Test("Maps 422 to unprocessableEntity")
    func maps422() {
        if case .unprocessableEntity = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 422), data: Data()) {} else {
            Issue.record("Expected .unprocessableEntity")
        }
    }

    @Test("Maps 429 to tooManyRequests")
    func maps429() {
        if case .tooManyRequests = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 429), data: Data()) {} else {
            Issue.record("Expected .tooManyRequests")
        }
    }

    @Test("Maps 500 to internalServerError")
    func maps500() {
        if case .internalServerError = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 500), data: Data()) {} else {
            Issue.record("Expected .internalServerError")
        }
    }

    @Test("Maps 503 to serviceUnavailable")
    func maps503() {
        if case .serviceUnavailable = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 503), data: Data()) {} else {
            Issue.record("Expected .serviceUnavailable")
        }
    }

    @Test("Maps unknown status code to .unknown with correct rawValue")
    func mapsUnknown() {
        if case .unknown(let code, _) = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 418), data: Data()) {
            #expect(code == 418)
        } else {
            Issue.record("Expected .unknown")
        }
    }

    // MARK: - Error message parsing

    @Test("Parses message from 'title' key")
    func parsesTitle() {
        let json = #"{"title": "Title Error"}"#.data(using: .utf8)!
        let error = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 400), data: json)
        #expect(error.errorDescription == "Title Error")
    }

    @Test("Parses message from 'message' key")
    func parsesMessage() {
        let json = #"{"message": "Message Error"}"#.data(using: .utf8)!
        let error = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 400), data: json)
        #expect(error.errorDescription == "Message Error")
    }

    @Test("Parses message from 'error' key")
    func parsesError() {
        let json = #"{"error": "Error Field"}"#.data(using: .utf8)!
        let error = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 400), data: json)
        #expect(error.errorDescription == "Error Field")
    }

    @Test("Parses message from 'error_description' key")
    func parsesErrorDescription() {
        let json = #"{"error_description": "Desc"}"#.data(using: .utf8)!
        let error = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 400), data: json)
        #expect(error.errorDescription == "Desc")
    }

    @Test("Prefers 'title' over 'message' when both present")
    func prioritizesTitle() {
        let json = #"{"title": "Title", "message": "Message"}"#.data(using: .utf8)!
        let error = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 400), data: json)
        #expect(error.errorDescription == "Title")
    }

    @Test("Returns default description when JSON has no known keys")
    func unknownKeysDefaultDescription() {
        let json = #"{"foo": "bar"}"#.data(using: .utf8)!
        let error = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 400), data: json)
        #expect(error.errorDescription == "Bad Request (400)")
    }

    @Test("Falls back to raw string when data is not JSON")
    func fallsBackToRawString() {
        let data = "plain error text".data(using: .utf8)!
        let error = NetworkResponseError.from(statusCode: HTTPStatusCode(rawValue: 400), data: data)
        #expect(error.errorDescription == "plain error text")
    }

    // MARK: - httpStatusCode mapping

    @Test("httpStatusCode returns correct rawValue for all cases")
    func httpStatusCodeMapping() {
        #expect(NetworkResponseError.badRequest(nil).httpStatusCode.rawValue == 400)
        #expect(NetworkResponseError.unauthorized(nil).httpStatusCode.rawValue == 401)
        #expect(NetworkResponseError.forbidden(nil).httpStatusCode.rawValue == 403)
        #expect(NetworkResponseError.notFound(nil).httpStatusCode.rawValue == 404)
        #expect(NetworkResponseError.conflict(nil).httpStatusCode.rawValue == 409)
        #expect(NetworkResponseError.unprocessableEntity(nil).httpStatusCode.rawValue == 422)
        #expect(NetworkResponseError.tooManyRequests(nil).httpStatusCode.rawValue == 429)
        #expect(NetworkResponseError.internalServerError(nil).httpStatusCode.rawValue == 500)
        #expect(NetworkResponseError.serviceUnavailable(nil).httpStatusCode.rawValue == 503)
        #expect(NetworkResponseError.unknown(statusCode: 418, message: nil).httpStatusCode.rawValue == 418)
    }

    // MARK: - errorDescription fallback

    @Test("Uses default text when message is nil")
    func errorDescriptionFallback() {
        #expect(NetworkResponseError.badRequest(nil).errorDescription == "Bad Request (400)")
        #expect(NetworkResponseError.unauthorized(nil).errorDescription == "Unauthorized (401)")
        #expect(NetworkResponseError.unknown(statusCode: 999, message: nil).errorDescription == "Error (999)")
    }

    @Test("Returns custom message when provided")
    func errorDescriptionWithMessage() {
        #expect(NetworkResponseError.badRequest("custom").errorDescription == "custom")
    }
}
