import Foundation
import Testing
@testable import CoreKitReview

final class ReviewGateTests {
    private let suiteName = "corekit-review-\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let now = Date(timeIntervalSince1970: 1_794_571_200)

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func gate(version: String = "1.0", minDaysBetween: Int = 0, at date: Date? = nil) -> ReviewGate {
        let date = date ?? now

        return ReviewGate(
            defaults: defaults,
            versionKey: "review.version",
            dateKey: "review.date",
            minDaysBetween: minDaysBetween,
            currentVersion: version,
            now: { date }
        )
    }

    private func days(_ count: Double) -> TimeInterval {
        count * 24 * 60 * 60
    }

    // MARK: - Once per version

    @Test func asksOncePerVersion() {
        #expect(gate().isEligible)

        gate().markRequested()

        #expect(!gate().isEligible)
        #expect(!gate(at: now.addingTimeInterval(days(400))).isEligible)
        #expect(gate(version: "1.1").isEligible)
    }

    // MARK: - Interval

    @Test func aNewVersionStillWaitsTheInterval() {
        gate(version: "1.0").markRequested()

        #expect(!gate(version: "1.1", minDaysBetween: 90, at: now.addingTimeInterval(days(89.9))).isEligible)
        #expect(gate(version: "1.1", minDaysBetween: 90, at: now.addingTimeInterval(days(90))).isEligible)
    }

    @Test func withoutAnIntervalTheDateDoesNotMatter() {
        gate(version: "1.0").markRequested()

        #expect(gate(version: "1.1", at: now).isEligible)
    }

    // MARK: - Marks the apps already stored

    @Test func aVersionStoredBeforeTheGateIsRead() {
        defaults.set("1.0", forKey: "review.version")

        #expect(!gate(version: "1.0").isEligible)
        #expect(gate(version: "1.1").isEligible)
    }

    @Test func aDateStoredAsSecondsSince1970IsRead() {
        defaults.set(now.addingTimeInterval(-days(10)).timeIntervalSince1970, forKey: "review.date")

        #expect(!gate(minDaysBetween: 30).isEligible)
        #expect(gate(minDaysBetween: 30, at: now.addingTimeInterval(days(20))).isEligible)
    }

    @Test func aDateStoredAsADateIsRead() {
        defaults.set(now.addingTimeInterval(-days(10)), forKey: "review.date")

        #expect(!gate(minDaysBetween: 30).isEligible)
        #expect(gate(minDaysBetween: 30, at: now.addingTimeInterval(days(20))).isEligible)
    }

    // MARK: - Rule

    /// Same cases as CoreKit-Android's `ReviewGateTest`.
    @Test func theRuleMatchesAndroid() {
        #expect(ReviewGate.isEligible(currentVersion: "1.1", lastPromptVersion: "1.0", lastPromptAt: nil, now: now, minDaysBetween: 0))
        #expect(!ReviewGate.isEligible(currentVersion: "1.1", lastPromptVersion: "1.1", lastPromptAt: nil, now: now, minDaysBetween: 0))
        #expect(ReviewGate.isEligible(currentVersion: "1.0", lastPromptVersion: nil, lastPromptAt: nil, now: now, minDaysBetween: 0))

        let recent = now.addingTimeInterval(-days(89))
        let old = now.addingTimeInterval(-days(90))

        #expect(!ReviewGate.isEligible(currentVersion: "1.1", lastPromptVersion: "1.0", lastPromptAt: recent, now: now, minDaysBetween: 90))
        #expect(ReviewGate.isEligible(currentVersion: "1.1", lastPromptVersion: "1.0", lastPromptAt: old, now: now, minDaysBetween: 90))
        #expect(ReviewGate.isEligible(currentVersion: "1.1", lastPromptVersion: "1.0", lastPromptAt: now, now: now, minDaysBetween: 0))
    }

    @Test func aNewAppCanKeepTheDefaultKeys() {
        let gate = ReviewGate(defaults: defaults, currentVersion: "2.0", now: { self.now })

        #expect(gate.isEligible)

        gate.markRequested()

        #expect(!gate.isEligible)
        #expect(defaults.string(forKey: "corekit.review.lastPromptVersion") == "2.0")
    }
}
