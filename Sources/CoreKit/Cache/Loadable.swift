import Foundation

/// Where a piece of a cache stands. A load cut short never leaves `.loaded`: it goes back to what it was.
public enum LoadStatus<Failure: Error & Equatable & Sendable>: Equatable, Sendable {
    /// Never asked: the first reader asks.
    case idle

    case loading

    case loaded

    case failed(Failure)

    /// What a screen's opening asks for: never asked, or asked and failed (each opening and each return asks again after
    /// a failure; a value loaded or on its way is left alone).
    public var asksOnOpening: Bool {
        switch self {
        case .idle, .failed: true
        case .loading, .loaded: false
        }
    }
}

/// One value of a cache and where it stands. `value` stays while it is read again (a refresh, a write that may have
/// landed): only a value never loaded shows `.loading` or `.failed`.
public struct Loadable<Value: Equatable & Sendable, Failure: Error & Equatable & Sendable>: Equatable, Sendable {
    public var value: Value?

    public var status: LoadStatus<Failure>

    public init(value: Value? = nil, status: LoadStatus<Failure> = .idle) {
        self.value = value
        self.status = status
    }
}

/// The key of a cache that holds one value.
public enum SingleKey: Hashable, Sendable {
    case value
}

/// How a snapshot reads the cache: observed (a SwiftUI body, `values(_:)`), or not (a view model's `init`, which SwiftUI
/// runs inside the body that builds the screen: an observed read there would redraw that body on every change).
public enum CacheRead: Sendable {
    case tracked

    case untracked
}

/// Whether an error is the fetch being cancelled rather than an answer: the task itself, or the URL loading system.
/// An app's own cancellation (a client error of its network layer) is told apart by its `mapError` returning `nil`.
func isCancellation(_ error: any Error) -> Bool {
    if Task.isCancelled || error is CancellationError { return true }

    return (error as? URLError)?.code == .cancelled
}
