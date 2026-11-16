/// Waits, without blocking the main actor, until `condition` holds; false when it never did.
///
/// For what reaches a view model through a stream (`AsyncStream.observing`): the value arrives on a
/// later turn of the main actor, so a check right after the write would fail. Use it as
/// `#expect(await eventually { viewModel.state.rows.count == 1 })`.
@MainActor
public func eventually(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while !condition() {
        guard clock.now < deadline else { return false }

        try? await Task.sleep(for: .milliseconds(10))
    }

    return true
}
