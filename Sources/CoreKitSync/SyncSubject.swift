import Foundation

/// One record as the server sent it in a pull.
public protocol SyncedRecord: Sendable {
    var entityID: String { get }
}

/// What a pull brought: the records changed since the cursor (or the whole list), the ones removed, and the cursor to
/// ask from next time.
public struct PullBatch<Record: SyncedRecord>: Sendable {
    public enum Shape: Sendable, Equatable {
        /// Only what changed since the cursor; `removed` lists what went away.
        case changes

        /// Everything the server has: what the device holds and the batch does not is gone.
        case fullList
    }

    public var records: [Record]

    public var removed: Set<String>

    public let cursor: String?

    public let shape: Shape

    /// More changes wait on the server: the engine asks again from `cursor`.
    public let hasMore: Bool

    public init(records: [Record], removed: Set<String> = [], cursor: String?, shape: Shape, hasMore: Bool = false) {
        self.records = records
        self.removed = removed
        self.cursor = cursor
        self.shape = shape
        self.hasMore = hasMore
    }
}

/// What the server said about one change.
public enum PushOutcome: Sendable, Equatable {
    case accepted

    /// Refused for good (a validation, a permission): sending it again would be refused again.
    case rejected(reason: String)
}

/// Where the subject stands, kept by the app with its data (the same save that applies a pull).
public struct SyncState: Sendable, Equatable {
    public var cursor: String?

    public var syncedAt: Date?

    public init(cursor: String? = nil, syncedAt: Date? = nil) {
        self.cursor = cursor
        self.syncedAt = syncedAt
    }
}

/// What a pull does to a record that still has a change waiting to go.
public enum ConflictPolicy: Sendable, Equatable {
    /// The default: the local change goes first and the server decides; the pull leaves the record alone, and the next
    /// pull brings what the server kept (last write wins, by the server's order).
    case pendingWins

    /// The server's version replaces the local one, and the waiting changes go.
    case serverWins
}

/// One subject kept in the app's database and synced with a server (the "offline-first" way). The app implements the
/// network calls and the writes; the rules (order, retries, what a pull may touch, one sync at a time) are the engine's.
@MainActor
public protocol SyncSubject: AnyObject {
    associatedtype Record: SyncedRecord

    /// The outbox's key for this subject.
    var name: String { get }

    var state: SyncState { get }

    var conflictPolicy: ConflictPolicy { get }

    func pull(since cursor: String?) async throws -> PullBatch<Record>

    /// Writes the batch and the new state in one save, so the cursor never moves without the data. A full list removes
    /// what it does not bring, except the records in `keeping` (they still have changes waiting to go).
    func apply(_ batch: PullBatch<Record>, keeping: Set<String>, state: SyncState) throws

    /// Sends one change. A failure on the way (offline, a timeout, the server down) throws: the change stays and goes
    /// again.
    func push(_ change: PendingChange) async throws -> PushOutcome

    /// The session ended: the cursor and the sync date go (the app deletes the data itself).
    func resetState() throws
}

extension SyncSubject {
    public var conflictPolicy: ConflictPolicy { .pendingWins }

    /// A subject that only reads (a catalog): nothing is ever queued.
    public func push(_ change: PendingChange) async throws -> PushOutcome {
        .rejected(reason: "\(name) does not send changes")
    }
}
