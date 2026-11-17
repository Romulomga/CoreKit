/// Waits, without blocking the main actor, until `condition` holds; false when it never did.
///
/// For what reaches a view model through a stream (`AsyncStream.observing`): the value arrives on a
/// later turn of the main actor, so a check right after the write would fail. Use it as
/// `#expect(await eventually { viewModel.state.rows.count == 1 })`.
///
/// The budget is counted in turns, not read off the clock. Each turn yields once (whatever is
/// already queued on the main actor, like the stream's next value, runs before the next check) and
/// then sleeps 10 ms (for work off the main actor); `timeout` buys `timeout / 10 ms` turns, so with
/// a free main actor it gives up after about `timeout`. A wall-clock deadline was the first design,
/// and it failed at random in the apps' parallel runs: every `@MainActor` suite shares the main
/// actor, the loop waited seconds for its turn, and when it got one the deadline had passed even
/// though the value was next in line. A turn spent waiting for the main actor now costs one turn,
/// however long the wait.
///
/// `ceiling` is only a safety net, so a starved run still ends: past it the answer is false even
/// with turns left. Keep it well above `timeout`.
@MainActor
public func eventually(
    timeout: Duration = .seconds(2),
    ceiling: Duration = .seconds(30),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let interval = Duration.milliseconds(10)
    var turns = max(1, Int(timeout / interval))

    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: ceiling)

    while !condition() {
        guard turns > 0, !Task.isCancelled, clock.now < deadline else { return false }

        turns -= 1

        await Task.yield()

        if condition() { return true }

        try? await Task.sleep(for: interval)
    }

    return true
}
