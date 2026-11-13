extension AsyncStream where Element: Sendable {

    /// Maps each element into a new `AsyncStream`.
    ///
    /// The standard `map` returns an `AsyncMapSequence`, which an API that takes an `AsyncStream`
    /// (a session state stream narrowed to "logged in or not") cannot accept. The stream that
    /// forwards the elements stops when the consumer goes away: its termination cancels the task
    /// reading the source, so a dropped observer doesn't keep the source alive.
    public func map<T: Sendable>(_ transform: @escaping @Sendable (Element) -> T) -> AsyncStream<T> {
        AsyncStream<T> { continuation in
            let task = Task {
                for await element in self {
                    continuation.yield(transform(element))
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
