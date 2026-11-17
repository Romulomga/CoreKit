import Foundation

/// What a repository hands its screens: a value, empty until something is read.
public protocol CacheSnapshot: Equatable, Sendable {
    init()
}

/// A repository of what the screens read from the server, kept in memory, one per container, emptied when the session
/// ends (the container keeps each one in `SessionCaches` as it builds it). A repository gives its snapshot and its
/// `clear()`; the observed and the untracked value and the flow of values come from here. Twin of CoreKit-Android's
/// `SessionCache`.
@MainActor
public protocol SessionCache<Snapshot>: AnyObject {
    associatedtype Snapshot: CacheSnapshot

    /// The cache now, read as `read` says.
    func snapshot(_ read: CacheRead) -> Snapshot

    /// The session ended: nothing stays, and answers still on their way are dropped.
    func clear()
}

extension SessionCache {
    /// The cache now, observed: a SwiftUI body or `values(_:)` that reads it redraws when it moves.
    public var snapshot: Snapshot { snapshot(.tracked) }

    /// The same value without observing it: for a view model's `init`.
    public var untrackedSnapshot: Snapshot { snapshot(.untracked) }

    /// What `read` makes of the cache now, and again on every change that moves it.
    public func values<Value: Sendable & Equatable>(_ read: @escaping @MainActor (Snapshot) -> Value) -> AsyncStream<Value> {
        AsyncStream.observing { [weak self] in
            read(self?.snapshot ?? Snapshot())
        }
    }
}

/// Every cache of the session in one place: the app empties them all when a session ends (logout, a refused token), so
/// nothing of the user who left stays in memory and answers still on their way are dropped. The container keeps each
/// repository here as it builds it (`sessionCaches.keep(XRepository(...))`); one never built holds nothing to empty.
@MainActor
public final class SessionCaches {
    private var caches: [any SessionCache] = []

    public init() {}

    /// How many repositories were kept so far.
    public var count: Int { caches.count }

    /// The repository the container just built, kept to be emptied with the others.
    public func keep<Cache: SessionCache>(_ cache: Cache) -> Cache {
        caches.append(cache)

        return cache
    }

    public func clear() {
        for cache in caches { cache.clear() }
    }
}
