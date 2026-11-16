import CoreKitTesting
import Testing

@MainActor
@Suite struct EventuallyTests {

    @Test func waitsForAConditionThatHoldsLater() async {
        var ready = false
        Task { @MainActor in ready = true }

        #expect(await eventually { ready })
    }

    @Test func isFalseWhenItNeverHolds() async {
        #expect(await eventually(timeout: .milliseconds(30)) { false } == false)
    }
}
