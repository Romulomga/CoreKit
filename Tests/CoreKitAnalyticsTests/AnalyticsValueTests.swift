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
