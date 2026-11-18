/// The Mixpanel event a screen becomes: its name and the property that carries the screen's name.
/// Mixpanel has no screen event of its own, so the app picks the shape its reports read. Twin of
/// CoreKit-Android's `MixpanelScreenEvent`.
public struct MixpanelScreenEvent: Sendable, Hashable {
    /// The names Firebase uses (`screen_view` with `screen_name`), so a screen reads the same in both.
    public static let standard = MixpanelScreenEvent(event: "screen_view", nameKey: "screen_name")

    public let event: String

    public let nameKey: String

    public init(event: String, nameKey: String) {
        self.event = event
        self.nameKey = nameKey
    }

    /// What goes with the event for the screen `name`.
    public func properties(for name: String) -> [String: String] {
        [nameKey: name]
    }
}
