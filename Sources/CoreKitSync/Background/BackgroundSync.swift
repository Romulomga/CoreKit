import Foundation
import os

#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// One background run the system granted: the app's work reports how it ended, and the system may take the time back.
public final class BackgroundRun: Sendable {
    private let complete: @Sendable (Bool) -> Void

    private let expiration = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(initialState: nil)

    public init(complete: @escaping @Sendable (Bool) -> Void) {
        self.complete = complete
    }

    /// What runs when the system takes the time back (the work is cancelled).
    public func onExpiration(_ handler: @escaping @Sendable () -> Void) {
        expiration.withLock { $0 = handler }
    }

    public func expire() {
        expiration.withLock { $0 }?()
    }

    public func finish(success: Bool) {
        complete(success)
    }
}

/// The system's background scheduler, behind a seam: `BGTaskScheduler` in the app, a double in the tests.
public protocol BackgroundScheduling: Sendable {
    /// False when the system refused the identifier.
    func register(identifier: String, launch: @escaping @Sendable (BackgroundRun) -> Void) -> Bool

    func submit(identifier: String, earliestBegin: Date) throws
}

/// Background refresh for a sync, as an extra: the system decides when (maybe never), the user can turn it off in
/// Settings, and Low Power Mode holds it. The app syncs on opening, on pull and when the network comes back; this only
/// adds the runs in between.
///
/// It needs two keys in the app's `Info.plist`: `UIBackgroundModes` with `fetch` (the Background Modes capability,
/// "Background fetch") and the identifier in `BGTaskSchedulerPermittedIdentifiers`. Registering an identifier the plist
/// does not list crashes the app, so `register` checks first and, without them, registers nothing, logs why and returns
/// false. Call it before the app finishes launching (`App.init` or the app delegate).
public enum BackgroundSync {
    private static let logger = Logger(subsystem: "io.github.romulomga.corekit", category: "BackgroundSync")

    /// The keys `identifier` needs and `infoPlist` lacks.
    public static func missingKeys(identifier: String, infoPlist: [String: Any]) -> [String] {
        var missing: [String] = []

        if !((infoPlist["UIBackgroundModes"] as? [String]) ?? []).contains("fetch") {
            missing.append("UIBackgroundModes: fetch")
        }

        if !((infoPlist["BGTaskSchedulerPermittedIdentifiers"] as? [String]) ?? []).contains(identifier) {
            missing.append("BGTaskSchedulerPermittedIdentifiers: \(identifier)")
        }

        return missing
    }

    /// Registers `run` under `identifier` and asks for the first run `interval` from now; every run asks for the next.
    /// `run` returns whether it worked, and is cancelled when the system takes the time back.
    @discardableResult
    public static func register(
        identifier: String,
        interval: Duration = .seconds(3600),
        infoPlist: [String: Any] = Bundle.main.infoDictionary ?? [:],
        scheduler: any BackgroundScheduling = SystemBackgroundScheduler(),
        now: @escaping @Sendable () -> Date = { .now },
        run: @escaping @MainActor @Sendable () async -> Bool
    ) -> Bool {
        let missing = missingKeys(identifier: identifier, infoPlist: infoPlist)

        guard missing.isEmpty else {
            logger.error("Background sync not registered, Info.plist lacks: \(missing.joined(separator: ", "), privacy: .public)")
            return false
        }

        let schedule: @Sendable () -> Void = {
            do {
                try scheduler.submit(identifier: identifier, earliestBegin: now().addingTimeInterval(interval.seconds))
            } catch {
                // The simulator and a user who turned background refresh off both refuse it: the app goes on.
                logger.error("Background sync not scheduled: \(String(describing: error), privacy: .public)")
            }
        }

        let registered = scheduler.register(identifier: identifier) { backgroundRun in
            schedule()

            let work = Task { @MainActor in
                let worked = await run()
                backgroundRun.finish(success: worked && !Task.isCancelled)
            }

            backgroundRun.onExpiration { work.cancel() }
        }

        guard registered else {
            logger.error("Background sync not registered: the system refused \(identifier, privacy: .public)")
            return false
        }

        schedule()

        return true
    }
}

#if canImport(BackgroundTasks) && os(iOS)
/// `BGTaskScheduler`, as `BackgroundScheduling`.
public struct SystemBackgroundScheduler: BackgroundScheduling {
    public init() {}

    public func register(identifier: String, launch: @escaping @Sendable (BackgroundRun) -> Void) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            // `BGTask` is not Sendable; it is only touched again to end it, which the system allows from any thread.
            nonisolated(unsafe) let task = task
            let run = BackgroundRun { task.setTaskCompleted(success: $0) }

            task.expirationHandler = { run.expire() }
            launch(run)
        }
    }

    public func submit(identifier: String, earliestBegin: Date) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBegin

        try BGTaskScheduler.shared.submit(request)
    }
}
#endif
