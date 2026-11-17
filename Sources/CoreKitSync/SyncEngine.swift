import Foundation
import Observation

/// Where a subject's sync stands, for the screens: "Atualizado há 3 h", "2 alterações esperando conexão".
public struct SyncStatus<Failure: Error & Equatable & Sendable>: Equatable, Sendable {
    public var syncedAt: Date?

    public var isSyncing = false

    /// Changes waiting to go (refused ones not counted).
    public var pendingCount = 0

    /// Changes the server refused, waiting for the app to resolve them.
    public var rejectedCount = 0

    /// The last run's failure; `nil` once a run works.
    public var lastFailure: Failure?

    public init(syncedAt: Date? = nil) {
        self.syncedAt = syncedAt
    }
}

/// How long a failed run waits before the engine tries again on its own: doubling from `base`, at most `max`.
public struct SyncRetry: Sendable, Equatable {
    public let base: Duration

    public let max: Duration

    public init(base: Duration = .seconds(5), max: Duration = .seconds(300)) {
        self.base = base
        self.max = max
    }

    /// The wait after `failures` runs in a row failed (1 is the first).
    public func delay(afterFailures failures: Int) -> Duration {
        let doubled = base * Int(pow(2, Double(Swift.max(0, failures - 1))))

        return Swift.min(doubled, max)
    }
}

/// Runs one subject's sync: sends the outbox first (oldest first, the record's later changes after its earlier ones),
/// then reads from the cursor and hands the subject what it may write. One run at a time: a caller while a run is on its
/// way waits for that run (not `SingleFlight`, which would drop it). Twin of CoreKit-Android's `SyncEngine`.
///
/// When it runs is the app's: `syncIfStale` on opening, `sync` on pull to refresh, `pushPending` after a local write,
/// `follow(connectivity:)` when the network comes back, and `BackgroundSync` as an extra. A run that fails on the way
/// tries again on its own after `SyncRetry`.
///
/// `mapError` turns what failed into the app's failure; `nil` says it was a cancellation, which is never a failure.
@MainActor
@Observable
public final class SyncEngine<Subject: SyncSubject, Failure: Error & Equatable & Sendable> {
    public private(set) var status: SyncStatus<Failure>

    @ObservationIgnored private let subject: Subject

    @ObservationIgnored private let outbox: any Outbox

    @ObservationIgnored private let mapError: (any Error) -> Failure?

    @ObservationIgnored private let retry: SyncRetry

    @ObservationIgnored private let now: @MainActor () -> Date

    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    @ObservationIgnored private var running: Task<Failure?, Never>?

    @ObservationIgnored private var retrying: Task<Void, Never>?

    @ObservationIgnored private var failuresInARow = 0

    /// A local write while a run was on its way: the run sends the outbox once more before it ends.
    @ObservationIgnored private var pushAgain = false

    /// Goes up on `reset()`: a run of the previous session ends without writing.
    @ObservationIgnored private var epoch = 0

    public init(
        subject: Subject,
        outbox: any Outbox,
        mapError: @escaping (any Error) -> Failure?,
        retry: SyncRetry = SyncRetry(),
        now: @escaping @MainActor () -> Date = { .now },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.subject = subject
        self.outbox = outbox
        self.mapError = mapError
        self.retry = retry
        self.now = now
        self.sleep = sleep
        status = SyncStatus(syncedAt: subject.state.syncedAt)
        refreshCounts()
    }

    // MARK: - Triggers

    /// Sends, then reads. A caller while a run is on its way waits for it. The failure is for a toast.
    @discardableResult
    public func sync() async -> Failure? {
        if let running { return await running.value }

        return await start(pulling: true).value
    }

    /// Opening a screen: syncs when the copy is older than `maxAge`, or was never read.
    public func syncIfStale(maxAge: Duration) async {
        if let syncedAt = status.syncedAt, now().timeIntervalSince(syncedAt) < maxAge.seconds { return }

        await sync()
    }

    /// The app just queued a change (in the same save as the record): sends it now. A run on its way sends it before it
    /// ends.
    public func pushPending() async {
        refreshCounts()

        if let running {
            pushAgain = true
            _ = await running.value
            return
        }

        _ = await start(pulling: false).value
    }

    /// Syncs every time the network comes back, until the caller's task ends.
    public func follow(connectivity: AsyncStream<Bool>) async {
        var wasOnline: Bool?

        for await isOnline in connectivity {
            defer { wasOnline = isOnline }

            if isOnline, wasOnline == false { await sync() }
        }
    }

    /// The counts again, from the outbox (after the app resolves a refused change).
    public func refreshCounts() {
        let changes = outbox.pending(subject: subject.name)

        status.pendingCount = changes.filter { $0.rejection == nil }.count
        status.rejectedCount = changes.filter { $0.rejection != nil }.count
    }

    /// The session ended: nothing queued stays, the cursor goes, and a run on its way ends without writing.
    public func reset() throws {
        epoch += 1
        running?.cancel()
        running = nil
        retrying?.cancel()
        retrying = nil
        failuresInARow = 0
        pushAgain = false

        try outbox.removeAll(subject: subject.name)
        try subject.resetState()

        status = SyncStatus()
    }

    // MARK: - Run

    private func start(pulling: Bool) -> Task<Failure?, Never> {
        retrying?.cancel()
        retrying = nil
        status.isSyncing = true

        let epoch = epoch
        let task = Task { [weak self] () -> Failure? in
            await self?.run(pulling: pulling, epoch: epoch)
        }

        running = task

        return task
    }

    private func run(pulling: Bool, epoch: Int) async -> Failure? {
        let failure: Failure?

        do {
            try await sendOutbox(epoch: epoch)

            if pulling { try await pull(epoch: epoch) }

            // A local write while the run was on its way goes before it ends.
            while pushAgain, epoch == self.epoch {
                pushAgain = false
                try await sendOutbox(epoch: epoch)
            }

            failure = nil
        } catch {
            failure = Task.isCancelled ? nil : mapError(error)
        }

        guard epoch == self.epoch else { return nil }

        running = nil
        status.isSyncing = false
        refreshCounts()

        if let failure {
            status.lastFailure = failure
            failuresInARow += 1
            scheduleRetry()
        } else if !Task.isCancelled {
            status.lastFailure = nil
            failuresInARow = 0
        }

        return failure
    }

    /// Oldest first; a record with a refused change keeps its later changes until the app resolves it. A failure on the
    /// way stops the run: the rest goes, in order, next time.
    private func sendOutbox(epoch: Int) async throws {
        var blocked = Set<String>()

        for change in outbox.pending(subject: subject.name) {
            guard epoch == self.epoch else { return }

            if change.rejection != nil || blocked.contains(change.entityID) {
                blocked.insert(change.entityID)
                continue
            }

            let outcome: PushOutcome

            do {
                outcome = try await subject.push(change)
                try Task.checkCancellation()
            } catch {
                if epoch == self.epoch, !Task.isCancelled { try outbox.recordAttempt(change.id) }

                throw error
            }

            guard epoch == self.epoch else { return }

            switch outcome {
            case .accepted:
                try outbox.confirm(change.id)

            case .rejected(let reason):
                try outbox.reject(change.id, reason: reason)
                blocked.insert(change.entityID)
            }

            refreshCounts()
        }
    }

    /// From the cursor, page by page; each page is written with its cursor in one save.
    private func pull(epoch: Int) async throws {
        var cursor = subject.state.cursor

        while true {
            var batch = try await subject.pull(since: cursor)

            try Task.checkCancellation()

            guard epoch == self.epoch else { return }

            let waiting = Set(outbox.pending(subject: subject.name).map(\.entityID))
            let touched = waiting.intersection(Set(batch.records.map(\.entityID)).union(batch.removed))
            let keeping: Set<String>

            switch subject.conflictPolicy {
            case .pendingWins:
                batch.records.removeAll { waiting.contains($0.entityID) }
                batch.removed.subtract(waiting)
                keeping = waiting

            case .serverWins:
                if !touched.isEmpty { try outbox.discard(entityIDs: touched, subject: subject.name) }

                keeping = waiting.subtracting(touched)
            }

            let syncedAt = now()

            try subject.apply(batch, keeping: keeping, state: SyncState(cursor: batch.cursor, syncedAt: syncedAt))
            status.syncedAt = syncedAt
            cursor = batch.cursor

            guard batch.hasMore else { return }
        }
    }

    private func scheduleRetry() {
        let delay = retry.delay(afterFailures: failuresInARow)
        let sleep = sleep

        retrying = Task { [weak self] in
            guard (try? await sleep(delay)) != nil, !Task.isCancelled else { return }

            await self?.sync()
        }
    }
}

extension Duration {
    var seconds: TimeInterval {
        let (seconds, attoseconds) = components

        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
