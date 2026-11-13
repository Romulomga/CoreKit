import SwiftUI

/// A row that pushes `destination` onto the enclosing `NavigationHost` with the system's look: the
/// chevron and the tap highlight of a `List` row come only from a `NavigationLink`, and a button
/// styled to imitate them never matches. `NavigationLink(value: route)` doesn't work here, since
/// the stack holds the coordinator's entries rather than routes; this link pushes one of those, and
/// the coordinator applies its own rules to it (the destination already on top isn't pushed again,
/// `pushInterceptor` sees it).
public struct RouteLink<D: NavigableDestination, Label: View>: View {
    private let destination: D
    private let label: Label

    public init(to destination: D, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    public var body: some View {
        NavigationLink(value: NavigationStep(destination: destination)) {
            label
        }
    }
}

extension RouteLink where Label == Text {
    public init(_ titleKey: LocalizedStringKey, to destination: D) {
        self.init(to: destination) { Text(titleKey) }
    }
}
