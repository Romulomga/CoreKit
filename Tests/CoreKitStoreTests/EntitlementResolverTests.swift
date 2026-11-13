@testable import CoreKitStore
import Foundation
import Testing

struct EntitlementResolverTests {
    private let resolver = EntitlementResolver(plans: Plans.all)

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func lifetimeBeatsAnySubscription() {
        let resolved = resolver.resolve(
            [transaction(Plans.monthly, id: 1, expires: now + day), transaction(Plans.lifetime, id: 2)],
            at: now
        )

        #expect(resolved == .lifetime)
    }

    @Test func theFurthestActiveSubscriptionWins() {
        let resolved = resolver.resolve(
            [transaction(Plans.monthly, id: 1, expires: now + day), transaction(Plans.yearly, id: 2, expires: now + 300 * day)],
            at: now
        )

        #expect(resolved == .subscription(expires: now + 300 * day))
    }

    @Test func expiredRevokedUpgradedAndForeignTransactionsDoNotEntitle() {
        let foreign = StoreTransaction(id: 9, productID: "other.app.lifetime")
        let resolved = resolver.resolve(
            [
                transaction(Plans.monthly, id: 1, expires: now - 1),
                transaction(Plans.yearly, id: 2, expires: now + day, revoked: true),
                transaction(Plans.monthly, id: 3, expires: now + day, upgraded: true),
                transaction(Plans.lifetime, id: 4, revoked: true),
                foreign,
            ],
            at: now
        )

        #expect(resolved == EntitlementKind.none)
    }

    @Test func aRefundOfTheRememberedPeriodEndsIt() {
        let confirmed = EntitlementKind.subscription(expires: now + day)

        #expect(resolver.isRefunded(confirmed, by: [transaction(Plans.monthly, expires: now + day, revoked: true)]))
    }

    @Test func aRefundOfAnOlderPeriodDoesNotEndTheRememberedOne() {
        let confirmed = EntitlementKind.subscription(expires: now + 300 * day)

        #expect(!resolver.isRefunded(confirmed, by: [transaction(Plans.monthly, expires: now - 40 * day, revoked: true)]))
    }

    @Test func lifetimeEndsOnlyOnItsOwnRefund() {
        #expect(!resolver.isRefunded(.lifetime, by: [transaction(Plans.monthly, expires: now + day, revoked: true)]))
        #expect(resolver.isRefunded(.lifetime, by: [transaction(Plans.lifetime, revoked: true)]))
    }

    @Test func theDeliveredTransactionReplacesTheStaleCopy() {
        let stale = transaction(Plans.lifetime, id: 7)
        let refunded = transaction(Plans.lifetime, id: 7, revoked: true)
        let merged = resolver.merging(refunded, into: [stale, transaction(Plans.monthly, id: 8)])

        #expect(merged.map(\.id) == [8, 7])
        #expect(merged.last?.isRevoked == true)
    }

    @Test func anOldPurchaseDateIsAnAlreadyOwnedConfirmation() {
        #expect(EntitlementResolver.isAlreadyOwned(purchaseDate: now - 14 * day, purchaseStartedAt: now))
        #expect(!EntitlementResolver.isAlreadyOwned(purchaseDate: now + 20, purchaseStartedAt: now))
        #expect(!EntitlementResolver.isAlreadyOwned(purchaseDate: now - 600, purchaseStartedAt: now))
    }
}
