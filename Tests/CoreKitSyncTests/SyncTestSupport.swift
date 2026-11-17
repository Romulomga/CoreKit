@testable import CoreKitSync
import CoreKitTesting
import Foundation
import os
import Testing

enum SyncFailure: Error, Equatable, Sendable {
    case offline
    case local

    static func map(_ error: any Error) -> SyncFailure? {
        if error is CancellationError { return nil }

        return (error as? SyncFailure) ?? .local
    }
}

struct Row: SyncedRecord, Equatable {
    let entityID: String
    var name: String
}

/// A gate a call waits at until the test opens it.
final class Gate: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (held: false, waiting: [CheckedContinuation<Void, Never>]()))

    var waitingCount: Int { state.withLock { $0.waiting.count } }

    func hold() { state.withLock { $0.held = true } }

    func release() {
        let waiting = state.withLock { state in
            state.held = false
            defer { state.waiting = [] }
            return state.waiting
        }

        waiting.forEach { $0.resume() }
    }

    func pass() async {
        await withCheckedContinuation { continuation in
            let goesOn = state.withLock { state in
                guard state.held else { return true }
                state.waiting.append(continuation)
                return false
            }

            if goesOn { continuation.resume() }
        }
    }
}

/// The app's outbox, in memory.
@MainActor
final class MemoryOutbox: Outbox {
    var changes: [PendingChange] = []

    func pending(subject: String) -> [PendingChange] {
        changes.filter { $0.subject == subject }.sorted { $0.createdAt < $1.createdAt }
    }

    func confirm(_ id: UUID) throws { changes.removeAll { $0.id == id } }

    func reject(_ id: UUID, reason: String) throws {
        guard let index = changes.firstIndex(where: { $0.id == id }) else { return }
        changes[index].rejection = reason
    }

    func recordAttempt(_ id: UUID) throws {
        guard let index = changes.firstIndex(where: { $0.id == id }) else { return }
        changes[index].attempts += 1
    }

    func discard(entityIDs: Set<String>, subject: String) throws {
        changes.removeAll { $0.subject == subject && entityIDs.contains($0.entityID) }
    }

    func removeAll(subject: String) throws { changes.removeAll { $0.subject == subject } }

    func queue(_ entityID: String, at second: Int, kind: PendingChange.Kind = .upsert) -> PendingChange {
        let change = PendingChange(
            subject: "rows",
            entityID: entityID,
            kind: kind,
            payload: Data(entityID.utf8),
            createdAt: Date(timeIntervalSince1970: TimeInterval(second))
        )
        changes.append(change)
        return change
    }
}

/// A subject over a scripted server: it records what was sent and what was applied.
@MainActor
final class FakeSubject: SyncSubject {
    let name = "rows"
    var state = SyncState()
    var conflictPolicy: ConflictPolicy = .pendingWins
    var rows: [String: Row] = [:]

    let pullGate = Gate()
    var pulls: [PullBatch<Row>] = []
    var pullFailure: (any Error)?
    private(set) var pullCursors: [String?] = []

    var pushAnswer: (PendingChange) throws -> PushOutcome = { _ in .accepted }
    private(set) var pushed: [PendingChange] = []
    private(set) var applied: [(batch: PullBatch<Row>, keeping: Set<String>)] = []
    private(set) var events: [String] = []

    func pull(since cursor: String?) async throws -> PullBatch<Row> {
        pullCursors.append(cursor)
        events.append("pull")
        await pullGate.pass()

        if let pullFailure { throw pullFailure }

        return pulls.isEmpty ? PullBatch(records: [], cursor: cursor, shape: .changes) : pulls.removeFirst()
    }

    func apply(_ batch: PullBatch<Row>, keeping: Set<String>, state: SyncState) throws {
        applied.append((batch, keeping))

        if batch.shape == .fullList {
            rows = rows.filter { keeping.contains($0.key) }
        }

        for id in batch.removed { rows[id] = nil }
        for row in batch.records { rows[row.entityID] = row }

        self.state = state
    }

    func push(_ change: PendingChange) async throws -> PushOutcome {
        pushed.append(change)
        events.append("push \(change.entityID)")
        return try pushAnswer(change)
    }

    func resetState() throws { state = SyncState() }
}

/// What the engine asked to sleep; the sleep ends cancelled, so a retry never runs on its own in a test.
final class SleepSpy: Sendable {
    private let recorded = OSAllocatedUnfairLock(initialState: [Duration]())

    var delays: [Duration] { recorded.withLock { $0 } }

    var sleep: @Sendable (Duration) async throws -> Void {
        { [recorded] delay in
            recorded.withLock { $0.append(delay) }
            throw CancellationError()
        }
    }
}

@MainActor
func waitUntil(sourceLocation: SourceLocation = #_sourceLocation, _ condition: @MainActor () -> Bool) async {
    guard await eventually(condition) else {
        Issue.record("waitUntil gave up before the condition held", sourceLocation: sourceLocation)
        return
    }
}
