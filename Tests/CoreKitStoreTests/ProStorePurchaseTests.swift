import CoreKitStore
import CoreKitTesting
import Foundation
import Testing

/// Buying and restoring: only a verified purchase grants Pro.
@MainActor
struct ProStorePurchaseTests {
    private let gateway = FakeStoreGateway()

    private let memory = FakeEntitlementMemory()

    private func startedStore() async -> ProStore {
        let store = ProStore(plans: Plans.all, memory: memory, gateway: gateway, resolveTimeout: .seconds(60))

        await store.start()

        return store
    }

    /// `currentEntitlements` can lag the transaction just bought, leaving a paying user on the free plan.
    @Test func aVerifiedPurchaseGrantsProEvenWhileCurrentEntitlementsLags() async {
        let store = await startedStore()
        let bought = transaction(Plans.yearly, id: 5)

        gateway.nextPurchase = .success(bought)

        let outcome = await store.purchase(product(Plans.yearly, price: 49.9))

        #expect(outcome.result == .purchased)
        #expect(outcome.transaction?.id == 5)
        #expect(store.state == .pro)
        #expect(memory.saved == store.kind)
        #expect(gateway.finished == [5])
    }

    @Test func pendingAndCancelledPurchasesGiveNoPro() async {
        let store = await startedStore()

        gateway.nextPurchase = .pending

        #expect(await store.purchase(product(Plans.yearly, price: 49.9)).result == .pending)
        #expect(store.state == .free)

        gateway.nextPurchase = .userCancelled

        #expect(await store.purchase(product(Plans.lifetime, price: 99.9)).result == .cancelled)
        #expect(store.state == .free)
        #expect(gateway.finished.isEmpty)
    }

    /// Also how an unverified transaction ends: the gateway throws its verification error.
    @Test func aFailedPurchaseCarriesTheErrorAndGivesNoPro() async {
        let store = await startedStore()

        gateway.purchaseError = StoreDown()

        let outcome = await store.purchase(product(Plans.yearly, price: 49.9))

        #expect(outcome.result == .failed)
        #expect(outcome.error is StoreDown)
        #expect(store.state == .free)
    }

    @Test func buyingWhatTheAccountAlreadyHasIsNotASale() async {
        let store = await startedStore()

        gateway.nextPurchase = .success(transaction(Plans.lifetime, id: 3, purchased: .now - 14 * day))

        let outcome = await store.purchase(product(Plans.lifetime, price: 99.9))

        #expect(outcome.result == .alreadyOwned)
        #expect(store.state == .pro)
        #expect(gateway.finished == [3])
    }

    @Test func restoreSaysWhetherTheAppStoreCouldConfirm() async {
        let store = await startedStore()

        #expect(await store.restore())
        #expect(gateway.syncs == 1)

        gateway.syncError = StoreDown()

        #expect(await store.restore() == false)

        gateway.history = [transaction(Plans.lifetime)]

        #expect(await store.restore())
        #expect(store.state == .pro)
    }
}
