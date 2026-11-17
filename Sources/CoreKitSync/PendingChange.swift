import Foundation

/// A local write the server has not confirmed yet: one row of the app's outbox. The app's store inserts it in the same
/// save as the record it changes (so neither exists without the other if the app closes in between); the engine only
/// reads it, confirms it, refuses it or lets it go.
///
/// `id` is generated on the device and goes with every attempt: the server takes it as the idempotency key, so a change
/// sent twice (an answer lost on the way back) is applied once.
public struct PendingChange: Identifiable, Equatable, Sendable, Codable {
    public enum Kind: String, Equatable, Sendable, Codable {
        case upsert

        /// The record stays as a tombstone (hidden by the app's reads) until the server confirms.
        case delete
    }

    public let id: UUID

    /// The subject that sends it (`SyncSubject.name`).
    public let subject: String

    /// The record it changes: later changes of the same record go after it, in order.
    public let entityID: String

    public let kind: Kind

    /// What the subject's `push` sends, encoded by the app.
    public let payload: Data

    public let createdAt: Date

    /// Attempts that failed on the way (offline, a timeout): the change stays and goes again.
    public var attempts: Int

    /// Set when the server refused it for good. The record's later changes wait until the app resolves it (discards the
    /// change or clears the refusal to try again).
    public var rejection: String?

    public init(
        id: UUID = UUID(),
        subject: String,
        entityID: String,
        kind: Kind,
        payload: Data,
        createdAt: Date,
        attempts: Int = 0,
        rejection: String? = nil
    ) {
        self.id = id
        self.subject = subject
        self.entityID = entityID
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
        self.attempts = attempts
        self.rejection = rejection
    }
}

/// The app's outbox, in the app's own schema (a CoreKit change never touches anyone's database migration). Every method
/// saves before it returns; a save that fails throws, and the engine reports it through `mapError`.
@MainActor
public protocol Outbox: AnyObject {
    /// The subject's changes, oldest first, refused ones included.
    func pending(subject: String) -> [PendingChange]

    /// The server applied it: it leaves the outbox.
    func confirm(_ id: UUID) throws

    /// The server refused it for good.
    func reject(_ id: UUID, reason: String) throws

    /// An attempt failed on the way.
    func recordAttempt(_ id: UUID) throws

    /// The server's version won (`ConflictPolicy.serverWins`): the subject's changes of these records go.
    func discard(entityIDs: Set<String>, subject: String) throws

    /// The session ended: nothing of the subject stays queued.
    func removeAll(subject: String) throws
}
