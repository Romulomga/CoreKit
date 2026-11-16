import Observation

/// Runs one async action at a time: a second tap that arrives while the first is still running
/// is ignored.
///
/// Saving, restoring purchases, sending, deleting: once the work is `async`, the button stays on
/// screen until it finishes, and two quick taps ran it twice (two restores, two requests, two
/// rows). Each app guarded it with its own `isSaving` flag, set at slightly different points;
/// the ones set inside the `Task` let the second tap through. The lock here closes synchronously,
/// before any `await`, and opens when the work ends, throws or is cancelled. Twin of
/// CoreKit-Android's `SingleFlight`.
///
/// Bind `isRunning` to the button (`.disabled(saving.isRunning)` or a progress state).
@MainActor
@Observable
public final class SingleFlight {

    /// Whether an action is running now.
    public private(set) var isRunning = false

    public init() {}

    /// Starts `operation` in a new task if nothing is running.
    ///
    /// - Returns: the task, for a caller that awaits or cancels it; `nil` when the call was ignored.
    @discardableResult
    public func launch(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never>? {
        guard !isRunning else { return nil }

        isRunning = true

        return Task { @MainActor in
            defer { isRunning = false }

            await operation()
        }
    }

    /// Runs `operation` in the caller's task if nothing is running.
    ///
    /// - Returns: what `operation` returned; `nil` when the call was ignored.
    @discardableResult
    public func run<T>(_ operation: @MainActor () async throws -> T) async rethrows -> T? {
        guard !isRunning else { return nil }

        isRunning = true
        defer { isRunning = false }

        return try await operation()
    }
}

/// The same lock per key, for row actions (follow, toggle, delete an item of a list): each row
/// has its own, and one row saving doesn't lock the others. Twin of CoreKit-Android's
/// `KeyedSingleFlight`.
@MainActor
@Observable
public final class KeyedSingleFlight<Key: Hashable & Sendable> {

    /// The keys with an action running now.
    public private(set) var running: Set<Key> = []

    public init() {}

    /// Whether an action for `key` is running now.
    public func isRunning(_ key: Key) -> Bool {
        running.contains(key)
    }

    /// Starts `operation` in a new task if nothing is running for `key`.
    ///
    /// - Returns: the task; `nil` when the call was ignored.
    @discardableResult
    public func launch(
        _ key: Key,
        _ operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never>? {
        guard running.insert(key).inserted else { return nil }

        return Task { @MainActor in
            defer { running.remove(key) }

            await operation()
        }
    }

    /// Runs `operation` in the caller's task if nothing is running for `key`.
    ///
    /// - Returns: what `operation` returned; `nil` when the call was ignored.
    @discardableResult
    public func run<T>(_ key: Key, _ operation: @MainActor () async throws -> T) async rethrows -> T? {
        guard running.insert(key).inserted else { return nil }

        defer { running.remove(key) }

        return try await operation()
    }
}
