import CoreKitTesting
import Testing

@MainActor
@Suite struct WaitsTests {

    // MARK: - waitUntil

    @Test func waitUntilGoesOnOnceTheConditionHolds() async {
        var ready = false
        Task { @MainActor in ready = true }

        await waitUntil { ready }

        #expect(ready)
    }

    @Test func waitUntilRecordsAFailureWhenTheConditionNeverHolds() async {
        await withKnownIssue {
            await waitUntil(timeout: .milliseconds(30)) { false }
        }
    }

    // MARK: - holdsThroughout

    @Test func holdsThroughoutIsTrueWhenTheConditionNeverBreaks() async {
        var checks = 0

        let held = await holdsThroughout(timeout: .milliseconds(30)) {
            checks += 1
            return true
        }

        #expect(held)
        #expect(checks > 1)
    }

    @Test func holdsThroughoutIsFalseWhenTheConditionBreaksInsideTheWindow() async {
        var landed = false
        Task { @MainActor in landed = true }

        #expect(await holdsThroughout(timeout: .milliseconds(200)) { !landed } == false)
    }
}
