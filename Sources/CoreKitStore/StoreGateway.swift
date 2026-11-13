import Foundation

/// What `ProStore` needs from the App Store, without StoreKit's types. The rules (what to remember, when an answer
/// changes nothing) run in a test against a fake; only `StoreKitGateway` talks to StoreKit.
///
/// Every transaction a gateway returns is already verified: an unverified one never grants Pro.
@MainActor
public protocol StoreGateway {
    /// `Transaction.currentEntitlements`: what StoreKit says the account has right now. It can come back empty for a
    /// paying account, so an empty list is not proof of anything.
    func currentEntitlements() async -> [StoreTransaction]

    /// `Transaction.latest(for:)` for each product: the second opinion when `currentEntitlements` is empty, and where a
    /// refund shows up.
    func latestTransactions(for productIDs: [String]) async -> [StoreTransaction]

    /// The plans on sale, with whatever loaded even when part of the request failed.
    func products(for plans: [ProPlan]) async -> ProductsAnswer

    /// Shows the purchase sheet and waits for its end. Throws StoreKit's error, or the verification failure of the
    /// transaction it returned.
    func purchase(_ product: ProProduct) async throws -> StorePurchaseResult

    /// Tells StoreKit the content was delivered. An unfinished transaction is delivered again on every launch.
    func finish(_ transaction: StoreTransaction) async

    /// `AppStore.sync()`: asks the App Store for the account's purchases (it may ask the user to sign in).
    func sync() async throws

    /// `Transaction.updates`: renewals, refunds, approved Ask to Buy, purchases made on another device or outside the
    /// app, and the unfinished ones from an earlier launch.
    func transactionUpdates() -> AsyncStream<StoreTransaction>
}

/// How the purchase sheet ended, as StoreKit says it.
public enum StorePurchaseResult: Sendable {
    case success(StoreTransaction)

    case pending

    case userCancelled
}

/// The catalog request's answer. A partial failure still brings what loaded: hiding plans that can be sold because of
/// an error elsewhere loses sales.
public struct ProductsAnswer: Sendable {
    public let products: [ProProduct]

    public let failure: ProductsFailure?

    /// The underlying error, for crash reporting, when there is one.
    public let error: (any Error)?

    public init(products: [ProProduct], failure: ProductsFailure? = nil, error: (any Error)? = nil) {
        self.products = products
        self.failure = failure
        self.error = error
    }
}

/// Why the catalog didn't fully load. The raw value is the `reason` CoreKit-Android reports, so both platforms log
/// the same thing.
public enum ProductsFailure: String, Sendable, Hashable {
    /// The App Store couldn't be reached (no network): no request was answered. Not the same problem as `error`.
    case unavailable

    /// The App Store answered the request with an error.
    case error

    /// Everything answered and no product came back (a wrong id, or not on sale in this storefront).
    case empty
}
