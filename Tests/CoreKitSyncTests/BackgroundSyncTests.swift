@testable import CoreKitSync
import Foundation
import os
import Testing

/// Background refresh registers only with both `Info.plist` keys (an identifier the plist lacks crashes the app), asks
/// for the next run every time, and a run the system takes back is cancelled.
@Suite struct BackgroundSyncTests {
    final class FakeScheduler: BackgroundScheduling {
        private let state = OSAllocatedUnfairLock(initialState: (registered: [String](), submitted: [String](), launch: nil as (@Sendable (BackgroundRun) -> Void)?))
        let refusesSubmit: Bool

        init(refusesSubmit: Bool = false) { self.refusesSubmit = refusesSubmit }

        var registered: [String] { state.withLock { $0.registered } }

        var submitted: [String] { state.withLock { $0.submitted } }

        func register(identifier: String, launch: @escaping @Sendable (BackgroundRun) -> Void) -> Bool {
            state.withLock { $0.registered.append(identifier); $0.launch = launch }
            return true
        }

        func submit(identifier: String, earliestBegin: Date) throws {
            if refusesSubmit { throw CocoaError(.featureUnsupported) }
            state.withLock { $0.submitted.append(identifier) }
        }

        func launch(_ run: BackgroundRun) { state.withLock { $0.launch }?(run) }
    }

    static let id = "com.example.sync"

    static var plist: [String: Any] { ["UIBackgroundModes": ["fetch"], "BGTaskSchedulerPermittedIdentifiers": [id]] }

    @Test func eachMissingKeyIsNamed() {
        #expect(BackgroundSync.missingKeys(identifier: Self.id, infoPlist: Self.plist).isEmpty)
        #expect(BackgroundSync.missingKeys(identifier: Self.id, infoPlist: [:]).count == 2)
        #expect(BackgroundSync.missingKeys(identifier: Self.id, infoPlist: ["UIBackgroundModes": ["fetch"]]) == ["BGTaskSchedulerPermittedIdentifiers: \(Self.id)"])
    }

    @Test func withoutTheKeysNothingIsRegistered() {
        let scheduler = FakeScheduler()

        #expect(!BackgroundSync.register(identifier: Self.id, infoPlist: ["UIBackgroundModes": ["fetch"]], scheduler: scheduler) { true })
        #expect(scheduler.registered.isEmpty)
    }

    @Test func withTheKeysItRegistersAndAsksForTheFirstRun() {
        let scheduler = FakeScheduler()

        #expect(BackgroundSync.register(identifier: Self.id, infoPlist: Self.plist, scheduler: scheduler) { true })
        #expect(scheduler.registered == [Self.id])
        #expect(scheduler.submitted == [Self.id])
    }

    /// The simulator, or a user who turned background refresh off, refuses the request: the app goes on.
    @Test func aRefusedRequestStillRegisters() {
        let scheduler = FakeScheduler(refusesSubmit: true)

        #expect(BackgroundSync.register(identifier: Self.id, infoPlist: Self.plist, scheduler: scheduler) { true })
    }

    @Test func aRunAsksForTheNextAndReportsHowItEnded() async {
        let scheduler = FakeScheduler()
        BackgroundSync.register(identifier: Self.id, infoPlist: Self.plist, scheduler: scheduler) { true }

        let ended = await withCheckedContinuation { continuation in
            scheduler.launch(BackgroundRun { continuation.resume(returning: $0) })
        }

        #expect(ended)
        #expect(scheduler.submitted.count == 2)
    }

    @Test func aRunTheSystemTakesBackIsCancelled() async {
        let scheduler = FakeScheduler()
        BackgroundSync.register(identifier: Self.id, infoPlist: Self.plist, scheduler: scheduler) {
            try? await Task.sleep(for: .seconds(3600))
            return !Task.isCancelled
        }

        let ended = await withCheckedContinuation { continuation in
            let run = BackgroundRun { continuation.resume(returning: $0) }
            scheduler.launch(run)
            run.expire()
        }

        #expect(!ended)
    }
}
