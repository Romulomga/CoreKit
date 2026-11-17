import CoreKitStore
import Foundation

/// The App Store, made up, for tests of the code around `ProStore` (purchase analytics, the end-of-trial reminder).
/// Change the fields to build the scenario; empty `entitlements` and `history` is StoreKit saying nothing.
@MainActor
public final class FakeStoreGateway: StoreGateway {
    /// What `Transaction.currentEntitlements` lists.
    public var entitlements: [StoreTransaction]

    /// What `Transaction.latest(for:)` returns, filtered to the products asked for.
    public var history: [StoreTransaction]

    /// The catalog; `nil` is a request the App Store answered with an error.
    public var products: [ProProduct]?

    /// The App Store can't be reached for the catalog.
    public var productsUnavailable = false

    /// With `products` filled, a failure reported alongside them: part of the catalog loaded.
    public var partialProductsFailure: ProductsFailure?

    /// How the next purchase sheet ends.
    public var nextPurchase: StorePurchaseResult = .userCancelled

    /// Thrown by the next purchase instead of `nextPurchase`.
    public var purchaseError: (any Error)?

    /// Thrown by `sync()`: the App Store couldn't be reached.
    public var syncError: (any Error)?

    /// Runs after `currentEntitlements` read its answer and before it returns it: the place to suspend for a slow
    /// StoreKit.
    public var beforeEntitlementsAnswer: (@MainActor () async -> Void)?

    public private(set) var finished: [UInt64] = []

    /// The `appAccountToken` of each purchase, in order (`nil` when none was given).
    public private(set) var purchaseAccountTokens: [UUID?] = []

    public private(set) var entitlementQueries = 0

    public private(set) var productQueries = 0

    public private(set) var syncs = 0

    private var updates: AsyncStream<StoreTransaction>.Continuation?

    public init(
        entitlements: [StoreTransaction] = [],
        history: [StoreTransaction] = [],
        products: [ProProduct]? = []
    ) {
        self.entitlements = entitlements
        self.history = history
        self.products = products
    }

    public func currentEntitlements() async -> [StoreTransaction] {
        entitlementQueries += 1

        let answer = entitlements

        await beforeEntitlementsAnswer?()

        return answer
    }

    public func latestTransactions(for productIDs: [String]) async -> [StoreTransaction] {
        history.filter { productIDs.contains($0.productID) }
    }

    public func products(for plans: [ProPlan]) async -> ProductsAnswer {
        productQueries += 1

        if productsUnavailable { return ProductsAnswer(products: [], failure: .unavailable) }

        guard let products else { return ProductsAnswer(products: [], failure: .error) }

        if products.isEmpty { return ProductsAnswer(products: [], failure: .empty) }

        return ProductsAnswer(products: products, failure: partialProductsFailure)
    }

    public func purchase(_ product: ProProduct) async throws -> StorePurchaseResult {
        try await purchase(product, appAccountToken: nil)
    }

    public func purchase(_ product: ProProduct, appAccountToken: UUID?) async throws -> StorePurchaseResult {
        purchaseAccountTokens.append(appAccountToken)

        if let purchaseError { throw purchaseError }

        return nextPurchase
    }

    public func finish(_ transaction: StoreTransaction) async {
        finished.append(transaction.id)
    }

    public func sync() async throws {
        syncs += 1

        if let syncError { throw syncError }
    }

    public func transactionUpdates() -> AsyncStream<StoreTransaction> {
        let (stream, continuation) = AsyncStream.makeStream(of: StoreTransaction.self)

        updates = continuation

        return stream
    }

    /// Delivers `transaction` the way `Transaction.updates` does, and gives the store the chance to finish it before
    /// returning. Needs `ProStore.start()` first: that is when the store starts listening.
    public func deliverUpdate(_ transaction: StoreTransaction) async {
        updates?.yield(transaction)

        var turns = 0

        while !finished.contains(transaction.id), turns < 1_000 {
            turns += 1
            await Task.yield()
        }
    }
}
