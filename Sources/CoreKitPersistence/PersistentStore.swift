import Foundation
import SwiftData
import os

/// How the store opened at launch: what decides whether the app shows its content or its recovery screen.
public enum StoreOpening: Sendable {
    case healthy(ModelContainer)

    /// The store didn't open: a failed migration, a damaged file, a location the app can't reach, a file still
    /// locked by data protection. Its files stay exactly where they are, so a later build or a restart can still
    /// read them. There is no container: anything the person did now would not be saved, so the app shows its
    /// recovery screen instead of its content.
    case degraded(any Error)
}

/// Where the store's file lives.
public enum StoreLocation: Sendable {
    /// SwiftData's default file (`default.store` in Application Support, or in the app group's container when
    /// the app has one: SwiftData picks it on its own).
    case standard

    /// A file the app chose, such as one in an app group shared with an extension.
    case file(URL)

    /// No file: for UI tests that need a clean slate on every launch. Never a stand-in for a store that didn't
    /// open, because whatever the person recorded there would vanish when the app closed.
    case inMemory
}

/// The one place an app builds its `ModelContainer`.
///
/// A store that can't open used to be a `fatalError`: for an installed user, an app that closed on every
/// launch, with no way out but deleting it, and the data with it. The other ways out were worse because they
/// looked fine: running from memory (everything recorded vanished on close) or moving the file aside and
/// starting empty (the history looked gone). Here the store opens or it doesn't, and nothing in between
/// touches the file: it is never deleted, replaced or recreated. The twin on Android is
/// `KeepCorruptDatabaseFactory`, which stops Android from deleting a database SQLite reports as corrupt.
///
/// SwiftData traps when two containers for the same models live in one process, so an app opens once, keeps
/// the result, and never reopens a degraded store: closing and opening the app is the retry.
public enum PersistentStore {
    /// Stands in for the real failure when the app forces the degraded state.
    public struct ForcedFailure: Error {
        public init() {}
    }

    /// Opens the store from its versioned schema and migration plan.
    ///
    /// - Parameters:
    ///   - versionedSchema: the current schema version.
    ///   - migrationPlan: the plan that brings older stores up to `versionedSchema`, or `nil` when the app
    ///     relies on lightweight migration alone. Required on purpose: forgetting the plan opens an older store
    ///     without its stages. Ignored for `.inMemory`, which has nothing stored to migrate.
    ///   - location: where the file lives. Resolved inside the guarded open, so a location that can't be
    ///     resolved (an app group gone missing) is a degraded store, not a crash.
    ///   - cloudKitDatabase: whether the store syncs through CloudKit. `.automatic` (SwiftData's own
    ///     default) syncs when the app has the iCloud entitlement; `.none` never does; `.private(_:)`
    ///     names the container.
    ///   - forceDegraded: returns `.degraded` without building a container or resolving the location. The
    ///     recovery screen only shows in a rare state of the device; without a way to force it, it would be UI
    ///     nobody ever saw run. The app maps its own debug launch argument here.
    public static func open(
        _ versionedSchema: any VersionedSchema.Type,
        migrationPlan: (any SchemaMigrationPlan.Type)?,
        location: @autoclosure () throws -> StoreLocation = .standard,
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .automatic,
        forceDegraded: Bool = false
    ) -> StoreOpening {
        do {
            if forceDegraded { throw ForcedFailure() }

            let schema = Schema(versionedSchema: versionedSchema)
            let location = try location()

            let container = try ModelContainer(
                for: schema,
                migrationPlan: location.isInMemory ? nil : migrationPlan,
                configurations: configuration(for: location, schema: schema, cloudKitDatabase: cloudKitDatabase)
            )

            return .healthy(container)
        } catch {
            logger.fault("store failed to open; its files were left untouched: \(String(describing: error), privacy: .public)")

            return .degraded(error)
        }
    }

    /// Whether the store's folder (and its file, when there is one) can be read and written: the recovery
    /// screen's "Check again".
    ///
    /// It only looks and never reopens: SwiftData traps when two containers for the same models open in one
    /// process, so the retry is the next launch. Pass the same schema and location given to `open`.
    public static func locationIsReachable(
        _ versionedSchema: any VersionedSchema.Type,
        location: @autoclosure () throws -> StoreLocation = .standard
    ) -> Bool {
        guard let location = try? location() else { return false }

        if location.isInMemory { return true }

        let fileManager = FileManager.default
        let file = configuration(for: location, schema: Schema(versionedSchema: versionedSchema)).url

        guard fileManager.isWritableFile(atPath: file.deletingLastPathComponent().path) else { return false }

        guard fileManager.fileExists(atPath: file.path) else { return true }

        return fileManager.isReadableFile(atPath: file.path) && fileManager.isWritableFile(atPath: file.path)
    }

    // MARK: - Configuration

    /// The same configuration for opening and for checking, so the check always looks at the file `open` used.
    static func configuration(
        for location: StoreLocation,
        schema: Schema,
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .automatic
    ) -> ModelConfiguration {
        switch location {
        case .standard:
            ModelConfiguration(schema: schema, cloudKitDatabase: cloudKitDatabase)
        case .file(let url):
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: cloudKitDatabase)
        case .inMemory:
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CoreKit", category: "persistence")
}

private extension StoreLocation {
    var isInMemory: Bool {
        if case .inMemory = self { return true }

        return false
    }
}
