import Testing
import Foundation
@testable import CoreKitNetwork

@Suite("HTTPStatusCode")
struct HTTPStatusCodeTests {

    // MARK: - Range checks

    @Test("isInformational returns true for 100–199 and false outside")
    func isInformationalRange() {
        #expect(HTTPStatusCode(rawValue: 100).isInformational == true)
        #expect(HTTPStatusCode(rawValue: 199).isInformational == true)
        #expect(HTTPStatusCode(rawValue: 200).isInformational == false)
        #expect(HTTPStatusCode(rawValue: 99).isInformational == false)
    }

    @Test("isSuccess returns true for 200–299 and false outside")
    func isSuccessRange() {
        #expect(HTTPStatusCode(rawValue: 200).isSuccess == true)
        #expect(HTTPStatusCode(rawValue: 299).isSuccess == true)
        #expect(HTTPStatusCode(rawValue: 300).isSuccess == false)
    }

    @Test("isRedirection returns true for 300–399 and false outside")
    func isRedirectionRange() {
        #expect(HTTPStatusCode(rawValue: 300).isRedirection == true)
        #expect(HTTPStatusCode(rawValue: 399).isRedirection == true)
        #expect(HTTPStatusCode(rawValue: 400).isRedirection == false)
        #expect(HTTPStatusCode(rawValue: 299).isRedirection == false)
    }

    @Test("isClientError returns true for 400–499 and false outside")
    func isClientErrorRange() {
        #expect(HTTPStatusCode(rawValue: 400).isClientError == true)
        #expect(HTTPStatusCode(rawValue: 200).isClientError == false)
    }

    @Test("isServerError returns true for 500–599 and false outside")
    func isServerErrorRange() {
        #expect(HTTPStatusCode(rawValue: 500).isServerError == true)
        #expect(HTTPStatusCode(rawValue: 400).isServerError == false)
    }

    // MARK: - Static constants

    @Test("Static constants map to correct raw values")
    func staticConstants() {
        #expect(HTTPStatusCode.ok.rawValue == 200)
        #expect(HTTPStatusCode.notFound.rawValue == 404)
        #expect(HTTPStatusCode.internalServerError.rawValue == 500)
    }

    // MARK: - Description

    @Test("description follows 'code - message' format")
    func descriptionFormat() {
        #expect(HTTPStatusCode.ok.description == "200 - OK")
        #expect(HTTPStatusCode.notFound.description == "404 - Not Found")
    }

    // MARK: - Equality

    @Test("Equatable conformance compares raw values")
    func equality() {
        #expect(HTTPStatusCode(rawValue: 200) == HTTPStatusCode.ok)
        #expect(HTTPStatusCode(rawValue: 200) != HTTPStatusCode(rawValue: 201))
    }
}
