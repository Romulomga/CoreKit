import CoreKitTesting
import Foundation
import Testing

@MainActor
@Suite struct EventuallyTests {

    @Test func waitsForAConditionThatHoldsLater() async {
        var ready = false
        Task { @MainActor in ready = true }

        #expect(await eventually { ready })
    }

    @Test func waitsForAConditionThatHoldsAfterSeveralTurnsOfTheMainActor() async {
        let flag = Flag()

        Task { @MainActor in
            for _ in 0..<20 {
                await Task.yield()
            }

            flag.isSet = true
        }

        #expect(await eventually { flag.isSet })
    }

    // 30 ms buy three turns: the first check, then two per turn. Counting checks instead of timing
    // the wait keeps this test out of the flakiness it is about.
    @Test func isFalseWhenItNeverHoldsAfterItsTurns() async {
        var checks = 0

        let held = await eventually(timeout: .milliseconds(30)) {
            checks += 1
            return false
        }

        #expect(held == false)

        #expect(checks == 7)
    }

    @Test func theCeilingEndsTheWaitEvenWithTurnsLeft() async {
        let start = ContinuousClock.now

        #expect(await eventually(timeout: .seconds(100), ceiling: .milliseconds(50)) { false } == false)

        #expect(ContinuousClock.now - start < .seconds(10))
    }

    // MARK: - Under load

    // Six tasks hold the main actor for 50 ms each, as other `@MainActor` suites do in a parallel
    // run, and the value lands right after them. The main actor runs its jobs in order, so both
    // outcomes below are fixed: the check that comes back after the load has spent one turn of
    // its 10, while the wall-clock deadline of 100 ms is long gone.

    @Test func holdsWhenTheMainActorWasBusyForLongerThanTheTimeout() async {
        let flag = Flag()
        loadTheMainActor(then: flag)

        #expect(await eventually(timeout: .milliseconds(100)) { flag.isSet })
    }

    @Test func aWallClockDeadlineFailsUnderTheSameLoad() async {
        let flag = Flag()
        loadTheMainActor(then: flag)

        #expect(await wallClockEventually(timeout: .milliseconds(100)) { flag.isSet } == false)

        #expect(await eventually { flag.isSet })
    }

    private func loadTheMainActor(then flag: Flag) {
        for index in 0..<6 {
            Task { @MainActor in
                holdTheMainThread(for: 0.05)

                if index == 5 {
                    Task { @MainActor in flag.isSet = true }
                }
            }
        }
    }

    /// `eventually` up to 0.1.4: a wall-clock deadline, kept to show what the load above did to it.
    private func wallClockEventually(timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while !condition() {
            guard clock.now < deadline else { return false }

            try? await Task.sleep(for: .milliseconds(10))
        }

        return true
    }
}

/// Blocks the calling thread on purpose: the load is a main actor that can't take turns.
private func holdTheMainThread(for seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
}

@MainActor
private final class Flag {
    var isSet = false
}
