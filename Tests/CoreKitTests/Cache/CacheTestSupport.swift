import CoreKitTesting
import Foundation
import os
import Testing

/// The app's failure, as a repository would map it.
enum TestFailure: Error, Equatable, Sendable {
    case offline
    case server
    /// What an app's network layer throws for a cancelled request: `map` turns it into `nil`.
    case appCancelled

    static func map(_ error: any Error) -> TestFailure? {
        guard let failure = error as? TestFailure else { return .server }

        return failure == .appCancelled ? nil : failure
    }
}

/// A gate a fetch waits at until the test opens it, so a test exercises what happens *while* a request is in flight
/// without a delay and without winning a race.
final class TestGate: Sendable {
    private struct State {
        var isHeld = false
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var waitingCount: Int { state.withLock { $0.waiting.count } }

    func hold() {
        state.withLock { $0.isHeld = true }
    }

    func release() {
        let waiting = state.withLock { state in
            state.isHeld = false
            defer { state.waiting = [] }
            return state.waiting
        }

        waiting.forEach { $0.resume() }
    }

    func pass() async {
        await withCheckedContinuation { continuation in
            let goesOn = state.withLock { state in
                guard state.isHeld else { return true }
                state.waiting.append(continuation)
                return false
            }

            if goesOn { continuation.resume() }
        }
    }
}

/// Runs `work` in a task already cancelled when it starts, the way a screen's `.task` ends when the user leaves.
@MainActor
func runCancelled(_ work: @escaping @MainActor () async -> Void) async {
    let task = Task { @MainActor in await work() }
    task.cancel()
    await task.value
}

/// Waits until `condition` holds, counting turns of the main actor (CoreKitTesting's `eventually`).
@MainActor
func waitUntil(sourceLocation: SourceLocation = #_sourceLocation, _ condition: @MainActor () -> Bool) async {
    guard await eventually(condition) else {
        Issue.record("waitUntil gave up before the condition held", sourceLocation: sourceLocation)
        return
    }
}
