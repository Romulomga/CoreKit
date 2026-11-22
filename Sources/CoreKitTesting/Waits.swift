import Testing

/// Waits until `condition` holds (`eventually`, counted in turns of the main actor, not read off the clock), and
/// records a failure at the caller when it never does.
///
/// For work that finishes inside a Task (a debounce, a poll, a request held by a gate) before the test goes on: a
/// fixed sleep passes on a fast Mac and fails on a busy runner. A `waitUntil` is usually the precondition for a
/// `release()` or a `cancel()`, so running out of turns is a failure right here: going on silently turns it into a
/// confusing expectation further down, or a test that hangs on a gate. For a value the test asserts on, use
/// `#expect(await eventually { … })` instead.
@MainActor
public func waitUntil(
    timeout: Duration = .seconds(5),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @MainActor () -> Bool
) async {
    guard await eventually(timeout: timeout, condition) else {
        Issue.record("waitUntil gave up before the condition held", sourceLocation: sourceLocation)
        return
    }
}

/// True when `condition` held on every turn for `timeout` worth of turns (`eventually`, counted in turns of the main
/// actor).
///
/// For "this never happens": a read that must not start, a second request a `SingleFlight` must hold back, an answer
/// still on its way that must not land. Use a `timeout` well above the fake's delay, so the answer arrives inside the
/// window and the check sees what was done with it. It replaces counting `Task.yield()`, which proves nothing once
/// the work hops off the main actor.
@MainActor
public func holdsThroughout(timeout: Duration, _ condition: @MainActor () -> Bool) async -> Bool {
    !(await eventually(timeout: timeout) { !condition() })
}
