import Foundation
import Observation

/// What each app does around the store: analytics, a widget mirror of the right, the end-of-trial reminder. Every
/// method has an empty default, so implement only what you use.
@MainActor
public protocol ProStoreObserver {
    /// The right was applied: read from memory, answered by StoreKit, forced, or taken as free when StoreKit took too
    /// long. May repeat the same value.
    func onEntitlement(_ kind: EntitlementKind)

    /// StoreKit gave an answer that changes or confirms the right: `active` are the transactions that entitle now
    /// (empty when there is none).
    func onConfirmed(_ active: [StoreTransaction]) async

    /// The catalog didn't fully load. Products that did load are on sale anyway.
    func onProductsLoadFailed(_ failure: ProductsFailure, error: (any Error)?)

    /// `currentEntitlements` came back empty and Pro was kept anyway. Once per process.
    func onProKeptWithoutAnswer(source: KeptProSource)
}

extension ProStoreObserver {
    public func onEntitlement(_ kind: EntitlementKind) {}

    public func onConfirmed(_ active: [StoreTransaction]) async {}

    public func onProductsLoadFailed(_ failure: ProductsFailure, error: (any Error)?) {}

    public func onProKeptWithoutAnswer(source: KeptProSource) {}
}

/// Why Pro was kept when `currentEntitlements` came back empty. The raw value is a stable name for analytics.
public enum KeptProSource: String, Sendable, Hashable {
    /// A plan's latest transaction still entitles: `currentEntitlements` missed it.
    case transactionHistory = "transaction_history"

    /// StoreKit said nothing either way, and the remembered right hasn't run out.
    case lastConfirmed = "last_confirmed"
}

/// The Pro right through StoreKit 2, twin of CoreKit-Android's `ProStore`. Each rule comes from an incident:
///
/// - Until the right is known the state is `.unknown`, not free, so a paying user sees no teaser and counts no paywall
///   impression at launch. The remembered right answers first; without one, the wait for StoreKit is capped
///   (`resolveTimeout`) and the app goes on as free until StoreKit answers.
/// - Only StoreKit's word changes the right. `currentEntitlements` has come back empty for a subscriber mid-period, who
///   then met the free limit on every launch and bought again: an empty list is checked against each plan's latest
///   transaction and, failing that, the remembered right stands until it runs out or its refund shows up.
/// - A refund or revocation takes the right away, even while `currentEntitlements` still lists the purchase.
/// - `Transaction.updates` is heard from `start()` on, and every verified transaction is finished.
/// - A verified purchase grants Pro at once, even when `currentEntitlements` lags behind it.
/// - The right resolves before the catalog loads: entitlements are local, products need the network.
/// - A failed catalog load keeps the plans already loaded, and part of a catalog is still on sale.
///
/// Gate every Pro surface on `state` (or `isPro`), never on a product.
@MainActor
@Observable
public final class ProStore: Entitlement {
    public private(set) var products: [ProProduct] = []

    public private(set) var productsState: ProductsState = .loading

    /// `nil` until the right is known.
    private var known: EntitlementKind? = nil

    /// The kind of the right in use (`.none` while unknown): what the paywall shows a subscriber ("renews on…").
    public var kind: EntitlementKind { known ?? .none }

    /// Read against the clock, so a subscription that runs out while the app is open stops being Pro.
    public var state: EntitlementState {
        guard let known else { return .unknown }

        return known.isActive(at: .now) ? .pro : .free
    }

    @ObservationIgnored private let gateway: any StoreGateway

    @ObservationIgnored private let memory: any EntitlementMemory

    @ObservationIgnored private let observer: (any ProStoreObserver)?

    @ObservationIgnored private let resolver: EntitlementResolver

    @ObservationIgnored private let resolveTimeout: Duration

    /// The last right StoreKit confirmed, as `memory` holds it.
    @ObservationIgnored private var confirmed: EntitlementKind?

    @ObservationIgnored private var forced: EntitlementKind?

    @ObservationIgnored private var hasStarted = false

    @ObservationIgnored private var hasReportedKeptPro = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    /// The last refresh queued: each one waits for the previous, so an answer read before a refund can't land after it
    /// and bring Pro back.
    @ObservationIgnored private var refreshTail: Task<Bool, Never>?

    @ObservationIgnored private var productsTask: Task<Void, Never>?

    /// - Parameters:
    ///   - plans: the app's Pro plans. Transactions for any other product are ignored.
    ///   - memory: where the confirmed right is kept between launches.
    ///   - resolveTimeout: how long a launch with nothing remembered waits for StoreKit before going on as free.
    public init(
        plans: [ProPlan],
        memory: any EntitlementMemory,
        gateway: any StoreGateway = StoreKitGateway(),
        observer: (any ProStoreObserver)? = nil,
        resolveTimeout: Duration = .seconds(3)
    ) {
        self.gateway = gateway
        self.memory = memory
        self.observer = observer
        self.resolver = EntitlementResolver(plans: plans)
        self.resolveTimeout = resolveTimeout

        let remembered = memory.load()

        confirmed = remembered

        // A remembered subscription that ran out stays unknown: it most likely renewed, and StoreKit says so in a
        // moment.
        guard let remembered, remembered == EntitlementKind.none || remembered.isActive(at: .now) else { return }

        apply(remembered)
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Call as the app launches: listens to `Transaction.updates`, resolves the right, then loads the catalog.
    public func start() async {
        guard !hasStarted else { return }

        hasStarted = true

        listenForUpdates()

        let timeout = resolveTimeout
        let cap = Task { [weak self] in
            try? await Task.sleep(for: timeout)

            guard !Task.isCancelled else { return }

            self?.resolveAsFreeIfUnknown()
        }

        await refresh()

        cap.cancel()
        resolveAsFreeIfUnknown()

        await loadProducts()
    }

    /// Asks StoreKit again; call when the app returns to the foreground. A subscription that renewed, lapsed or was
    /// cancelled outside the app doesn't always come through `Transaction.updates`.
    ///
    /// - Returns: `false` when StoreKit gave no answer and the remembered right was kept.
    @discardableResult
    public func refresh() async -> Bool {
        await refresh(evidence: nil)
    }

    /// Holds `kind` until the process ends, whatever StoreKit says. For QA and store screenshots: the caller decides
    /// when (a DEBUG launch argument). Transactions are still finished; nothing is remembered.
    public func force(_ kind: EntitlementKind) {
        forced = kind

        apply(kind)
    }

    // MARK: - Products

    public func loadProducts() async {
        if let productsTask {
            await productsTask.value

            return
        }

        let task = Task { await fetchProducts() }

        productsTask = task

        await task.value

        productsTask = nil
    }

    /// Call when the paywall opens and when the app returns to the foreground: a load that failed at launch (a network
    /// handoff, the app opened from the lock screen) would otherwise keep the paywall on its error card for the whole
    /// process.
    public func reloadProductsIfFailed() async {
        guard productsState == .failed else { return }

        await loadProducts()
    }

    public func product(for plan: ProPlan) -> ProProduct? {
        products.first { $0.plan.productID == plan.productID }
    }

    // MARK: - Purchase and restore

    /// Shows the purchase sheet and returns how it ended. Only a verified purchase grants Pro.
    public func purchase(_ product: ProProduct) async -> PurchaseOutcome {
        let startedAt = Date.now

        do {
            switch try await gateway.purchase(product) {
            case .success(let transaction):
                await refresh(evidence: transaction)
                await gateway.finish(transaction)

                let alreadyOwned = EntitlementResolver.isAlreadyOwned(
                    purchaseDate: transaction.purchaseDate,
                    purchaseStartedAt: startedAt
                )

                return PurchaseOutcome(result: alreadyOwned ? .alreadyOwned : .purchased, transaction: transaction)

            case .pending:
                return PurchaseOutcome(result: .pending)

            case .userCancelled:
                return PurchaseOutcome(result: .cancelled)
            }
        } catch {
            return PurchaseOutcome(result: .failed, error: error)
        }
    }

    /// `AppStore.sync()` and a fresh look at the right.
    ///
    /// - Returns: `false` when the App Store couldn't confirm (offline, sign-in cancelled) and the user isn't Pro:
    ///   then "nothing to restore" would be a lie to someone who bought on another device.
    public func restore() async -> Bool {
        var synced = true

        do {
            try await gateway.sync()
        } catch {
            synced = false
        }

        await refresh()

        return synced || isPro
    }

    // MARK: - Resolution

    private func listenForUpdates() {
        let updates = gateway.transactionUpdates()

        updatesTask = Task { [weak self] in
            for await transaction in updates {
                guard let self else { return }

                await refresh(evidence: transaction)
                await gateway.finish(transaction)
            }
        }
    }

    @discardableResult
    private func refresh(evidence: StoreTransaction?) async -> Bool {
        guard forced == nil else { return true }

        let previous = refreshTail
        let task = Task { [weak self] () -> Bool in
            _ = await previous?.value

            return await self?.resolveFromStoreKit(evidence: evidence) ?? false
        }

        refreshTail = task

        return await task.value
    }

    private func resolveFromStoreKit(evidence: StoreTransaction?) async -> Bool {
        let current = resolver.merging(evidence, into: await gateway.currentEntitlements())
        let now = Date.now
        let entitling = current.filter { resolver.entitles($0, at: now) }
        let resolved = resolver.resolve(entitling, at: now)

        if resolved != .none {
            await confirm(resolved, active: entitling)

            return true
        }

        let history = resolver.merging(evidence, into: await gateway.latestTransactions(for: resolver.productIDs))
        let entitlingHistory = history.filter { resolver.entitles($0, at: now) }
        let fromHistory = resolver.resolve(entitlingHistory, at: now)

        if fromHistory != .none {
            await confirm(fromHistory, active: entitlingHistory)
            reportKeptPro(.transactionHistory)

            return true
        }

        if let confirmed, confirmed.isActive(at: now), !resolver.isRefunded(confirmed, by: history) {
            apply(confirmed)
            reportKeptPro(.lastConfirmed)

            return false
        }

        // Nothing entitles, and nothing remembered is left to protect: a refund proven, a period that ran out, or no
        // purchase ever.
        await confirm(.none, active: [])

        return true
    }

    private func confirm(_ kind: EntitlementKind, active: [StoreTransaction]) async {
        apply(kind)

        confirmed = kind
        memory.save(kind)

        await observer?.onConfirmed(active)
    }

    private func apply(_ kind: EntitlementKind) {
        let applied = forced ?? kind

        known = applied
        observer?.onEntitlement(applied)
    }

    private func resolveAsFreeIfUnknown() {
        guard known == nil else { return }

        apply(.none)
    }

    private func reportKeptPro(_ source: KeptProSource) {
        guard !hasReportedKeptPro else { return }

        hasReportedKeptPro = true
        observer?.onProKeptWithoutAnswer(source: source)
    }

    private func fetchProducts() async {
        if products.isEmpty { productsState = .loading }

        let answer = await gateway.products(for: resolver.plans)

        if !answer.products.isEmpty {
            products = answer.products.sorted { $0.price < $1.price }
        }

        productsState = products.isEmpty ? .failed : .loaded

        if let failure = answer.failure {
            observer?.onProductsLoadFailed(failure, error: answer.error)
        }
    }
}
