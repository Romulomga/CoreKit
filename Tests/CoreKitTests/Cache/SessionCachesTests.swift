@testable import CoreKit
import Foundation
import Testing

/// The end of a session empties every cache kept, and the flow of a repository follows its cache.
@MainActor
@Suite struct SessionCachesTests {

    struct Snapshot: CacheSnapshot {
        var value: Loadable<String, TestFailure> = Loadable()
    }

    final class Repository: SessionCache {
        let resource = KeyedResource<SingleKey, String, TestFailure>(mapError: TestFailure.map) { _ in "value" }

        func snapshot(_ read: CacheRead) -> Snapshot { Snapshot(value: resource.value(read)) }

        func clear() { resource.clear() }
    }

    @Test func theEndOfTheSessionEmptiesEveryCacheKept() async {
        let caches = SessionCaches()
        let first = caches.keep(Repository())
        let second = caches.keep(Repository())

        await first.resource.refresh()
        await second.resource.refresh()

        caches.clear()

        #expect(caches.count == 2)
        #expect(first.snapshot.value.status == .idle)
        #expect(second.snapshot.value.value == nil)
    }

    @Test func theFlowFollowsTheCache() async {
        let repository = Repository()
        var latest: LoadStatus<TestFailure>?

        let reading = Task {
            for await status in repository.values({ $0.value.status }) { latest = status }
        }

        await waitUntil { latest == .idle }
        repository.resource.load()
        await waitUntil { latest == .loaded }
        reading.cancel()
    }
}
