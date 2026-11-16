import Observation

extension AsyncStream where Element: Sendable & Equatable {

    /// The value `read` returns now, and again every time something observable it touched changes.
    ///
    /// The way a screen gets data that changes, without holding the database objects: the view model
    /// turns them into values inside `read` (rows, a screen state), and the stream delivers those
    /// values. A store makes every write count by reading its own write counter inside `read`; the
    /// clock's day or the selected item count because `read` touched them. Equal values in a row are
    /// dropped, so a write that changed nothing on the screen doesn't redraw it. The stream stops
    /// reading when its consumer goes away (the screen's `.task` is cancelled).
    ///
    /// iOS only: on Android the same job is Room's `Flow` mapped to the screen state and collected
    /// with `stateInScreen`.
    @MainActor
    public static func observing(_ read: @escaping @MainActor () -> Element) -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream.makeStream(of: Element.self, bufferingPolicy: .bufferingNewest(1))
        let watcher = ObservationWatcher(read: read, continuation: continuation)

        watcher.emit()

        continuation.onTermination = { _ in
            Task { @MainActor in watcher.stop() }
        }

        return stream
    }
}

/// Runs a read under observation, yields what it returns, and runs it again on the next change.
@MainActor
private final class ObservationWatcher<Value: Sendable & Equatable> {
    private let read: @MainActor () -> Value
    private let continuation: AsyncStream<Value>.Continuation
    private var last: Value?
    private var isStopped = false

    init(read: @escaping @MainActor () -> Value, continuation: AsyncStream<Value>.Continuation) {
        self.read = read
        self.continuation = continuation
    }

    func emit() {
        guard !isStopped else { return }

        // `onChange` fires once, before the change lands: the next read runs on the main actor after it.
        let value = withObservationTracking(read) { [weak self] in
            Task { @MainActor in self?.emit() }
        }

        guard value != last else { return }

        last = value
        continuation.yield(value)
    }

    func stop() {
        isStopped = true
    }
}
