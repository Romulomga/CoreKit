import Testing
import Foundation
@testable import CoreKitNetwork

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
}

@Suite("DecodingError+Extensions")
struct DecodingErrorTests {

    @Test("keyNotFoundDescription returns message containing key name and 'not found'")
    func keyNotFoundDescription() {
        let error = DecodingError.keyNotFound(
            AnyCodingKey(stringValue: "name"),
            .init(codingPath: [], debugDescription: "")
        )
        let description = error.detailedDescription
        #expect(description.contains("Key 'name' not found"))
    }

    @Test("typeMismatchDescription returns message containing 'Type mismatch' and expected type")
    func typeMismatchDescription() {
        let error = DecodingError.typeMismatch(
            String.self,
            .init(codingPath: [], debugDescription: "")
        )
        let description = error.detailedDescription
        #expect(description.contains("Type mismatch"))
        #expect(description.contains("String"))
    }

    @Test("valueNotFoundDescription returns message containing 'Value of type' and missing type")
    func valueNotFoundDescription() {
        let error = DecodingError.valueNotFound(
            Int.self,
            .init(codingPath: [], debugDescription: "")
        )
        let description = error.detailedDescription
        #expect(description.contains("Value of type"))
        #expect(description.contains("Int"))
    }

    @Test("dataCorruptedDescription returns message containing 'Data corrupted' and debug description")
    func dataCorruptedDescription() {
        let error = DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "bad format")
        )
        let description = error.detailedDescription
        #expect(description.contains("Data corrupted"))
        #expect(description.contains("bad format"))
    }
}
