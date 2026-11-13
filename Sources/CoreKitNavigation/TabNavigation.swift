import Observation

/// The selected tab, typed and observable. Owned above the `TabView` so code outside it (a deep
/// link, an overlay button, a menu command) can switch tabs; screens inside read it with
/// `@Environment(TabNavigation<Route>.self)`.
@MainActor
@Observable
public final class TabNavigation<D: NavigableDestination> {

    public var selection: D

    public init(selection: D) {
        self.selection = selection
    }

    public func `switch`(to destination: D) {
        selection = destination
    }
}
