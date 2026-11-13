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

    static let debugArgument = "--analytics-debug"
    static let automationArgument = "--uitests"

    func allowsCollection(in launch: LaunchContext) -> Bool {
        guard !launch.arguments.contains(Self.automationArgument) else { return false }

        if launch.isDebugBuild {
            return launch.arguments.contains(Self.debugArgument)
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
