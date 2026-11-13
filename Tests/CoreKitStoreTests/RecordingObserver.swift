import CoreKitStore

@MainActor
final class RecordingObserver: ProStoreObserver {
    var entitlements: [EntitlementKind] = []

    var confirmed: [[StoreTransaction]] = []

    var productFailures: [ProductsFailure] = []

    var kept: [KeptProSource] = []

    func onEntitlement(_ kind: EntitlementKind) {
        entitlements.append(kind)
    }

    func onConfirmed(_ active: [StoreTransaction]) async {
        confirmed.append(active)
    }

    func onProductsLoadFailed(_ failure: ProductsFailure, error: (any Error)?) {
        productFailures.append(failure)
    }

    func onProKeptWithoutAnswer(source: KeptProSource) {
        kept.append(source)
    }
}
