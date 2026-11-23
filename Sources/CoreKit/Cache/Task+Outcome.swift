import Foundation
import os

extension Task where Failure == Never {
    /// The task's answer, or nil as soon as the caller's own task is cancelled; the task itself goes on. A fetch belongs
    /// to the cache, not to whoever waits for it: `task.value` alone doesn't answer to the waiter's cancellation, so a
    /// screen that left stayed held by its wait until the server answered. Twin of CoreKit-Android's `Deferred.outcome()`.
    @MainActor
    func outcome() async -> Success? {
        let waiter = Waiter<Success>()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard waiter.wait(continuation) else { return }

                // Captures only the task and the waiter: the caller is free once it gave up.
                Task<Void, Never> { waiter.resume(with: await self.value) }
            }
        } onCancel: {
            waiter.resume(with: nil)
        }
    }
}

/// One continuation resumed exactly once, by the answer or by the cancellation, whichever comes first, including a
/// cancellation that arrives before the continuation is installed.
private final class Waiter<Value: Sendable>: Sendable {
    private enum State: Sendable {
        case idle
        case waiting(CheckedContinuation<Value?, Never>)
        case answered(Value?)
        case finished
    }

    private let state = OSAllocatedUnfairLock(initialState: State.idle)

    /// False when the answer (a cancellation) already came: the continuation was resumed here.
    func wait(_ continuation: CheckedContinuation<Value?, Never>) -> Bool {
        let early: Value?? = state.withLock { state in
            guard case .answered(let value) = state else {
                state = .waiting(continuation)
                return .none
            }

            state = .finished
            return .some(value)
        }

        guard let early else { return true }

        continuation.resume(returning: early)
        return false
    }

    func resume(with value: Value?) {
        let continuation: CheckedContinuation<Value?, Never>? = state.withLock { state in
            switch state {
            case .idle:
                state = .answered(value)
                return nil
            case .waiting(let continuation):
                state = .finished
                return continuation
            case .answered, .finished:
                return nil
            }
        }

        continuation?.resume(returning: value)
    }
}
