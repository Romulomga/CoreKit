import StoreKit
import SwiftUI

/// Where an app's events go. The app keeps its typed events (names and parameters are product
/// decisions) and turns each into a name plus parameters at its own boundary; only the engine
/// modules know an SDK, so views, models and tests never import Firebase or Mixpanel.
///
/// `Sendable` so the same client is handed to a `@MainActor` store, a view's environment and a
/// notification delegate that runs off the main thread.
public protocol AnalyticsClient: Sendable {
    /// A discrete event: a tap, a funnel step, a purchase outcome.
    func log(_ name: String, parameters: [String: AnalyticsValue])

    /// A screen view. `TrackScreen` calls it; an app rarely needs to.
    func screen(_ name: String)

    /// A durable property of this install, for segmenting every later event (`is_pro`,
    /// `entitlement`). `nil` clears it.
    func setUserProperty(_ value: String?, forName name: String)

    /// A non-fatal error for the crash reporter, with an optional breadcrumb of where it happened.
    func recordError(_ error: any Error, context: String?)

    /// A completed StoreKit 2 purchase as the App Store's own revenue event (`in_app_purchase` in
    /// Firebase). StoreKit 2 purchases bypass the payment-queue observer Firebase's automatic
    /// collection listens to, so without this the revenue reports stay empty. Call it only on the
    /// explicit purchase-success path: renewals already arrive on their own, and logging them here
    /// would count the revenue twice. Use it or `logPurchase`, never both for one sale. iOS only:
    /// CoreKit-Android has just `logPurchase`.
    func logTransaction(_ transaction: StoreKit.Transaction)

    /// A sale with the value the app states, as the engine's standard purchase event (`purchase` in
    /// Firebase), apart from the app's funnel events. The twin of CoreKit-Android's `logPurchase`.
    /// Use it or `logTransaction`, never both for one sale.
    func logPurchase(_ purchase: PurchaseRevenue)
}

/// A confirmed sale. The value goes in cents: no floating point on the money path until the engine
/// needs one. Prefer the price actually charged (`Transaction.price`) over the list price, which
/// overstates a sale made with an introductory offer.
public struct PurchaseRevenue: Sendable, Hashable {
    public let itemID: String
    public let itemName: String
    public let valueCents: Int
    public let currency: String
    public let transactionID: String?
    public let category: String

    /// - Parameter itemName: Defaults to `itemID`.
    public init(
        itemID: String,
        itemName: String? = nil,
        valueCents: Int,
        currency: String,
        transactionID: String? = nil,
        category: String = "pro"
    ) {
        self.itemID = itemID
        self.itemName = itemName ?? itemID
        self.valueCents = valueCents
        self.currency = currency
        self.transactionID = transactionID
        self.category = category
    }
}

/// The client of whoever doesn't collect: previews, a store built in a unit test.
public struct NoopAnalyticsClient: AnalyticsClient {
    public init() {}

    public func log(_ name: String, parameters: [String: AnalyticsValue]) {}

    public func screen(_ name: String) {}

    public func setUserProperty(_ value: String?, forName name: String) {}

    public func recordError(_ error: any Error, context: String?) {}

    public func logTransaction(_ transaction: StoreKit.Transaction) {}

    public func logPurchase(_ purchase: PurchaseRevenue) {}
}

// MARK: - Environment

extension EnvironmentValues {
    /// Defaults to `Analytics.shared`, not to a no-op: a view outside the scope where the app
    /// injects the client still reports. A root-level `.sheet` placed after the app's
    /// `.environment(\.analytics, …)` doesn't inherit it, and that is how one app's paywall
    /// reported nothing for three releases. Previews and tests never start an engine, so the
    /// default is silent there.
    public var analytics: any AnalyticsClient {
        get { self[AnalyticsClientKey.self] }
        set { self[AnalyticsClientKey.self] = newValue }
    }
}

private struct AnalyticsClientKey: EnvironmentKey {
    static let defaultValue: any AnalyticsClient = Analytics.shared
}
