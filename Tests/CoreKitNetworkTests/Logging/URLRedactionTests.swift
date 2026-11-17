import Testing
import Foundation
@testable import CoreKitNetwork

/// `URLRedaction`, the same cases as CoreKit-Android's `UrlRedactionTest`.
@Suite("URLRedaction")
struct URLRedactionTests {

    private let redaction = URLRedaction(sensitiveParents: ["phone-number", "code", "name"], routeWords: ["check"])

    @Test func theQueryAndTheFragmentNeverStay() {
        #expect(URLRedaction().redact("https://api.example.com/v1/users/exists?email=a@b.com#top") == "https://api.example.com/v1/users/exists")
    }

    @Test func theSegmentAfterASensitiveParentIsMasked() {
        #expect(
            redaction.redact("https://api.example.com/v1/auth/phone-number/5521999990000/code/123456")
                == "https://api.example.com/v1/auth/phone-number/***/code/***"
        )
    }

    @Test func routeWordsAndIdsStay() {
        #expect(
            redaction.redact("https://api.example.com/v1/verification/code/check/42")
                == "https://api.example.com/v1/verification/code/check/42"
        )
        #expect(redaction.redact("https://api.example.com/v1/users/42/posts") == "https://api.example.com/v1/users/42/posts")
    }

    @Test func parentsMatchWhateverTheirCase() {
        #expect(redaction.redact("https://api.example.com/users/Name/Maria") == "https://api.example.com/users/Name/***")
    }

    @Test func aURLWithoutAPathKeepsItsHost() {
        #expect(redaction.redact("https://api.example.com?token=1") == "https://api.example.com")
    }

    @Test func theDebugMirrorCarriesTheRedactedURL() {
        let logger = ConsoleNetworkLogger(urlRedaction: redaction)

        let line = logger.mirroredLine([
            "method": "GET",
            "url": "https://api.example.com/v1/users/name/Maria?page=2",
            "body": "{\"password\":\"secret\"}"
        ])

        #expect(line == "method: GET, url: https://api.example.com/v1/users/name/***")
    }
}
