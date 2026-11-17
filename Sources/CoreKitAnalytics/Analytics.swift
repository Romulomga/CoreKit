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

    /// The user's switch ("Enviar estatísticas"), every engine at once. Call it at launch with the
    /// saved choice, before `start`: off, no engine is set up, so nothing leaves the device, not even
    /// the launch events. Turned on later, the engines start then; turned off, each engine switches
    /// its SDK's collection off (it persists on the device) and nothing more is forwarded. The
    /// build's policy still wins: a debug build never collects.
    @MainActor
    public static func setCollectionEnabled(_ enabled: Bool) {
        hub.setCollectionEnabled(enabled)
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
        /// The user's switch; on until the app says otherwise.
        var isEnabled = true
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    // The engines' bookkeeping is read and written only by `start` and `setCollectionEnabled`, both
    // `@MainActor`; the forwarding methods, called from any thread, read only `state`, behind its lock.

    /// The engines the policy allowed, kept to start them when the user turns collection on later.
    private nonisolated(unsafe) var allowedEngines: [AnalyticsEngine] = []

    /// The engines that started and returned a client: the ones the user's switch reaches.
    private nonisolated(unsafe) var runningEngines: [AnalyticsEngine] = []

    /// The allowed engines were asked to start, once; one without a key is not asked again.
    private nonisolated(unsafe) var didStartEngines = false

    /// Every call goes to the started engines while the user's switch is on, and nowhere otherwise.
    private var clients: [any AnalyticsClient] {
        state.withLock { $0.isEnabled ? $0.clients : [] }
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

        allowedEngines = engines

        guard state.withLock({ $0.isEnabled }) else {
            engines.forEach { $0.stayOff() }

            analyticsLog.notice("Analytics off: the user switched collection off")
            return
        }

        startEngines()
    }

    @MainActor
    private func startEngines() {
        didStartEngines = true

        var running: [AnalyticsEngine] = []
        var started: [any AnalyticsClient] = []

        for engine in allowedEngines {
            if let client = engine.start() {
                running.append(engine)
                started.append(client)
            }
        }

        runningEngines = running
        state.withLock { [started] in $0.clients = started }

        let startedCount = started.count
        let allowedCount = allowedEngines.count
        analyticsLog.notice("Analytics collecting with \(startedCount, privacy: .public) of \(allowedCount, privacy: .public) engine(s)")
    }

    @MainActor
    func setCollectionEnabled(_ enabled: Bool) {
        let wasEnabled = state.withLock { state in
            defer { state.isEnabled = enabled }

            return state.isEnabled
        }

        guard enabled != wasEnabled else { return }

        if enabled, !didStartEngines, !allowedEngines.isEmpty {
            startEngines()
        } else {
            runningEngines.forEach { $0.setCollectionEnabled(enabled) }
        }
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

    /// Only the domain and the code travel: the message, the underlying error and the rest of the
    /// user info may quote what the user typed.
    func recordError(_ error: any Error, context: String?) {
        let error = error as NSError
        let bare = NSError(domain: error.domain, code: error.code)

        clients.forEach { $0.recordError(bare, context: context) }
    }

    func logTransaction(_ transaction: StoreKit.Transaction) {
        clients.forEach { $0.logTransaction(transaction) }
    }

    func logPurchase(_ purchase: PurchaseRevenue) {
        clients.forEach { $0.logPurchase(purchase) }
    }
}
