import Foundation
import os

/// Where the visible route is reported (tab switch, push, pop, sheet, cover), for crash
/// breadcrumbs or telemetry: a crash report that says which screen was up. CoreKit only reports;
/// the app decides where it goes (`observe(_:)` once at launch). What a destination reports is its
/// `routeName`. More than one place can listen (analytics and a crash reporter): each extra one
/// joins with `addObserver(_:)` and leaves with `removeObserver(_:)`.
///
/// The observers live in a lock-protected `static let`, not in a mutable global. Twin of the CoreKit-Android
/// `NavigationDiagnostics` (0.1.18), whose `ReportVisibleRoute` reports the top of the selected tab.
public enum NavigationDiagnostics {

    public typealias Observer = @MainActor @Sendable (String) -> Void

    /// What `addObserver(_:)` returns, to remove that observer later.
    public struct Token: Hashable, Sendable {
        fileprivate let id = UUID()
    }

    private struct Observers {
        var main: Observer?
        var extra: [Token: Observer] = [:]
    }

    private static let observers = OSAllocatedUnfairLock(initialState: Observers())

    /// Replaces the main observer (`nil` stops it); the ones added with `addObserver(_:)` stay.
    public static func observe(_ handler: Observer?) {
        observers.withLock { $0.main = handler }
    }

    /// Adds one more observer, next to the main one.
    @discardableResult
    public static func addObserver(_ handler: @escaping Observer) -> Token {
        let token = Token()

        observers.withLock { $0.extra[token] = handler }

        return token
    }

    public static func removeObserver(_ token: Token) {
        _ = observers.withLock { $0.extra.removeValue(forKey: token) }
    }

    @MainActor
    public static func report(route: String) {
        let current = observers.withLock { [$0.main].compactMap { $0 } + Array($0.extra.values) }

        current.forEach { $0(route) }
    }
}
