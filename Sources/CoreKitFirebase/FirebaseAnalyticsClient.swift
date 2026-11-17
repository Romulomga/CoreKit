import CoreKitAnalytics
internal import FirebaseAnalytics
internal import FirebaseCrashlytics
import StoreKit

/// The only place that talks to the Firebase SDK. A stateless value forwarding to Firebase's
/// thread-safe singletons, so it is `Sendable` as is.
struct FirebaseAnalyticsClient: AnalyticsClient {
    func log(_ name: String, parameters: [String: AnalyticsValue]) {
        FirebaseAnalytics.Analytics.logEvent(name, parameters: Self.eventParameters(parameters))
    }

    func screen(_ name: String) {
        FirebaseAnalytics.Analytics.logEvent(AnalyticsEventScreenView, parameters: Self.screenViewParameters(name))
    }

    func setUserProperty(_ value: String?, forName name: String) {
        FirebaseAnalytics.Analytics.setUserProperty(value, forName: name)
    }

    func recordError(_ error: any Error, context: String?) {
        let crashlytics = Crashlytics.crashlytics()

        if let context { crashlytics.log(context) }

        crashlytics.record(error: error)
    }

    func logTransaction(_ transaction: StoreKit.Transaction) {
        FirebaseAnalytics.Analytics.logTransaction(transaction)
    }

    func logPurchase(_ purchase: PurchaseRevenue) {
        FirebaseAnalytics.Analytics.logEvent(AnalyticsEventPurchase, parameters: Self.purchaseParameters(purchase))
    }

    /// Crashlytics has no "forget": an empty id is its sign-out.
    func setUserID(_ id: String?) {
        FirebaseAnalytics.Analytics.setUserID(id)
        Crashlytics.crashlytics().setUserID(id ?? "")
    }

    func setCrashKey(_ value: String, forKey key: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }

    func addBreadcrumb(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }

    // MARK: - Parameters

    // What each call hands Firebase, built apart from the SDK so a test reads it without Firebase set up.

    static func eventParameters(_ parameters: [String: AnalyticsValue]) -> [String: Any]? {
        parameters.isEmpty ? nil : parameters.mapValues(parameter)
    }

    /// GA4 groups screens by class too and reports "(not set)" without one. Automatic screen
    /// reporting would fill it with the hosting controller's name, which is why it is off.
    static func screenViewParameters(_ name: String) -> [String: Any] {
        [
            AnalyticsParameterScreenName: name,
            AnalyticsParameterScreenClass: name,
        ]
    }

    /// GA4 sums `value` verbatim, so it goes in whole currency units, and drops the revenue when
    /// `value` or `currency` is missing. The item, with its own price, fills the per-product
    /// reports.
    static func purchaseParameters(_ purchase: PurchaseRevenue) -> [String: Any] {
        let value = Double(purchase.valueCents) / 100

        var parameters: [String: Any] = [
            AnalyticsParameterValue: value,
            AnalyticsParameterCurrency: purchase.currency,
            AnalyticsParameterItems: [[
                AnalyticsParameterItemID: purchase.itemID,
                AnalyticsParameterItemName: purchase.itemName,
                AnalyticsParameterItemCategory: purchase.category,
                AnalyticsParameterPrice: value,
                AnalyticsParameterCurrency: purchase.currency,
                AnalyticsParameterQuantity: 1,
            ]],
        ]

        if let transactionID = purchase.transactionID {
            parameters[AnalyticsParameterTransactionID] = transactionID
        }

        return parameters
    }

    /// A GA4 custom dimension reads only a parameter's text slot, and Firebase puts a `Bool` in the
    /// number slot: a boolean dimension would report "(not set)" forever, however it is registered.
    /// A flag is always a category, never a metric, so it goes as text. Numbers stay numbers, which
    /// GA4 sums and averages; an app sends a grouping number (`page_index`) as text itself.
    static func parameter(_ value: AnalyticsValue) -> Any {
        switch value {
        case .string(let text): text
        case .int(let number): number
        case .double(let number): number
        case .bool(let flag): flag ? "true" : "false"
        }
    }
}
