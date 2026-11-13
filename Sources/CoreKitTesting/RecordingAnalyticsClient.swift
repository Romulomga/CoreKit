import CoreKitAnalytics
import os
import StoreKit

/// An `AnalyticsClient` that keeps what it is told, for asserting on events in an app's tests:
///
///     let analytics = RecordingAnalyticsClient()
///     let store = Store(analytics: analytics)
///     ...
///     #expect(analytics.eventNames == ["purchase_complete"])
public final class RecordingAnalyticsClient: AnalyticsClient {
    public struct Event: Sendable, Hashable {
        public let name: String
        public let parameters: [String: AnalyticsValue]

        public init(_ name: String, _ parameters: [String: AnalyticsValue] = [:]) {
            self.name = name
            self.parameters = parameters
        }
    }

    /// The error's description, since an `any Error` isn't `Sendable`.
    public struct RecordedError: Sendable, Hashable {
        public let description: String
        public let context: String?
    }

    private struct Recorded: Sendable {
        var events: [Event] = []
        var screens: [String] = []
        var userProperties: [String: String] = [:]
        var errors: [RecordedError] = []
        var transactionIDs: [UInt64] = []
        var purchases: [PurchaseRevenue] = []
    }

    private let recorded = OSAllocatedUnfairLock(initialState: Recorded())

    public init() {}

    public var events: [Event] { recorded.withLock { $0.events } }

    public var eventNames: [String] { events.map(\.name) }

    public var screens: [String] { recorded.withLock { $0.screens } }

    /// The current value of each property; a property set to `nil` is gone.
    public var userProperties: [String: String] { recorded.withLock { $0.userProperties } }

    public var errors: [RecordedError] { recorded.withLock { $0.errors } }

    public var transactionIDs: [UInt64] { recorded.withLock { $0.transactionIDs } }

    public var purchases: [PurchaseRevenue] { recorded.withLock { $0.purchases } }

    public func log(_ name: String, parameters: [String: AnalyticsValue]) {
        recorded.withLock { $0.events.append(Event(name, parameters)) }
    }

    public func screen(_ name: String) {
        recorded.withLock { $0.screens.append(name) }
    }

    public func setUserProperty(_ value: String?, forName name: String) {
        recorded.withLock { $0.userProperties[name] = value }
    }

    public func recordError(_ error: any Error, context: String?) {
        let error = RecordedError(description: String(describing: error), context: context)

        recorded.withLock { $0.errors.append(error) }
    }

    public func logTransaction(_ transaction: StoreKit.Transaction) {
        let id = transaction.id

        recorded.withLock { $0.transactionIDs.append(id) }
    }

    public func logPurchase(_ purchase: PurchaseRevenue) {
        recorded.withLock { $0.purchases.append(purchase) }
    }
}
