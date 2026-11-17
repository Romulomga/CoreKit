@testable import CoreKitAnalytics
import Testing

struct CollectionPolicyTests {
    private let policy = CollectionPolicy.storeBuildsOnly

    @Test func debugBuildNeverCollects() {
        #expect(!policy.allowsCollection(in: LaunchContext(isDebugBuild: true, arguments: [])))
    }

    @Test func storeBuildCollects() {
        #expect(policy.allowsCollection(in: LaunchContext(isDebugBuild: false, arguments: [])))
    }

    @Test func debugBuildCollectsOnlyWhenAskedToTraceEvents() {
        #expect(policy.allowsCollection(in: LaunchContext(isDebugBuild: true, arguments: ["--analytics-debug"])))
    }

    @Test(arguments: [false, true])
    func uiTestRunNeverCollects(isDebugBuild: Bool) {
        let launch = LaunchContext(isDebugBuild: isDebugBuild, arguments: ["--uitests", "--analytics-debug"])

        #expect(!policy.allowsCollection(in: launch))
    }

    /// The package reads `DEBUG` itself; a test run is a debug build.
    @Test func thisTestRunIsADebugBuild() {
        #expect(LaunchContext.current.isDebugBuild)
    }

    // MARK: - What the app chooses

    @Test func anAppCanLetItsDebugBuildsCollect() {
        let policy = CollectionPolicy(debugBuildsCollect: true)

        #expect(policy.allowsCollection(in: LaunchContext(isDebugBuild: true, arguments: [])))
        #expect(!policy.allowsCollection(in: LaunchContext(isDebugBuild: true, arguments: ["--uitests"])))
    }

    @Test func anAppNamesItsOwnArguments() {
        let policy = CollectionPolicy(debugArgument: "--trace", automationArguments: ["--ui-run", "--snapshots"])

        #expect(policy.allowsCollection(in: LaunchContext(isDebugBuild: true, arguments: ["--trace"])))
        #expect(!policy.allowsCollection(in: LaunchContext(isDebugBuild: true, arguments: ["--analytics-debug"])))
        #expect(!policy.allowsCollection(in: LaunchContext(isDebugBuild: false, arguments: ["--snapshots"])))
    }
}
