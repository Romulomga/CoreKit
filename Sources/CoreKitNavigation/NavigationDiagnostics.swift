import Foundation
import os

/// Where the visible route is reported (tab switch, push, pop, sheet, cover), for crash
/// breadcrumbs or telemetry: a crash report that says which screen was up. CoreKit only reports;
/// the app decides where it goes (`observe(_:)` once at launch). What a destination reports is its
/// `routeName`.
///
/// The observer lives in a lock-protected `static let`, not in a mutable global. iOS only for now.
public enum NavigationDiagnostics {

    public typealias Observer = @MainActor @Sendable (String) -> Void

    private static let observer = OSAllocatedUnfairLock<Observer?>(initialState: nil)

    /// Replaces the observer (`nil` stops reporting).
    public static func observe(_ handler: Observer?) {
        observer.withLock { $0 = handler }
    }

    @MainActor
    public static func report(route: String) {
        observer.withLock { $0 }?(route)
    }
}
