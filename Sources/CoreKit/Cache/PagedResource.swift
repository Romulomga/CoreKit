import Foundation
import Observation

/// What a page asks the server: the offset (`items.count`) for offset/limit endpoints, the number
/// (from 1) for the ones that count pages.
public struct PageRequest: Equatable, Sendable {
    public let offset: Int

    public let number: Int

    public init(offset: Int, number: Int) {
        self.offset = offset
        self.number = number
    }
}

/// A page as the server answered it; `hasMore` is the endpoint's rule (`total`, or a page shorter than the limit).
public struct Page<Item: Sendable>: Sendable {
    public let items: [Item]

    public let hasMore: Bool

    public init(items: [Item], hasMore: Bool) {
        self.items = items
        self.hasMore = hasMore
    }
}

/// One paged list as the server last gave it, deduplicated by id.
public struct PagedList<Item: Identifiable & Equatable & Sendable, Failure: Error & Equatable & Sendable>: Equatable, Sendable {
    public var items: [Item] = []

    public var hasMore = false

    public var status: LoadStatus<Failure> = .idle

    public var isLoadingMore = false

    /// Pages appended since the last restart: the next one is `pages + 1`.
    public var pages = 0

    public init(items: [Item] = [], hasMore: Bool = false, status: LoadStatus<Failure> = .idle, isLoadingMore: Bool = false, pages: Int = 0) {
        self.items = items
        self.hasMore = hasMore
        self.status = status
        self.isLoadingMore = isLoadingMore
        self.pages = pages
    }
}

/// Paged lists read from the server, one per key (a query, a user), kept in memory until `clear()`. Twin of
/// CoreKit-Android's `PagedResource`. `mapError` works as in `KeyedResource`. A restart (pull, retry, a write that may have landed)
/// replaces the first page and lets the next page on its way go; no next page leaves while a restart is on
/// its way (the rows on screen are the old list, and their count would be the offset of the new one);
/// every fetch runs in a task of its own, so leaving the screen never cancels it.
@MainActor
@Observable
public final class PagedResource<Key: Hashable & Sendable, Item: Identifiable & Equatable & Sendable, Failure: Error & Equatable & Sendable>
where Item.ID: Sendable {
    public private(set) var lists: [Key: PagedList<Item, Failure>] = [:]

    /// The lists observed, or not (`CacheRead`).
    public func lists(_ read: CacheRead) -> [Key: PagedList<Item, Failure>] { read == .tracked ? lists : _lists }

    @ObservationIgnored private let fetch: @MainActor (Key, PageRequest) async throws -> Page<Item>

    @ObservationIgnored private let mapError: (any Error) -> Failure?
    @ObservationIgnored private var restarts: [Key: Task<Failure?, Never>] = [:]
    @ObservationIgnored private var nextPages: [Key: Task<Failure?, Never>] = [:]
    /// Per list: goes up on every restart, so a page asked for the list that was replaced is dropped.
    @ObservationIgnored private var generations: [Key: Int] = [:]
    @ObservationIgnored private var epoch = 0

    public init(mapError: @escaping (any Error) -> Failure?, fetch: @escaping @MainActor (Key, PageRequest) async throws -> Page<Item>) {
        self.mapError = mapError
        self.fetch = fetch
    }

    public func list(_ key: Key) -> PagedList<Item, Failure> {
        lists[key] ?? PagedList()
    }

    /// A screen shows the list: the first page the first time (or after a load cut short, or one that failed),
    /// never again once loaded.
    public func load(_ key: Key) {
        guard list(key).status.asksOnOpening, restarts[key] == nil else { return }
        startRestart(key)
    }

    /// Pull to refresh and "Tentar de novo": joins the restart on its way. The error is for a toast; the
    /// rows on screen stay until the new first page lands.
    @discardableResult
    public func refresh(_ key: Key) async -> Failure? {
        var task = restarts[key] ?? startRestart(key)
        var generation = generations[key, default: 0]
        let epoch = epoch
        while true {
            let outcome = await task.value
            guard epoch == self.epoch, generation != generations[key, default: 0], let newer = restarts[key] else { return outcome }
            task = newer
            generation = generations[key, default: 0]
        }
    }

    /// The next page; the error is for a toast. A row's `.task` that asks for it can go: the page lands anyway.
    @discardableResult
    public func loadMore(_ key: Key) async -> Failure? {
        if let running = nextPages[key] { return await running.value }
        let list = list(key)
        guard list.status == .loaded, list.hasMore, restarts[key] == nil else { return nil }
        return await startNextPage(key).value
    }

    /// Something may have changed on the server: a list ever shown reads its first page again, quietly.
    public func invalidate(_ key: Key) {
        guard list(key).status != .idle else { return }
        startRestart(key)
    }

    public func invalidateAll() {
        for key in lists.keys { invalidate(key) }
    }

    /// A screen opens and must not show what was kept: the rows go, the pages on their way are let go, and the first
    /// page is read again under the skeleton. `invalidate` is the quiet one, with the rows on screen.
    public func reload(_ key: Key) {
        lists[key] = PagedList()
        startRestart(key)
    }

    /// Every list that shows the row reads its first page again: a write that may have landed moved it.
    public func invalidateLists(showing id: Item.ID) {
        for (key, list) in lists where list.items.contains(where: { $0.id == id }) { invalidate(key) }
    }

    /// A row changed by a write the server confirmed, in every list that shows it.
    public func updateItem(_ id: Item.ID, _ change: (inout Item) -> Void) {
        for (key, var list) in lists {
            guard let index = list.items.firstIndex(where: { $0.id == id }) else { continue }
            change(&list.items[index])
            lists[key] = list
        }
    }

    /// The session ended: nothing stays, and answers still on their way are dropped.
    public func clear() {
        epoch += 1
        for task in restarts.values { task.cancel() }
        for task in nextPages.values { task.cancel() }
        restarts = [:]
        nextPages = [:]
        lists = [:]
    }

    // MARK: - First page

    @discardableResult
    private func startRestart(_ key: Key) -> Task<Failure?, Never> {
        nextPages[key]?.cancel()
        nextPages[key] = nil
        restarts[key]?.cancel()
        generations[key, default: 0] += 1
        let generation = generations[key, default: 0]
        let epoch = epoch

        var list = list(key)
        let before = list.status
        list.isLoadingMore = false
        if list.items.isEmpty, list.status != .loaded { list.status = .loading }
        lists[key] = list

        let task = Task { [weak self] () -> Failure? in
            await self?.fetchFirstPage(key, generation: generation, epoch: epoch, before: before)
        }
        restarts[key] = task
        return task
    }

    private func fetchFirstPage(_ key: Key, generation: Int, epoch: Int, before: LoadStatus<Failure>) async -> Failure? {
        defer { if isCurrent(key, generation, epoch) { restarts[key] = nil } }
        do {
            let page = try await fetch(key, PageRequest(offset: 0, number: 1))
            try Task.checkCancellation()
            guard isCurrent(key, generation, epoch) else { return nil }
            lists[key] = PagedList(items: Self.unique(page.items), hasMore: page.hasMore, status: .loaded, pages: 1)
            return nil
        } catch {
            let failure = isCancellation(error) ? nil : mapError(error)
            guard isCurrent(key, generation, epoch) else { return nil }
            guard let mapped = failure else {
                if list(key).status == .loading { lists[key]?.status = before == .loaded ? .loaded : .idle }
                return nil
            }
            // Read before the write: an assignment through `lists[key]?` that reads `lists` is an access conflict.
            let status: LoadStatus<Failure> = list(key).items.isEmpty && before != .loaded ? .failed(mapped) : .loaded
            lists[key]?.status = status
            return mapped
        }
    }

    // MARK: - Next page

    private func startNextPage(_ key: Key) -> Task<Failure?, Never> {
        let generation = generations[key, default: 0]
        let epoch = epoch
        lists[key]?.isLoadingMore = true
        let task = Task { [weak self] () -> Failure? in
            await self?.fetchNextPage(key, generation: generation, epoch: epoch)
        }
        nextPages[key] = task
        return task
    }

    private func fetchNextPage(_ key: Key, generation: Int, epoch: Int) async -> Failure? {
        defer {
            // A restart meanwhile already let this page go and may have started its own.
            if isCurrent(key, generation, epoch) {
                lists[key]?.isLoadingMore = false
                nextPages[key] = nil
            }
        }
        let current = list(key)
        do {
            let page = try await fetch(key, PageRequest(offset: current.items.count, number: current.pages + 1))
            try Task.checkCancellation()
            guard isCurrent(key, generation, epoch) else { return nil }
            var list = list(key)
            let known = Set(list.items.map(\.id))
            list.items += Self.unique(page.items.filter { !known.contains($0.id) })
            list.hasMore = page.hasMore
            list.pages += 1
            lists[key] = list
            return nil
        } catch {
            let failure = isCancellation(error) ? nil : mapError(error)
            return isCurrent(key, generation, epoch) ? failure : nil
        }
    }

    private func isCurrent(_ key: Key, _ generation: Int, _ epoch: Int) -> Bool {
        epoch == self.epoch && generation == generations[key, default: 0]
    }

    private static func unique(_ items: [Item]) -> [Item] {
        var seen = Set<Item.ID>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

extension PagedResource where Key == SingleKey {
    public func list(_ read: CacheRead) -> PagedList<Item, Failure> { lists(read)[.value] ?? PagedList() }
}
