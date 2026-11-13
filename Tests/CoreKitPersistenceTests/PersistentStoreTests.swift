import Foundation
import SwiftData
import Testing
import CoreKitPersistence

@Model
final class Note {
    var text: String

    init(text: String) {
        self.text = text
    }
}

enum NotesSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] { [Note.self] }
}

enum NotesMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NotesSchemaV1.self] }

    static var stages: [MigrationStage] { [] }
}

/// Serialized: SwiftData traps when two containers for the same models are alive at once.
@MainActor
@Suite(.serialized)
final class PersistentStoreTests {
    private struct LocationUnavailable: Error {}

    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "corekit-store-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Opening

    @Test func aStoreThatOpensIsHealthyAndKeepsWhatIsSaved() throws {
        let url = folder.appending(path: "notes.store")

        let opening = PersistentStore.open(NotesSchemaV1.self, migrationPlan: NotesMigrationPlan.self, location: .file(url))

        guard case .healthy(let container) = opening else {
            Issue.record("expected .healthy, got \(opening)")
            return
        }

        container.mainContext.insert(Note(text: "kept"))
        try container.mainContext.save()

        #expect(try container.mainContext.fetch(FetchDescriptor<Note>()).map(\.text) == ["kept"])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    /// The real failure, not a stand-in: SwiftData refuses a file that isn't a store, and the file is still
    /// there afterwards, the same file, byte for byte.
    @Test func anUnreadableStoreIsDegradedAndItsFileIsLeftUntouched() throws {
        let url = folder.appending(path: "damaged.store")
        let garbage = Data("this is not a SQLite database".utf8)

        try garbage.write(to: url)

        let inodeBefore = try fileNumber(of: url)

        let opening = PersistentStore.open(NotesSchemaV1.self, migrationPlan: NotesMigrationPlan.self, location: .file(url))

        guard case .degraded = opening else {
            Issue.record("expected .degraded, got \(opening)")
            return
        }

        #expect(try Data(contentsOf: url) == garbage)
        #expect(try fileNumber(of: url) == inodeBefore)
    }

    @Test func aLocationThatCannotBeResolvedIsDegradedInsteadOfThrowing() {
        let opening = PersistentStore.open(
            NotesSchemaV1.self,
            migrationPlan: NotesMigrationPlan.self,
            location: try unavailableLocation()
        )

        guard case .degraded(let error) = opening else {
            Issue.record("expected .degraded, got \(opening)")
            return
        }

        #expect(error is LocationUnavailable)
    }

    @Test func forcingTheDegradedStateNeverReachesTheStore() {
        var resolvedLocation = false

        let opening = PersistentStore.open(
            NotesSchemaV1.self,
            migrationPlan: NotesMigrationPlan.self,
            location: {
                resolvedLocation = true

                return .file(folder.appending(path: "forced.store"))
            }(),
            forceDegraded: true
        )

        guard case .degraded(let error) = opening else {
            Issue.record("expected .degraded, got \(opening)")
            return
        }

        #expect(error is PersistentStore.ForcedFailure)
        #expect(!resolvedLocation)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "forced.store").path))
    }

    @Test func inMemoryOpens() throws {
        let opening = PersistentStore.open(NotesSchemaV1.self, migrationPlan: NotesMigrationPlan.self, location: .inMemory)

        guard case .healthy(let container) = opening else {
            Issue.record("expected .healthy, got \(opening)")
            return
        }

        container.mainContext.insert(Note(text: "for this run only"))

        #expect(try container.mainContext.fetchCount(FetchDescriptor<Note>()) == 1)
    }

    // MARK: - Checking again

    @Test func aWritableFolderIsReachable() {
        #expect(PersistentStore.locationIsReachable(NotesSchemaV1.self, location: .file(folder.appending(path: "notes.store"))))
    }

    @Test func aMissingFolderOrAnUnresolvableLocationIsNotReachable() {
        let missing = folder.appending(path: "missing/notes.store")

        #expect(!PersistentStore.locationIsReachable(NotesSchemaV1.self, location: .file(missing)))
        #expect(!PersistentStore.locationIsReachable(NotesSchemaV1.self, location: try unavailableLocation()))
    }

    @Test func aStoreFileThatCannotBeWrittenIsNotReachable() throws {
        let url = folder.appending(path: "locked.store")

        try Data("store".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)

        #expect(!PersistentStore.locationIsReachable(NotesSchemaV1.self, location: .file(url)))
    }

    @Test func checkingAgainNeverCreatesOrChangesTheStore() throws {
        let url = folder.appending(path: "damaged.store")
        let garbage = Data("this is not a SQLite database".utf8)

        try garbage.write(to: url)

        #expect(PersistentStore.locationIsReachable(NotesSchemaV1.self, location: .file(url)))
        #expect(try Data(contentsOf: url) == garbage)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["damaged.store"])
    }

    // MARK: - Helpers

    private func unavailableLocation() throws -> StoreLocation {
        throw LocationUnavailable()
    }

    private func fileNumber(of url: URL) throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int
    }
}
