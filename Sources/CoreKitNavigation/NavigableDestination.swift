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

    /// The tab or sidebar section whose stack this destination lives in, for `Navigator.open(_:)`; nil puts it on
    /// the bottom stack (the auth flow, or the only stack). A tab's root returns itself.
    var tab: Self? { get }

    /// A route without a tab of its own (`tab` nil) that `Navigator.open(_:)` shows on the selected tab instead of the
    /// bottom stack: a screen every tab reaches (a profile, a settings page) in a login-gated app, whose bottom stack is
    /// the auth flow under the main tab's cover. False by default.
    var opensOnSelectedTab: Bool { get }

    /// How the destination shows when nothing says otherwise: `Coordinator.navigate(to:)` without a `type`, and
    /// `Navigator.open(_:)` (a deep link opens it the way the app does). Push by default.
    var presentation: NavigationType { get }

    /// A deep link to this destination replaces its tab's stack instead of pushing onto it (a conversation opened
    /// from a push, whose back should lead to the list, not to whatever was open).
    var replacesStack: Bool { get }
}

extension NavigableDestination {

    public var isStandalone: Bool { false }

    public var presentationDetent: Set<PresentationDetent> { [.large] }

    public var routeName: String { String(describing: id) }

    public var tab: Self? { nil }

    public var opensOnSelectedTab: Bool { false }

    public var replacesStack: Bool { false }

    public var presentation: NavigationType { .push }

    /// The route is its own identity: two equal routes are the same sheet or cover.
    public var id: Self { self }
}
