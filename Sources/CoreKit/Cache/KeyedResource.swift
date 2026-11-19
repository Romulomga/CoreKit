import Foundation
import Observation

/// Values read from the server, one per key, kept in memory until `clear()`: the building block of an app's
/// repositories for data that lives on the server (the "online" way of a subject). Twin of CoreKit-Android's
/// `KeyedResource`.
///
/// Every fetch runs in a task of its own: leaving a screen stops its reading, never the fetch, and callers at the same
/// time wait for the same task (not `SingleFlight`, which would drop the second caller). An answer that left before a
/// newer fetch, a write or `clear()` is dropped when it lands.
///
/// `mapError` turns what a fetch threw into the app's failure; returning `nil` says it was a cancellation (an app's
/// network layer may report one in its own error type), which never counts as a failure.
@MainActor
@Observable
public final class KeyedResource<Key: Hashable & Sendable, Value: Equatable & Sendable, Failure: Error & Equatable & Sendable> {
    public private(set) var entries: [Key: Loadable<Value, Failure>] = [:]

    @ObservationIgnored private let fetch: @MainActor (Key) async throws -> Value

    @ObservationIgnored private let mapError: (any Error) -> Failure?

    @ObservationIgnored private var tasks: [Key: Task<Failure?, Never>] = [:]

    /// Per key: goes up on every fetch and every write, so an answer that left before is dropped.
    @ObservationIgnored private var generations: [Key: Int] = [:]

    /// Goes up on `clear()`: an answer that left for the previous session is dropped when it lands.
    @ObservationIgnored private var epoch = 0

    public init(mapError: @escaping (any Error) -> Failure?, fetch: @escaping @MainActor (Key) async throws -> Value) {
        self.mapError = mapError
        self.fetch = fetch
    }

    /// The entries observed, or not (`CacheRead`).
    public func entries(_ read: CacheRead) -> [Key: Loadable<Value, Failure>] {
        read == .tracked ? entries : _entries
    }

    public func entry(_ key: Key) -> Loadable<Value, Failure> {
        entries[key] ?? Loadable()
    }

    /// A screen shows the value: fetched the first time (or after a load cut short, or one that failed), never again
    /// once loaded. Idempotent, so a screen calls it every time it appears.
    public func load(_ key: Key) {
        guard entry(key).status.asksOnOpening, tasks[key] == nil else { return }

        start(key)
    }

    /// "Tentar de novo" and pull to refresh: joins the fetch on its way (and the one that replaced it). The failure is
    /// for a toast; a value on screen stays.
    @discardableResult
    public func refresh(_ key: Key) async -> Failure? {
        var task = tasks[key] ?? start(key)
        var generation = generations[key, default: 0]
        let epoch = epoch

        while true {
            let outcome = await task.value

            guard epoch == self.epoch, generation != generations[key, default: 0], let newer = tasks[key] else { return outcome }

            task = newer
            generation = generations[key, default: 0]
        }
    }

    /// Something may have changed on the server (a write that timed out, another screen's write): a value ever loaded is
    /// read again without the skeleton; one never asked for waits for its screen.
    public func invalidate(_ key: Key) {
        guard entry(key).status != .idle else { return }

        start(key)
    }

    public func invalidateAll() {
        for key in entries.keys { invalidate(key) }
    }

    /// A screen opens and must not show what was kept (an app whose screens always read from scratch on opening): the
    /// value goes, a fetch on its way is let go, and the key is read again under its skeleton. `invalidate` is the
    /// quiet one, with the value on screen.
    public func reload(_ key: Key) {
        drop(key)
        entries[key] = Loadable()
        start(key)
    }

    /// The server confirmed a write: the cache takes its result, and a read that left before is dropped.
    public func set(_ value: Value, for key: Key) {
        drop(key)
        entries[key] = Loadable(value: value, status: .loaded)
    }

    /// A change in place of a value already here (a follow, a counter).
    public func update(_ key: Key, _ change: (inout Value) -> Void) {
        guard var value = entries[key]?.value else { return }

        change(&value)
        entries[key]?.value = value
    }

    public func updateAll(_ change: (inout Value) -> Void) {
        for key in entries.keys { update(key, change) }
    }

    /// The session ended: nothing stays, and answers still on their way are dropped.
    public func clear() {
        epoch += 1

        for task in tasks.values { task.cancel() }

        tasks = [:]
        entries = [:]
    }

    // MARK: - Fetch

    private func drop(_ key: Key) {
        tasks[key]?.cancel()
        tasks[key] = nil
        generations[key, default: 0] += 1
    }

    @discardableResult
    private func start(_ key: Key) -> Task<Failure?, Never> {
        drop(key)

        let generation = generations[key, default: 0]
        let epoch = epoch
        var entry = entry(key)
        let before = entry.status

        if entry.value == nil { entry.status = .loading }

        entries[key] = entry

        let task = Task { [weak self] () -> Failure? in
            await self?.run(key, generation: generation, epoch: epoch, before: before)
        }

        tasks[key] = task

        return task
    }

    private func run(_ key: Key, generation: Int, epoch: Int, before: LoadStatus<Failure>) async -> Failure? {
        let isCurrent = { [unowned self] in epoch == self.epoch && generation == generations[key, default: 0] }

        defer { if isCurrent() { tasks[key] = nil } }

        do {
            let value = try await fetch(key)

            try Task.checkCancellation()

            guard isCurrent() else { return nil }

            entries[key] = Loadable(value: value, status: .loaded)

            return nil
        } catch {
            let failure = isCancellation(error) ? nil : mapError(error)

            guard isCurrent() else { return nil }

            guard let failure else {
                // Only a newer fetch, a write or the end of the session cancels it: a half load is never "loaded".
                if entry(key).status == .loading { entries[key]?.status = before == .loaded ? .loaded : .idle }

                return nil
            }

            // Read before the write: an assignment through `entries[key]?` that reads `entries` is an access conflict.
            let status: LoadStatus<Failure> = entry(key).value == nil ? .failed(failure) : .loaded

            entries[key]?.status = status

            return failure
        }
    }
}

extension KeyedResource where Key == SingleKey {
    public var value: Loadable<Value, Failure> { entry(.value) }

    public func value(_ read: CacheRead) -> Loadable<Value, Failure> { entries(read)[.value] ?? Loadable() }

    public func load() { load(.value) }

    @discardableResult
    public func refresh() async -> Failure? { await refresh(.value) }
}
