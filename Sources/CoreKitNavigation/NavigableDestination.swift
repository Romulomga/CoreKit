import SwiftUI

/// The app's route enum, the one type `Coordinator`, `NavigationHost` and `TabNavigation` move
/// between. Cases can carry values (`case detail(id: UUID)`); the route stays a plain value, and
/// the app maps each case to its view in the host's `viewBuilder`.
///
/// Every requirement has a default, so a plain `enum Route: NavigableDestination { ... }` is
/// enough. A login-gated app adds `SessionDestination` for `SessionObserver`.
///
/// `SendableMetatype`: the conformance itself is never isolated to an actor (SE-0470), so the
/// main-actor `Coordinator`, `ReloadNotifier` and `NavigationHost` can use it from any context
/// ("conformance of 'D' … may be isolated" otherwise).
public protocol NavigableDestination: Hashable, Identifiable, SendableMetatype {

    /// Shown as is when presented as a sheet or a cover, instead of inside a `NavigationHost` of
    /// its own: a destination that already runs its own navigation (a tab container, a sheet
    /// with its own `NavigationStack`) would otherwise get a second navigation bar.
    var isStandalone: Bool { get }

    /// The detents of the sheet that presents this destination.
    var presentationDetent: Set<PresentationDetent> { get }

    /// What `NavigationDiagnostics` reports while this destination is on screen. The report
    /// usually ends in a third-party crash reporter, so a case whose value carries personal data
    /// (a name, an e-mail) returns a name without it.
    var routeName: String { get }
}

extension NavigableDestination {

    public var isStandalone: Bool { false }

    public var presentationDetent: Set<PresentationDetent> { [.large] }

    public var routeName: String { String(describing: id) }

    /// The route is its own identity: two equal routes are the same sheet or cover.
    public var id: Self { self }
}
