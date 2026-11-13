import CoreKitStore
import CoreKitTesting
import Foundation
import Testing

/// The right to Pro: unknown until known, kept through StoreKit's silences, lost to a refund.
@MainActor
struct ProStoreTests {
    private let gateway = FakeStoreGateway()

    private let memory = FakeEntitlementMemory()

    private let observer = RecordingObserver()

    private func makeStore(resolveTimeout: Duration = .seconds(60)) -> ProStore {
        ProStore(plans: Plans.all, memory: memory, gateway: gateway, observer: observer, resolveTimeout: resolveTimeout)
    }

    // MARK: - Unknown until known

    @Test func staysUnknownUntilStoreKitAnswers() async {
        let gate = Gate()

        gateway.entitlements = [transaction(Plans.lifetime)]
        gateway.beforeEntitlementsAnswer = { await gate.wait() }

        let store = makeStore()

        #expect(store.state == .unknown)

        let start = Task { await store.start() }

        await waitUntil { gateway.entitlementQueries == 1 }

        #expect(store.state == .unknown)
        #expect(!store.isPro)
        #expect(observer.entitlements.isEmpty)

        gate.open()
        await start.value

        #expect(store.state == .pro)
        #expect(store.kind == .lifetime)
        #expect(memory.saved == .lifetime)
    }

    @Test func theRememberedRightAnswersBeforeStoreKit() {
        memory.saved = .lifetime

        #expect(makeStore().state == .pro)

        memory.saved = .subscription(expires: .now + day)

        #expect(makeStore().state == .pro)

        memory.saved = EntitlementKind.none

        #expect(makeStore().state == .free)
    }

    /// It most likely renewed: showing the free experience until StoreKit says so would be the launch flash again.
    @Test func aRememberedSubscriptionThatRanOutWaitsForStoreKit() {
        memory.saved = .subscription(expires: .now - 60)

        #expect(makeStore().state == .unknown)
    }

    @Test func withNothingRememberedASlowStoreKitGoesOnAsFreeAndBecomesProWhenItAnswers() async {
        let gate = Gate()

        gateway.entitlements = [transaction(Plans.yearly)]
        gateway.beforeEntitlementsAnswer = { await gate.wait() }

        let store = makeStore(resolveTimeout: .milliseconds(50))
        let start = Task { await store.start() }

        await waitUntil { store.state == .free }

        #expect(store.state == .free)
        #expect(memory.saved == nil)

        gate.open()
        await start.value

        #expect(store.state == .pro)
        #expect(memory.saved == store.kind)
    }

    @Test func anEmptyAnswerWithNothingToProtectIsRememberedAsFree() async {
        let store = makeStore()

        await store.start()

        #expect(store.state == .free)
        #expect(memory.saved == EntitlementKind.none)
        #expect(observer.confirmed == [[]])
    }

    /// Entitlements are local; products need the network. The gate must not wait on a slow connection.
    @Test func theRightResolvesBeforeTheCatalogLoads() async {
        let productsAskedBeforeTheAnswer = Box<Int?>(nil)
        let gateway = gateway

        gateway.beforeEntitlementsAnswer = { productsAskedBeforeTheAnswer.value = gateway.productQueries }

        await makeStore().start()

        #expect(productsAskedBeforeTheAnswer.value == 0)
        #expect(gateway.productQueries == 1)
    }

    // MARK: - StoreKit's silence

    @Test func silenceKeepsARememberedLifetime() async {
        memory.saved = .lifetime

        let store = makeStore()

        await store.start()

        #expect(store.state == .pro)
        #expect(memory.saved == .lifetime)
        #expect(memory.saves == 0)
        #expect(observer.kept == [.lastConfirmed])

        #expect(await store.refresh() == false)
        #expect(observer.kept == [.lastConfirmed])
    }

    /// A subscriber mid-period, and `currentEntitlements` answering with nothing at all.
    @Test func silenceKeepsARememberedSubscriptionUntilItRunsOut() async {
        let expires = Date.now + 17 * day

        memory.saved = .subscription(expires: expires)

        let store = makeStore()

        await store.start()

        #expect(store.state == .pro)
        #expect(store.kind == .subscription(expires: expires))
    }

    @Test func historyRecoversWhatCurrentEntitlementsMissed() async {
        let expires = Date.now + day

        gateway.history = [transaction(Plans.monthly, expires: expires)]

        let store = makeStore()

        await store.start()

        #expect(store.kind == .subscription(expires: expires))
        #expect(memory.saved == .subscription(expires: expires))
        #expect(observer.kept == [.transactionHistory])
    }

    @Test func aRememberedSubscriptionThatRanOutIsFreeWhenNothingEntitles() async {
        memory.saved = .subscription(expires: .now - 60)
        gateway.history = [transaction(Plans.monthly, expires: .now - 60)]

        let store = makeStore()

        await store.start()

        #expect(store.state == .free)
        #expect(memory.saved == EntitlementKind.none)
    }

    // MARK: - Refunds and updates

    @Test func aRefundDeliveredAsAnUpdateTakesProAwayWhileCurrentEntitlementsStillListsIt() async {
        let purchase = transaction(Plans.lifetime, id: 7)

        gateway.entitlements = [purchase]

        let store = makeStore()

        await store.start()

        #expect(store.state == .pro)

        let refunded = transaction(Plans.lifetime, id: 7, revoked: true)

        await gateway.deliverUpdate(refunded)

        #expect(store.state == .free)
        #expect(memory.saved == EntitlementKind.none)
        #expect(gateway.finished == [7])
    }

    @Test func aRefundFoundOnRefreshTakesAwayTheRememberedRight() async {
        memory.saved = .lifetime
        gateway.history = [transaction(Plans.lifetime, revoked: true)]

        let store = makeStore()

        #expect(store.state == .pro)

        await store.refresh()

        #expect(store.state == .free)
        #expect(memory.saved == EntitlementKind.none)
    }

    @Test func aRefreshReadBeforeARefundCantBringProBack() async {
        let gate = Gate()
        let isGated = Box(false)

        memory.saved = .lifetime
        gateway.entitlements = [transaction(Plans.lifetime, id: 7)]

        let store = makeStore()

        await store.start()

        gateway.beforeEntitlementsAnswer = {
            guard !isGated.value else { return }

            isGated.value = true
            await gate.wait()
        }

        let stale = Task { await store.refresh() }

        await waitUntil { isGated.value }

        gateway.entitlements = []
        gateway.history = [transaction(Plans.lifetime, id: 7, revoked: true)]

        await gateway.deliverUpdate(transaction(Plans.lifetime, id: 7, revoked: true))

        gate.open()
        _ = await stale.value
        await waitUntil { gateway.finished.contains(7) }

        #expect(store.state == .free)
        #expect(memory.saved == EntitlementKind.none)
    }

    @Test func everyDeliveredTransactionIsFinishedAndARenewalExtendsTheRight() async {
        let renewed = Date.now + 60 * day

        gateway.entitlements = [transaction(Plans.monthly, id: 1, expires: .now + day)]

        let store = makeStore()

        await store.start()

        gateway.entitlements = [transaction(Plans.monthly, id: 2, expires: renewed)]

        await gateway.deliverUpdate(transaction(Plans.monthly, id: 2, expires: renewed))

        #expect(gateway.finished == [2])
        #expect(store.kind == .subscription(expires: renewed))
    }

    @Test func lifetimeWinsAndOtherProductsAreIgnored() async {
        let foreign = StoreTransaction(id: 3, productID: "other.app.lifetime")

        gateway.entitlements = [transaction(Plans.yearly, id: 1), transaction(Plans.lifetime, id: 2), foreign]

        let store = makeStore()

        await store.start()

        #expect(store.kind == .lifetime)
        #expect(observer.confirmed.last?.map(\.id) == [1, 2])
    }

    // MARK: - Forced

    @Test func aForcedKindHoldsWhateverStoreKitSays() async {
        gateway.entitlements = [transaction(Plans.lifetime)]

        let store = makeStore()

        store.force(.none)

        await store.start()

        #expect(store.state == .free)
        #expect(gateway.entitlementQueries == 0)
        #expect(memory.saved == nil)

        let pro = makeStore()

        pro.force(.lifetime)
        gateway.entitlements = []

        await pro.start()

        #expect(pro.state == .pro)
    }
}
