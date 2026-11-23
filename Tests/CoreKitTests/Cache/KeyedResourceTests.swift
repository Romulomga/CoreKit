@testable import CoreKit
import CoreKitTesting
import Foundation
import Testing

/// The building block of an app's server caches: what every repository over it gets for free (one fetch for callers at
/// the same time, a fetch that outlives the screen, the end of the session). Moved from Homer with its tests.
@MainActor
@Suite struct KeyedResourceTests {

    // MARK: - Reads

    /// "Voltar de um push não recarrega": the screen asks every time it shows, the cache answers.
    @Test func loadingTwiceAsksTheServerOnce() async {
        let server = FetchSpy<Int, String> { "value \($0)" }
        let resource = server.resource()

        resource.load(1)
        resource.load(1)
        await waitUntil { resource.entry(1).status == .loaded }
        resource.load(1)
        // A fetch started by that load would reach the server within a few turns: give it them before counting.
        for _ in 0..<20 { await Task.yield() }

        #expect(resource.entry(1).value == "value 1")
        #expect(server.calls == [1])
    }

    @Test func callersAtTheSameTimeWaitForTheSameFetch() async {
        let server = FetchSpy<Int, String> { "value \($0)" }
        server.gate.hold()
        let resource = server.resource()

        resource.load(1)
        let retrying = Task { await resource.refresh(1) }
        await waitUntil { server.gate.waitingCount == 1 }
        server.gate.release()

        #expect(await retrying.value == nil)
        #expect(server.calls == [1])
    }

    /// Leaving the screen stops its reading, never the fetch, and nothing is left half loaded.
    @Test func aFetchOutlivesTheScreenThatAskedForIt() async {
        let server = FetchSpy<Int, String> { "value \($0)" }
        server.gate.hold()
        let resource = server.resource()
        let reading = Task { for await _ in AsyncStream.observing({ resource.entry(1).status }) {} }

        resource.load(1)
        await waitUntil { server.gate.waitingCount == 1 }
        reading.cancel()
        server.gate.release()

        await waitUntil { resource.entry(1).status == .loaded }
        #expect(resource.entry(1).value == "value 1")
    }

    @Test func aRetryAskedByALeavingScreenStillLands() async {
        let server = FetchSpy<Int, String> { "value \($0)" }
        let resource = server.resource()

        await runCancelled { await resource.refresh(1) }

        await waitUntil { resource.entry(1).status == .loaded }
        #expect(resource.entry(1).value == "value 1", "the fetch is the cache's, not the cancelled caller's")
    }

    /// The screen that waits leaves: its wait ends at once (nothing holds it until the server answers), the fetch
    /// lands in the cache, and another caller waiting for the same fetch gets its answer.
    @Test func aCancelledCallerStopsWaitingAndTheFetchStillLandsForTheOthers() async {
        let server = FetchSpy<Int, String> { _ in throw TestFailure.offline }
        server.gate.hold()
        let resource = server.resource()
        let staying = Task { await resource.refresh(1) }
        await waitUntil { server.gate.waitingCount == 1 }
        var leftDone = false
        let leaving = Task {
            let failure = await resource.refresh(1)
            leftDone = true
            return failure
        }
        for _ in 0..<5 { await Task.yield() }

        leaving.cancel()
        await waitUntil { leftDone }
        #expect(server.gate.waitingCount == 1, "it gave up with the fetch still on its way")

        server.gate.release()
        #expect(await leaving.value == nil, "a cancellation is never a failure")
        #expect(await staying.value == .offline, "the other caller gets the fetch's answer")
        #expect(resource.entry(1).status == .failed(.offline))
        #expect(server.calls == [1], "one fetch for both")

        server.answer = { "value \($0)" }
        await runCancelled { await resource.refresh(1) }
        await waitUntil { resource.entry(1).status == .loaded }
        #expect(resource.entry(1).value == "value 1", "a fetch whose only caller left still lands")
    }

    /// A failure with nothing shown is the screen's error; the next opening (or return) asks again, as every
    /// opening always did, and "Tentar de novo" too.
    @Test func aFailureWithNothingShownFailsAndTheNextOpeningOrARetryLoads() async {
        let server = FetchSpy<Int, String> { _ in throw TestFailure.offline }
        let resource = server.resource()

        resource.load(1)
        await waitUntil { resource.entry(1).status == .failed(.offline) }
        resource.load(1)
        await waitUntil { resource.entry(1).status == .failed(.offline) }
        #expect(server.calls == [1, 1], "the next opening asks again")

        server.answer = { "value \($0)" }
        #expect(await resource.refresh(1) == nil)
        #expect(resource.entry(1) == Loadable(value: "value 1", status: .loaded))
        resource.load(1)
        #expect(server.calls == [1, 1, 1], "a value loaded is left alone")
    }

    /// A request cancelled on its way without the cache asking (the request itself gave up) is not an answer: with
    /// nothing shown the key goes back to never asked, not to a failure, and the next opening asks again.
    @Test func aRequestCancelledOnItsWayIsNotAFailure() async {
        let server = FetchSpy<Int, String> { _ in throw CancellationError() }
        let resource = server.resource()

        #expect(await resource.refresh(1) == nil)
        #expect(resource.entry(1).status == .idle)

        server.answer = { "value \($0)" }
        resource.load(1)
        await waitUntil { resource.entry(1).status == .loaded }
        #expect(server.calls == [1, 1])
    }

    @Test func aFailedRefreshKeepsTheValueOnScreen() async {
        let server = FetchSpy<Int, String> { "value \($0)" }
        let resource = server.resource()
        await resource.refresh(1)

        server.answer = { _ in throw TestFailure.server }

        #expect(await resource.refresh(1) == .server)
        #expect(resource.entry(1) == Loadable(value: "value 1", status: .loaded))
    }

    // MARK: - The app's own errors

    /// The app's network layer reports a cancellation in its own error type: `mapError` says so with `nil`, and it is
    /// never a failure.
    @Test func whatTheAppMapsToNilIsACancellationNotAFailure() async {
        let server = FetchSpy<Int, String> { _ in throw TestFailure.appCancelled }
        let resource = server.resource()

        #expect(await resource.refresh(1) == nil)
        #expect(resource.entry(1).status == .idle)
    }

    // MARK: - Writes

    /// A write the server confirmed wins over a read that left before it.
    @Test func aWriteDropsTheReadThatLeftBeforeIt() async {
        let server = FetchSpy<Int, String> { _ in "old" }
        let resource = server.resource()
        await resource.refresh(1)
        server.gate.hold()

        let refreshing = Task { await resource.refresh(1) }
        await waitUntil { server.gate.waitingCount == 1 }
        resource.set("written", for: 1)
        server.gate.release()
        _ = await refreshing.value

        #expect(resource.entry(1).value == "written")
    }

    @Test func anInvalidatedValueIsReadAgainAndOneNeverShownWaits() async {
        let server = FetchSpy<Int, String> { "value \($0)" }
        let resource = server.resource()
        await resource.refresh(1)

        resource.invalidate(1)
        resource.invalidate(2)

        await waitUntil { server.calls == [1, 1] }
        #expect(resource.entry(2).status == .idle)
    }

    /// An opening that must not show what was kept: the value goes at once, the skeleton shows, and an answer of the
    /// fetch that was on its way never lands over the new one.
    @Test func aReloadDropsTheValueAndTheFetchOnItsWay() async {
        let server = FetchSpy<Int, String> { "old \($0)" }
        let resource = server.resource()
        await resource.refresh(1)
        server.gate.hold()
        let before = Task { await resource.refresh(1) }
        await waitUntil { server.gate.waitingCount == 1 }

        server.answer = { "new \($0)" }
        resource.reload(1)

        #expect(resource.entry(1).value == nil, "nothing kept on screen")
        #expect(resource.entry(1).status == .loading)
        server.gate.release()
        _ = await before.value
        await waitUntil { resource.entry(1).status == .loaded }
        #expect(resource.entry(1).value == "new 1")
    }

    @Test func aReloadThatFailsShowsTheErrorNotTheOldValue() async {
        let server = FetchSpy<Int, String> { "old \($0)" }
        let resource = server.resource()
        await resource.refresh(1)

        server.answer = { _ in throw TestFailure.offline }
        resource.reload(1)

        await waitUntil { resource.entry(1).status == .failed(.offline) }
        #expect(resource.entry(1).value == nil)
    }

    // MARK: - End of the session

    @Test func theEndOfTheSessionEmptiesTheCacheAndDropsAnswersOnTheirWay() async {
        let server = FetchSpy<Int, String> { "value \($0)" }
        let resource = server.resource()
        await resource.refresh(1)
        server.gate.hold()

        let refreshing = Task { await resource.refresh(2) }
        await waitUntil { server.gate.waitingCount == 1 }
        resource.clear()
        #expect(resource.entries.isEmpty)

        server.gate.release()
        _ = await refreshing.value
        #expect(resource.entries.isEmpty, "the previous user's answer never lands")
    }
}

/// A fetch closure the test scripts: it records the keys, waits at the gate, then answers.
@MainActor
final class FetchSpy<Key: Hashable & Sendable, Value: Equatable & Sendable> {
    let gate = TestGate()
    private(set) var calls: [Key] = []
    var answer: @MainActor (Key) throws -> Value

    init(_ answer: @escaping @MainActor (Key) throws -> Value) {
        self.answer = answer
    }

    func fetch(_ key: Key) async throws -> Value {
        calls.append(key)
        await gate.pass()
        try Task.checkCancellation()
        return try answer(key)
    }

    func resource() -> KeyedResource<Key, Value, TestFailure> {
        KeyedResource(mapError: TestFailure.map) { [self] key in try await fetch(key) }
    }
}
