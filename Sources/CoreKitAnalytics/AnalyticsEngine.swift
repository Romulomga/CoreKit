/// One analytics service the app runs (Firebase, Mixpanel). An engine module adds its own factory
/// (`.firebase(options:)`, `.mixpanel(token:)`), so the app compiles only the SDK it imports.
public struct AnalyticsEngine {
    let name: String
    let start: @MainActor () -> (any AnalyticsClient)?
    let stayOff: @MainActor () -> Void
    let setCollectionEnabled: @MainActor (Bool) -> Void

    /// - Parameters:
    ///   - start: Sets the SDK up and returns its client, or `nil` when it can't run (no key in
    ///     this build). Called only when the policy collects.
    ///   - stayOff: Called instead of `start` when the policy doesn't collect, or the user switched
    ///     collection off, to silence anything the app may have set up by itself before.
    ///   - setCollectionEnabled: The user's switch, once the engine runs: turn the SDK's own
    ///     collection off or back on (it persists on the device). Called only on an engine whose
    ///     `start` returned a client.
    public init(
        name: String,
        start: @escaping @MainActor () -> (any AnalyticsClient)?,
        stayOff: @escaping @MainActor () -> Void = {},
        setCollectionEnabled: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.name = name
        self.start = start
        self.stayOff = stayOff
        self.setCollectionEnabled = setCollectionEnabled
    }
}
