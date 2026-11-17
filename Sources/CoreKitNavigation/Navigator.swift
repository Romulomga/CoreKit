import Foundation
import Observation

// MARK: - DeepLinkDestination

/// A route that can be built from a URL, for `Navigator.open(_:)` with a URL. The app keeps its own URL grammar here
/// (`init?(url:)`); nil is a URL the app handles itself (a web page, a tool) or ignores.
public protocol DeepLinkDestination: NavigableDestination {
    init?(url: URL)
}

// MARK: - Navigator

/// The app's whole navigation: the bottom stack (`root`: the auth flow of a login-gated app, under the main tab's
/// cover) and one stack per tab or sidebar section, created the first time it is asked for. Every destination says
/// where it lives (`NavigableDestination.tab`), so `open(_:)` takes a route from anywhere (a deep link, a push, a
/// shortcut) to the right stack, switching tabs when needed. Twin of CoreKit-Android's `Navigator`.
///
/// Owned once, above everything (the app's root), and put in the environment by `TabNavigationRoot(navigator:)`: a
/// cover presented by `root` inherits it, so the main tab of a login-gated app reads the same navigator as the auth
/// flow underneath. Screens keep navigating through their host's `Coordinator` in the environment.
@MainActor
@Observable
public final class Navigator<D: NavigableDestination> {

    // MARK: - State

    /// The bottom stack. A tab-only app never uses it.
    public let root: Coordinator<D>

    /// The selected tab, which `TabNavigationRoot` binds to; screens may also read it from the environment.
    public let tabs: TabNavigation<D>

    /// A route that arrived while links were held (`holdLinks(until:)`); it opens once they may.
    public private(set) var heldLink: D?

    private let firstTab: D

    /// Created on demand, never observed: asking for a stack while a view's body runs is no state change.
    @ObservationIgnored private var stacks: [D: Coordinator<D>] = [:]

    @ObservationIgnored private var isReady: (@MainActor () -> Bool)?

    // MARK: - Init

    /// - Parameters:
    ///   - tab: The tab selected at launch (and again after `reset()`).
    ///   - root: The bottom stack's coordinator; a new one by default.
    public init(tab: D, root: Coordinator<D> = Coordinator<D>()) {
        self.root = root
        self.firstTab = tab
        self.tabs = TabNavigation(selection: tab)
    }

    // MARK: - Stacks

    public var selection: D { tabs.selection }

    /// The stack of a tab or sidebar section, created the first time it is asked for.
    public func coordinator(for tab: D) -> Coordinator<D> {
        if let stack = stacks[tab] { return stack }

        let stack = Coordinator<D>()
        stacks[tab] = stack
        return stack
    }

    public func `switch`(to tab: D) {
        tabs.switch(to: tab)
    }

    /// Nothing pushed and nothing presented on the tab's stack (a stack never asked for is at its root).
    public func isAtRoot(_ tab: D) -> Bool {
        guard let stack = stacks[tab] else { return true }

        return stack.pathCount == 0 && stack.sheetDestination == nil && stack.fullCoverDestination == nil
    }

    public func popToRoot(_ tab: D) {
        stacks[tab]?.popToRoot()
    }

    /// Every tab stack goes, the first tab is selected again and a held link is dropped: the session ended, and the
    /// next one starts clean. The bottom stack is left alone (it is what shows after a logout).
    public func reset() {
        stacks.removeAll()
        heldLink = nil
        tabs.switch(to: firstTab)
    }

    // MARK: - Opening

    /// Shows `destination` from anywhere. A route without a tab goes on the bottom stack. A tab's route is selected
    /// and its stack goes to the route: the tab itself pops to its root, the screen already on top stays, a route
    /// that `replacesStack` replaces the stack, anything else is pushed. A sheet or cover open on that stack is closed
    /// first, and the push waits for the next turn so the two changes don't land in one frame.
    ///
    /// While links are held (`holdLinks(until:)`), a tab's route waits in `heldLink` and opens when they may; the bottom
    /// stack is what shows meanwhile, so its routes open at once.
    public func open(_ destination: D) {
        guard let tab = destination.tab else {
            root.navigate(to: destination)
            return
        }

        if let isReady, !isReady() {
            heldLink = destination
            return
        }

        tabs.switch(to: tab)

        let stack = coordinator(for: tab)
        let hadModal = stack.sheetDestination != nil || stack.fullCoverDestination != nil
        stack.dismissSheet()
        stack.dismissFullCover()

        let land: @MainActor () -> Void = {
            if destination == tab {
                stack.popToRoot()
            } else if stack.currentDestination == destination {
                return
            } else if destination.replacesStack {
                stack.replaceAll(with: destination)
            } else {
                stack.navigate(to: destination)
            }
        }

        if hadModal {
            Task { @MainActor in land() }
        } else {
            land()
        }
    }

    // MARK: - Holding links

    /// Holds tab routes until `isReady` (the session is restored, no update screen is up). The condition is watched:
    /// when anything observable it reads changes, a held route opens if it now may. Without it, routes open at once.
    public func holdLinks(until isReady: @escaping @MainActor () -> Bool) {
        self.isReady = isReady
        watchReadiness()
    }

    /// Drops the held route: the session it was meant for ended, and it must not open on the next account.
    public func discardHeldLink() {
        heldLink = nil
    }

    private func watchReadiness() {
        guard let isReady else { return }

        withObservationTracking {
            _ = isReady()
        } onChange: { [weak self] in
            Task { @MainActor in self?.readinessChanged() }
        }
    }

    private func readinessChanged() {
        if let held = heldLink, isReady?() ?? true {
            heldLink = nil
            open(held)
        }

        watchReadiness()
    }
}

extension Navigator where D: DeepLinkDestination {

    /// Opens the route a URL names (see `open(_ destination:)`). False when the URL is no route of the app (the app
    /// may still handle it: a web page, a tool), and nothing changes.
    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard let destination = D(url: url) else { return false }

        open(destination)
        return true
    }
}
