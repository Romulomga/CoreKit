import StoreKit
import CoreKitAnalytics
import Testing

struct AnalyticsValueTests {
    /// The `[String: Any]` builders this replaces read a flag bridged through `NSNumber` as `1`.
    @Test func variablesKeepTheirType() {
        let hasLogo = true
        let itemCount = 3
        let kind = "receipt"
        let parameters: [String: any AnalyticsValueConvertible] = ["has_logo": hasLogo, "item_count": itemCount, "kind": kind]

        #expect(parameters.mapValues(\.analyticsValue) == ["has_logo": .bool(true), "item_count": .int(3), "kind": .string("receipt")])
    }

    @Test func literalsKeepTheirType() {
        let count = 2
        let parameters: [String: AnalyticsValue] = ["flag": false, "count": 1, "share": 0.5, "page": "\(count)"]

        #expect(parameters == ["flag": .bool(false), "count": .int(1), "share": .double(0.5), "page": .string("2")])
    }
}

/// An engine that only takes text gets typed properties as text, and no profile.
struct TextOnlyClientTests {
    private final class TextOnly: AnalyticsClient, @unchecked Sendable {
        var properties: [String: String] = [:]

        func log(_ name: String, parameters: [String: AnalyticsValue]) {}
        func screen(_ name: String) {}
        func setUserProperty(_ value: String?, forName name: String) { properties[name] = value }
        func recordError(_ error: any Error, context: String?) {}
        func logTransaction(_ transaction: StoreKit.Transaction) {}
        func logPurchase(_ purchase: PurchaseRevenue) {}
    }

    @Test func typedPropertiesReachATextOnlyEngineAsText() {
        let client = TextOnly()

        client.setUserProperties(["enabled": true, "count": 3, "plan": "pro"])
        client.setUserProfile(["$name": "Ana"])

        #expect(client.properties == ["enabled": "true", "count": "3", "plan": "pro"])
    }
}
