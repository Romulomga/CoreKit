import CoreKitStore
import CoreKitTesting
import Foundation
import Testing

/// The catalog: what loaded stays on sale.
@MainActor
struct ProStoreProductsTests {
    private let gateway = FakeStoreGateway()

    private let observer = RecordingObserver()

    private func makeStore() -> ProStore {
        ProStore(plans: Plans.all, memory: FakeEntitlementMemory(), gateway: gateway, observer: observer)
    }

    @Test func productsAreSortedByPriceAndAnEmptyAnswerIsAFailure() async {
        let store = makeStore()

        #expect(store.productsState == .loading)

        await store.loadProducts()

        #expect(store.productsState == .failed)
        #expect(observer.productFailures == [.empty])

        gateway.products = [product(Plans.lifetime, price: 99.9), product(Plans.monthly, price: 9.9), product(Plans.yearly, price: 49.9)]

        await store.reloadProductsIfFailed()

        #expect(store.productsState == .loaded)
        #expect(store.products.map(\.plan) == [Plans.monthly, Plans.yearly, Plans.lifetime])
        #expect(store.product(for: Plans.yearly)?.price == 49.9)
    }

    @Test func aFailedReloadKeepsTheLoadedCatalog() async {
        let store = makeStore()

        gateway.products = [product(Plans.yearly, price: 49.9)]

        await store.loadProducts()

        gateway.products = nil

        await store.loadProducts()

        #expect(store.productsState == .loaded)
        #expect(store.products.map(\.plan) == [Plans.yearly])
        #expect(observer.productFailures == [.error])
    }

    @Test func aPartialFailureKeepsThePlansThatLoadedAndStillReportsIt() async {
        let store = makeStore()

        gateway.products = [product(Plans.yearly, price: 49.9)]
        gateway.partialProductsFailure = .error

        await store.loadProducts()

        #expect(store.productsState == .loaded)
        #expect(store.products.map(\.plan) == [Plans.yearly])
        #expect(observer.productFailures == [.error])
    }

    @Test func anUnreachableAppStoreIsNotAFailedRequest() async {
        let store = makeStore()

        gateway.productsUnavailable = true

        await store.loadProducts()

        #expect(store.productsState == .failed)
        #expect(observer.productFailures == [.unavailable])
    }

    @Test func aLoadedCatalogIsNotReloaded() async {
        let store = makeStore()

        gateway.products = [product(Plans.yearly, price: 49.9)]

        await store.loadProducts()
        await store.reloadProductsIfFailed()

        #expect(gateway.productQueries == 1)
    }
}
