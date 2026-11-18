@testable import CoreKitSync
import Foundation
import Testing

/// The rules every synced subject gets from the engine: order, retries without duplicates, refusals, what a pull may
/// touch, one run at a time, the cursor, the end of the session. Twin of CoreKit-Android's `SyncEngineTest`.
@MainActor
@Suite struct SyncEngineTests {
    let subject = FakeSubject()
    let outbox = MemoryOutbox()
    let sleeper = SleepSpy()
    var clock = Date(timeIntervalSince1970: 1_000_000)

    func engine(retry: SyncRetry = SyncRetry()) -> SyncEngine<FakeSubject, SyncFailure> {
        let now = clock
        return SyncEngine(subject: subject, outbox: outbox, mapError: SyncFailure.map, retry: retry, now: { now }, sleep: sleeper.sleep)
    }

    // MARK: - Sending

    @Test func sendsTheOutboxOldestFirstBeforeReading() async {
        _ = outbox.queue("b", at: 2)
        _ = outbox.queue("a", at: 1)
        let engine = engine()

        #expect(await engine.sync() == nil)

        #expect(subject.events == ["push a", "push b", "pull"])
        #expect(outbox.changes.isEmpty)
        #expect(engine.status.pendingCount == 0)
    }

    /// The answer was lost on the way: the same change goes again, with the same id, so the server applies it once.
    @Test func aChangeThatFailedOnTheWayGoesAgainWithTheSameID() async {
        let change = outbox.queue("a", at: 1)
        subject.pushAnswer = { _ in throw SyncFailure.offline }
        let engine = engine()

        #expect(await engine.sync() == .offline)
        #expect(outbox.changes.map(\.attempts) == [1], "it stays, one attempt counted")
        #expect(engine.status.pendingCount == 1)
        #expect(!subject.events.contains("pull"), "no read after a send that failed on the way")

        subject.pushAnswer = { _ in .accepted }
        #expect(await engine.sync() == nil)

        #expect(subject.pushed.map(\.id) == [change.id, change.id])
        #expect(outbox.changes.isEmpty)
    }

    /// The record's later changes wait for the app to resolve the refused one; other records go on.
    @Test func aRefusedChangeHoldsTheRecordsLaterChanges() async {
        let refused = outbox.queue("a", at: 1)
        _ = outbox.queue("a", at: 2)
        _ = outbox.queue("b", at: 3)
        subject.pushAnswer = { $0.id == refused.id ? .rejected(reason: "invalid") : .accepted }
        let engine = engine()

        #expect(await engine.sync() == nil)

        #expect(subject.pushed.map(\.entityID) == ["a", "b"])
        #expect(outbox.changes.map(\.entityID) == ["a", "a"])
        #expect(outbox.changes.first?.rejection == "invalid")
        #expect(engine.status.rejectedCount == 1)
        #expect(engine.status.pendingCount == 1)

        await engine.sync()
        #expect(subject.pushed.count == 2, "nothing of the record goes while the refusal stands")
    }

    @Test func aLocalWriteWhileARunIsOnItsWayGoesBeforeTheRunEnds() async {
        subject.pullGate.hold()
        let engine = engine()
        let syncing = Task { await engine.sync() }
        await waitUntil { subject.pullGate.waitingCount == 1 }

        _ = outbox.queue("a", at: 1)
        let pushing = Task { await engine.pushPending() }
        await waitUntil { engine.status.pendingCount == 1 }
        subject.pullGate.release()
        _ = await syncing.value
        await pushing.value

        #expect(subject.pushed.map(\.entityID) == ["a"])
        #expect(outbox.changes.isEmpty)
    }

    /// Pull to refresh right after a local write joins the run that only sends: it still reads.
    @Test func aSyncThatJoinsARunThatOnlySendsStillReads() async {
        _ = outbox.queue("a", at: 1)
        subject.pushGate.hold()
        let engine = engine()
        let pushing = Task { await engine.pushPending() }
        await waitUntil { subject.pushGate.waitingCount == 1 }

        let syncing = Task { await engine.sync() }
        await waitUntil { subject.pushGate.waitingCount == 1 && engine.status.isSyncing }
        for _ in 0..<10 { await Task.yield() }
        subject.pushGate.release()
        await pushing.value
        _ = await syncing.value

        #expect(subject.events == ["push a", "pull"])
    }

    // MARK: - Reading

    /// A record with a change waiting keeps the local version: the change goes first and the server decides.
    @Test func aPullLeavesARecordWithAChangeWaitingAlone() async {
        subject.rows = ["a": Row(entityID: "a", name: "local"), "c": Row(entityID: "c", name: "gone")]
        _ = outbox.queue("a", at: 1)
        subject.pushAnswer = { _ in throw SyncFailure.offline }
        let engine = engine()
        await engine.sync()

        subject.pushAnswer = { _ in .rejected(reason: "held") }
        subject.pulls = [PullBatch(records: [Row(entityID: "a", name: "server"), Row(entityID: "b", name: "new")], cursor: "1", shape: .fullList)]
        await engine.sync()

        #expect(subject.rows["a"]?.name == "local")
        #expect(subject.rows["b"]?.name == "new")
        #expect(subject.rows["c"] == nil, "a full list removes what it does not bring")
        #expect(subject.applied.last?.keeping == ["a"])
    }

    @Test func withServerWinsThePullReplacesTheRecordAndItsChangesGo() async {
        subject.conflictPolicy = .serverWins
        subject.rows = ["a": Row(entityID: "a", name: "local")]
        _ = outbox.queue("a", at: 1)
        subject.pushAnswer = { _ in .rejected(reason: "conflict") }
        subject.pulls = [PullBatch(records: [Row(entityID: "a", name: "server")], cursor: "1", shape: .changes)]
        let engine = engine()

        await engine.sync()

        #expect(subject.rows["a"]?.name == "server")
        #expect(outbox.changes.isEmpty)
        #expect(engine.status.rejectedCount == 0)
    }

    @Test func theCursorMovesPageByPageWithTheData() async {
        subject.state = SyncState(cursor: "0")
        subject.pulls = [
            PullBatch(records: [Row(entityID: "a", name: "1")], cursor: "1", shape: .changes, hasMore: true),
            PullBatch(records: [Row(entityID: "b", name: "2")], removed: ["a"], cursor: "2", shape: .changes),
        ]
        let engine = engine()

        await engine.sync()

        #expect(subject.pullCursors == ["0", "1"])
        #expect(subject.state.cursor == "2")
        #expect(subject.rows.keys.sorted() == ["b"])
        #expect(engine.status.syncedAt == clock)
    }

    /// A pull that fails writes nothing: the cursor stays, and the engine tries again on its own after the wait.
    @Test func aFailedPullKeepsTheCursorAndTriesAgainLater() async {
        subject.state = SyncState(cursor: "5")
        subject.pullFailure = SyncFailure.offline
        let engine = engine(retry: SyncRetry(base: .seconds(5), max: .seconds(300)))

        #expect(await engine.sync() == .offline)

        #expect(subject.applied.isEmpty)
        #expect(subject.state.cursor == "5")
        #expect(engine.status.lastFailure == .offline)
        await waitUntil { sleeper.delays == [.seconds(5)] }

        subject.pullFailure = nil
        #expect(await engine.sync() == nil)
        #expect(engine.status.lastFailure == nil)
    }

    @Test func aCancellationIsNotAFailure() async {
        subject.pullFailure = CancellationError()
        let engine = engine()

        #expect(await engine.sync() == nil)
        #expect(engine.status.lastFailure == nil)
        #expect(sleeper.delays.isEmpty, "nothing to try again")
    }

    // MARK: - One at a time

    @Test func callersAtTheSameTimeWaitForTheSameRun() async {
        subject.pullGate.hold()
        let engine = engine()

        let first = Task { await engine.sync() }
        await waitUntil { subject.pullGate.waitingCount == 1 }
        let second = Task { await engine.sync() }
        await waitUntil { engine.status.isSyncing }
        subject.pullGate.release()
        _ = await first.value
        _ = await second.value

        #expect(subject.pullCursors.count == 1)
        #expect(!engine.status.isSyncing)
    }

    // MARK: - When

    @Test func aFreshCopyIsLeftAloneAndAStaleOneIsReadAgain() async {
        subject.state = SyncState(cursor: "1", syncedAt: clock.addingTimeInterval(-3600))
        let engine = engine()

        await engine.syncIfStale(maxAge: .seconds(86_400))
        #expect(subject.pullCursors.isEmpty)

        await engine.syncIfStale(maxAge: .seconds(1800))
        #expect(subject.pullCursors == ["1"])
    }

    @Test func theNetworkComingBackSyncs() async {
        let engine = engine()
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
        let following = Task { await engine.follow(connectivity: stream) }

        continuation.yield(true)
        continuation.yield(true)
        continuation.yield(false)
        continuation.yield(true)
        continuation.finish()
        await following.value

        #expect(subject.pullCursors.count == 1, "only offline to online")
    }

    @Test func theWaitDoublesUpToTheMaximum() {
        let retry = SyncRetry(base: .seconds(5), max: .seconds(30))

        #expect((1...5).map(retry.delay(afterFailures:)) == [.seconds(5), .seconds(10), .seconds(20), .seconds(30), .seconds(30)])
    }

    // MARK: - End of the session

    @Test func theEndOfTheSessionEmptiesTheQueueAndDropsARunOnItsWay() async throws {
        _ = outbox.queue("other", at: 1)
        subject.state = SyncState(cursor: "9", syncedAt: clock)
        subject.pulls = [PullBatch(records: [Row(entityID: "a", name: "old user")], cursor: "10", shape: .changes)]
        subject.pullGate.hold()
        let engine = engine()
        let syncing = Task { await engine.sync() }
        await waitUntil { subject.pullGate.waitingCount == 1 }

        try engine.reset()
        subject.pullGate.release()
        _ = await syncing.value

        #expect(outbox.changes.isEmpty)
        #expect(subject.state == SyncState())
        #expect(subject.applied.isEmpty, "the previous user's answer never lands")
        #expect(engine.status == SyncStatus())
    }

    /// The outbox is the app's, in its database: a new engine (the app opened again) sends what the last one left.
    @Test func aNewEngineSendsWhatTheLastOneLeft() async {
        _ = outbox.queue("a", at: 1)
        subject.pushAnswer = { _ in throw SyncFailure.offline }
        await engine().sync()

        subject.pushAnswer = { _ in .accepted }
        let reopened = engine()
        #expect(reopened.status.pendingCount == 1)
        await reopened.sync()

        #expect(outbox.changes.isEmpty)
    }
}
