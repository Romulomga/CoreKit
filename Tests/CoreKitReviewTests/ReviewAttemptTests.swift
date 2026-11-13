import Foundation
import Testing
@testable import CoreKitReview

@MainActor
final class ReviewAttemptTests {
    private let suiteName = "corekit-review-attempt-\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let gate: ReviewGate

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        gate = ReviewGate(defaults: defaults, versionKey: "review.version", dateKey: "review.date", currentVersion: "1.0")
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @Test func asksOnceAndMarksRightAfterTheCall() async {
        var requests = 0
        var eligibleWhenAsked: Bool?

        let first = await ReviewAttempt.run(gate: gate, canAsk: true, delay: .milliseconds(1)) {
            requests += 1
            eligibleWhenAsked = gate.isEligible
        }

        let second = await ReviewAttempt.run(gate: gate, canAsk: true, delay: .milliseconds(1)) {
            requests += 1
        }

        #expect(first == .asked)
        #expect(second == .gateClosed)
        #expect(requests == 1)
        #expect(eligibleWhenAsked == true)
        #expect(!gate.isEligible)
    }

    @Test func anAttemptInterruptedDuringTheWaitNeitherAsksNorSpendsTheVersion() async {
        let attempt = Task {
            await ReviewAttempt.run(gate: gate, canAsk: true, delay: .seconds(30)) {
                Issue.record("the system was asked after the attempt was interrupted")
            }
        }

        attempt.cancel()

        #expect(await attempt.value == .held)
        #expect(gate.isEligible)
    }

    /// The scene in the background, or the app holding requests: the moment waits, the version isn't spent.
    @Test func anAttemptThatCannotAskNowIsHeld() async {
        let outcome = await ReviewAttempt.run(gate: gate, canAsk: false, delay: .milliseconds(1)) {
            Issue.record("the system was asked while it couldn't be")
        }

        #expect(outcome == .held)
        #expect(gate.isEligible)
    }

    @Test func aClosedGateDropsTheMomentWithoutReachingTheSystem() async {
        gate.markRequested()

        let outcome = await ReviewAttempt.run(gate: gate, canAsk: true, delay: .milliseconds(1)) {
            Issue.record("the system was asked through a closed gate")
        }

        #expect(outcome == .gateClosed)
    }
}
