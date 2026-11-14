@testable import CoreKitFirebase
import Testing

/// What each call hands Firebase, read without Firebase set up. The keys are written out, not taken from Firebase's
/// constants: they are the names GA4 reads, and a wrong one only shows up as an empty report. The twin of
/// CoreKit-Android's `FirebaseParametersTest`.
struct FirebaseParametersTests {
    // MARK: - Values

    /// A GA4 dimension reads only the text slot: a flag sent as a number reports "(not set)" forever.
    @Test func aFlagGoesAsText() {
        #expect(FirebaseAnalyticsClient.parameter(.bool(true)) as? String == "true")
        #expect(FirebaseAnalyticsClient.parameter(.bool(false)) as? String == "false")
    }

    /// GA4 sums and averages a number only when it arrives as one.
    @Test func numbersStayNumbersAndTextStaysText() {
        #expect(FirebaseAnalyticsClient.parameter(.int(3)) as? Int == 3)
        #expect(FirebaseAnalyticsClient.parameter(.double(0.5)) as? Double == 0.5)
        #expect(FirebaseAnalyticsClient.parameter(.string("receipt")) as? String == "receipt")
    }

    @Test func anEventKeepsEveryParameterNameAndMapsEachValue() throws {
        let parameters = try #require(
            FirebaseAnalyticsClient.eventParameters(["kind": "receipt", "item_count": 2, "has_logo": true])
        )

        #expect(parameters.count == 3)
        #expect(parameters["kind"] as? String == "receipt")
        #expect(parameters["item_count"] as? Int == 2)
        #expect(parameters["has_logo"] as? String == "true")

        #expect(FirebaseAnalyticsClient.eventParameters([:]) == nil)
    }

    // MARK: - Screen view

    /// Without a class GA4 lists the screen under "(not set)", and the report stops matching Android's, which sends the
    /// name in both too.
    @Test func aScreenViewNamesTheScreenInTheClassToo() {
        let parameters = FirebaseAnalyticsClient.screenViewParameters("home")

        #expect(parameters.count == 2)
        #expect(parameters["screen_name"] as? String == "home")
        #expect(parameters["screen_class"] as? String == "home")
    }

    // MARK: - Purchase

    /// GA4 sums `value` as it comes, and its per-product reports read the item's own price and quantity.
    @Test func aPurchaseCarriesTheValueInWholeUnitsAndAnItemWithItsOwnPrice() throws {
        let purchase = PurchaseRevenue(itemID: "yearly", valueCents: 4_990, currency: "BRL", transactionID: "2000000123")
        let parameters = FirebaseAnalyticsClient.purchaseParameters(purchase)
        let items = try #require(parameters["items"] as? [[String: Any]])
        let item = try #require(items.first)

        #expect(parameters["value"] as? Double == 49.9)
        #expect(parameters["currency"] as? String == "BRL")
        #expect(parameters["transaction_id"] as? String == "2000000123")

        #expect(items.count == 1)
        #expect(item["item_id"] as? String == "yearly")
        #expect(item["item_name"] as? String == "yearly")
        #expect(item["item_category"] as? String == "pro")
        #expect(item["price"] as? Double == 49.9)
        #expect(item["currency"] as? String == "BRL")
        #expect(item["quantity"] as? Int == 1)
    }

    @Test func theItemNameCanDifferFromItsID() throws {
        let purchase = PurchaseRevenue(itemID: "app.pro.yearly", itemName: "yearly", valueCents: 0, currency: "BRL")
        let items = try #require(FirebaseAnalyticsClient.purchaseParameters(purchase)["items"] as? [[String: Any]])

        #expect(items.first?["item_id"] as? String == "app.pro.yearly")
        #expect(items.first?["item_name"] as? String == "yearly")
    }

    /// A free trial goes as a sale of zero, still counted as a conversion; StoreKit doesn't always give an id.
    @Test func aPurchaseWithoutATransactionIDLeavesTheParameterOut() {
        let parameters = FirebaseAnalyticsClient.purchaseParameters(
            PurchaseRevenue(itemID: "yearly", valueCents: 0, currency: "BRL")
        )

        #expect(parameters["value"] as? Double == 0)
        #expect(parameters["currency"] as? String == "BRL")
        #expect(!parameters.keys.contains("transaction_id"))
    }
}
