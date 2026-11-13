import Foundation
import os
import StoreKit

/// The app's analytics, started once at launch:
///
///     Analytics.start(engines: [.firebase(options: .bundled)], policy: .storeBuildsOnly)
///
/// Call it from `application(_:didFinishLaunchingWithOptions:)`, before the first event: what is
/// logged earlier is dropped, as Firebase did before `configure()`.
public enum Analytics {
    /// The client every call site uses: the store, the environment's default, a notification
    /// delegate. It forwards to the engines `start` set up, so a client captured before `start`
    /// (a `@State` store built in `App.init`, which runs before the app delegate) still reaches
    /// them, and nothing has to decide between the real client and a no-op at each call site.
    public static let shared: any AnalyticsClient = hub

    static let hub = AnalyticsHub()

    /// Sets the engines up when the policy collects, and only then: an SDK that is never set up
    /// sends nothing, while turning collection off after setting it up came too late (the launch
    /// events were already out). The first call wins; a second is ignored.
    @MainActor
    public static func start(engines: [AnalyticsEngine], policy: CollectionPolicy) {
        hub.start(engines: engines, policy: policy, launch: .current)
    }

    /// Whether some engine is collecting in this process, for a call the app makes straight to an
    /// SDK (an identity `CoreKit` doesn't model): calling an SDK that was never set up can trap.
    public static var isCollecting: Bool { hub.isCollecting }
}

package let analyticsLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CoreKit", category: "Analytics")

// MARK: - Hub

/// The fan-out behind `Analytics.shared`: every call goes to every engine that started.
final class AnalyticsHub: AnalyticsClient {
    private struct State: Sendable {
        var isStarted = false
        var clients: [any AnalyticsClient] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    private var clients: [any AnalyticsClient] {
        state.withLock { $0.clients }
    }

    var isCollecting: Bool { !clients.isEmpty }

    @MainActor
    func start(engines: [AnalyticsEngine], policy: CollectionPolicy, launch: LaunchContext) {
        let wasStarted = state.withLock { state in
            defer { state.isStarted = true }

            return state.isStarted
        }

        guard !wasStarted else {
            analyticsLog.fault("Analytics.start called twice; the second call is ignored")
            return
        }

        guard policy.allowsCollection(in: launch) else {
            engines.forEach { $0.stayOff() }

            analyticsLog.notice("Analytics off in this build (launch with \(CollectionPolicy.debugArgument, privacy: .public) to trace events)")
            return
        }

        let started = engines.compactMap { $0.start() }

        state.withLock { $0.clients = started }

        analyticsLog.notice("Analytics collecting with \(started.count, privacy: .public) of \(engines.count, privacy: .public) engine(s)")
    }

    func log(_ name: String, parameters: [String: AnalyticsValue]) {
        clients.forEach { $0.log(name, parameters: parameters) }
    }

    func screen(_ name: String) {
        clients.forEach { $0.screen(name) }
    }

    func setUserProperty(_ value: String?, forName name: String) {
        clients.forEach { $0.setUserProperty(value, forName: name) }
    }

    func recordError(_ error: any Error, context: String?) {
        clients.forEach { $0.recordError(error, context: context) }
    }

    func logTransaction(_ transaction: StoreKit.Transaction) {
        clients.forEach { $0.logTransaction(transaction) }
    }

    func logPurchase(_ purchase: PurchaseRevenue) {
        clients.forEach { $0.logPurchase(purchase) }
    }
}
