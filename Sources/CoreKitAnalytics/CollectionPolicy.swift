import Foundation

/// Which builds may send data. The twin of CoreKit-Android's `CollectionPolicy`: every reinstall of
/// a development build used to be a `first_open` in the production funnels, and every UI-test run a
/// fake user.
public struct CollectionPolicy: Sendable {
    /// What the shipped binary does, and only that: the App Store build and the TestFlight build
    /// (the same binary, the one the owner checks events on before release). Never a debug build,
    /// unless launched with `--analytics-debug` to trace events (add `-FIRDebugEnabled` for Firebase's
    /// DebugView). Never a run launched with `--uitests`, in any build.
    public static let storeBuildsOnly = CollectionPolicy()

    public static let defaultDebugArgument = "--analytics-debug"

    public static let defaultAutomationArguments: Set<String> = ["--uitests"]

    /// A debug build collects without being asked (an app whose testers run debug builds).
    public let debugBuildsCollect: Bool

    /// The launch argument that makes a debug build collect, to trace events.
    public let debugArgument: String

    /// Launch arguments of an automated run, which never collects in any build.
    public let automationArguments: Set<String>

    /// Each choice an app may make, with `storeBuildsOnly`'s behaviour as the default.
    public init(
        debugBuildsCollect: Bool = false,
        debugArgument: String = CollectionPolicy.defaultDebugArgument,
        automationArguments: Set<String> = CollectionPolicy.defaultAutomationArguments
    ) {
        self.debugBuildsCollect = debugBuildsCollect
        self.debugArgument = debugArgument
        self.automationArguments = automationArguments
    }

    func allowsCollection(in launch: LaunchContext) -> Bool {
        guard automationArguments.isDisjoint(with: launch.arguments) else { return false }

        if launch.isDebugBuild {
            return debugBuildsCollect || launch.arguments.contains(debugArgument)
        }

        return true
    }
}

/// What the policy looks at, apart so a test can describe a store build from a debug test run.
struct LaunchContext: Sendable {
    var isDebugBuild: Bool
    var arguments: [String]

    /// `DEBUG` is the package's own flag: Xcode builds a package in debug only when the app's
    /// configuration is named exactly "Debug", so an app with a custom debug configuration
    /// (`Homolog`) collects there.
    static var current: LaunchContext {
        #if DEBUG
        LaunchContext(isDebugBuild: true, arguments: ProcessInfo.processInfo.arguments)
        #else
        LaunchContext(isDebugBuild: false, arguments: ProcessInfo.processInfo.arguments)
        #endif
    }
}
