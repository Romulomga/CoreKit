import Foundation
import StoreKit

/// The real App Store, through StoreKit 2. Unverified transactions stop here: nothing is granted on a signature
/// StoreKit couldn't check, and they are not finished either.
public struct StoreKitGateway: StoreGateway {
    public init() {}

    public func currentEntitlements() async -> [StoreTransaction] {
        var transactions: [StoreTransaction] = []

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                transactions.append(await Self.storeTransaction(transaction))
            }
        }

        return transactions
    }

    public func latestTransactions(for productIDs: [String]) async -> [StoreTransaction] {
        var transactions: [StoreTransaction] = []

        for productID in productIDs {
            if case .verified(let transaction) = await Transaction.latest(for: productID) {
                transactions.append(await Self.storeTransaction(transaction))
            }
        }

        return transactions
    }

    public func products(for plans: [ProPlan]) async -> ProductsAnswer {
        let loaded: [Product]

        do {
            loaded = try await Product.products(for: plans.map(\.productID))
        } catch {
            return ProductsAnswer(products: [], failure: Self.isUnreachable(error) ? .unavailable : .error, error: error)
        }

        var products: [ProProduct] = []

        for product in loaded {
            guard let plan = plans.first(where: { $0.productID == product.id }) else { continue }

            products.append(ProProduct(plan: plan, product: product, freeTrial: await Self.eligibleFreeTrial(of: product)))
        }

        return ProductsAnswer(products: products, failure: products.isEmpty ? .empty : nil)
    }

    public func purchase(_ product: ProProduct) async throws -> StorePurchaseResult {
        try await purchase(product, appAccountToken: nil)
    }

    public func purchase(_ product: ProProduct, appAccountToken: UUID?) async throws -> StorePurchaseResult {
        guard let storeProduct = product.storeProduct else { throw StoreKitGatewayError.productNotLoaded }

        let options: Set<Product.PurchaseOption> = appAccountToken.map { [.appAccountToken($0)] } ?? []

        switch try await storeProduct.purchase(options: options) {
        case .success(let verification):
            return .success(StoreTransaction(try verification.payloadValue))

        case .pending:
            return .pending

        case .userCancelled:
            return .userCancelled

        // Grants nothing and shows no error; if it completes later, it arrives through `Transaction.updates`.
        @unknown default:
            return .pending
        }
    }

    public func finish(_ transaction: StoreTransaction) async {
        await transaction.transaction?.finish()
    }

    public func sync() async throws {
        try await AppStore.sync()
    }

    public func transactionUpdates() -> AsyncStream<StoreTransaction> {
        AsyncStream { continuation in
            let listener = Task {
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result {
                        continuation.yield(StoreTransaction(transaction))
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in listener.cancel() }
        }
    }

    /// The transaction with its grace period's end, read only for a subscription already past its expiry (the one case
    /// where it matters, and it costs a request).
    private static func storeTransaction(_ transaction: Transaction) async -> StoreTransaction {
        guard let expires = transaction.expirationDate, expires <= .now, let group = transaction.subscriptionGroupID else {
            return StoreTransaction(transaction)
        }

        return StoreTransaction(transaction, gracePeriodExpirationDate: await gracePeriodEnd(of: transaction, in: group))
    }

    private static func gracePeriodEnd(of transaction: Transaction, in group: String) async -> Date? {
        guard let statuses = try? await Product.SubscriptionInfo.status(for: group) else { return nil }

        for status in statuses where status.state == .inGracePeriod {
            guard case .verified(let renewal) = status.renewalInfo,
                  case .verified(let latest) = status.transaction,
                  latest.originalID == transaction.originalID
            else { continue }

            return renewal.gracePeriodExpirationDate
        }

        return nil
    }

    /// StoreKit wraps a connection problem in `networkError`: the App Store was never reached, which is not the same
    /// as the App Store answering with an error.
    nonisolated static func isUnreachable(_ error: any Error) -> Bool {
        if let storeKitError = error as? StoreKitError, case .networkError = storeKitError { return true }

        return error is URLError
    }

    private static func eligibleFreeTrial(of product: Product) async -> FreeTrial? {
        guard let subscription = product.subscription,
              let offer = subscription.introductoryOffer,
              offer.paymentMode == .freeTrial,
              await subscription.isEligibleForIntroOffer
        else { return nil }

        return FreeTrial(offer.period)
    }
}

enum StoreKitGatewayError: Error {
    /// The product was built by hand, not loaded from the App Store, so there is nothing to buy.
    case productNotLoaded
}
