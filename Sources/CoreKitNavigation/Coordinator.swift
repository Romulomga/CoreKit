import Observation
import SwiftUI

// MARK: - NavigationType

/// How `Coordinator.navigate(to:type:)` shows a destination.
public enum NavigationType: Sendable {
    case push, sheet, fullScreenCover
}

// MARK: - Coordinator

/// The navigation state of one `NavigationHost`: the pushed path plus the sheet and
/// full-screen-cover slots. A tab app keeps one per tab, owned above the `TabView`, so a deep
/// link can switch tabs and drive the right stack.
///
/// Screens read it with `@Environment(Coordinator<Route>.self)`; an app whose features only
/// report intent through callbacks drives it from the place that builds the views.
@MainActor
@Observable
public final class Coordinator<D: NavigableDestination> {

    // MARK: - State

    var path: [NavigationStep<D>] = []

    public internal(set) var sheetDestination: D?

    public internal(set) var fullCoverDestination: D?

    /// Offered every push (and every destination of `replaceAll`) before it lands on this stack.
    /// A container that shows some destinations elsewhere returns true to take one, and nothing
    /// is pushed: an iPad list/detail split puts the item beside its list, deep links included.
    @ObservationIgnored public var pushInterceptor: (@MainActor (D) -> Bool)?

    public init() {}

    // MARK: - Reading

    public var pathCount: Int { path.count }

    public var currentDestination: D? { path.last?.destination }

    /// Everything pushed, bottom to top.
    public var destinations: [D] { path.map(\.destination) }

    public func contains(_ destination: D) -> Bool {
        path.contains { $0.destination == destination }
    }

    /// What the user is looking at, modals first.
    func visibleDestination(root: D) -> D {
        fullCoverDestination ?? sheetDestination ?? path.last?.destination ?? root
    }

    // MARK: - Navigating

    /// Shows `destination`. Pushing the destination already on top does nothing: a second tap
    /// that landed before the first push ended stacked the screen twice (two backs to leave it,
    /// two loads). The same route further down the stack is still pushed (profile A → post →
    /// profile A). Twin of CoreKit-Android's `Navigator.navigate`.
    ///
    /// The modal slots need no such check: an equal value is no change to `@Observable` nor to
    /// `.sheet(item:)`, so the sheet already up stays as it is. A different one replaces it, which
    /// is how a deep link shows something over an open sheet.
    public func navigate(to destination: D, type: NavigationType = .push) {
        switch type {
        case .push:
            push(NavigationStep(destination: destination))

        case .sheet:
            sheetDestination = destination

        case .fullScreenCover:
            fullCoverDestination = destination
        }
    }

    private func push(_ step: NavigationStep<D>) {
        if pushInterceptor?(step.destination) == true { return }

        guard path.last?.destination != step.destination else { return }

        path.append(step)
    }

    /// What the stack's own controls ask for: a `RouteLink` appends one entry, the back button and
    /// the edge swipe drop entries. An append goes through the same rules as `navigate(to:)`, so a
    /// link tapped twice doesn't stack its screen twice; anything else is the system popping, and
    /// is taken as it is.
    func applyStackChange(_ newPath: [NavigationStep<D>]) {
        if newPath.count == path.count + 1, Array(newPath.dropLast()) == path, let appended = newPath.last {
            push(appended)
        } else {
            path = newPath
        }
    }

    public func pop() {
        guard !path.isEmpty else { return }

        path.removeLast()
    }

    public func popToRoot() {
        path.removeAll()
    }

    /// Pops everything above the first `destination` in the stack; nothing when it isn't there.
    public func pop(to destination: D) {
        guard let index = path.firstIndex(where: { $0.destination == destination }) else { return }

        path.removeSubrange((index + 1)..<path.count)
    }

    public func dismissSheet() {
        sheetDestination = nil
    }

    public func dismissFullCover() {
        fullCoverDestination = nil
    }

    /// Replaces the stack with `destination` over the root: back from the new screen lands on the
    /// root, not on the flow that led to it (the form that issued a document).
    public func replaceAll(with destination: D) {
        replaceAll(with: [destination])
    }

    /// Replaces the stack with `destinations`, bottom to top (a deep link that opens a screen
    /// two levels down). Each one is offered to `pushInterceptor` first, and a claimed one stays
    /// out of the stack.
    public func replaceAll(with destinations: [D]) {
        path = destinations
            .filter { pushInterceptor?($0) != true }
            .map { NavigationStep(destination: $0) }
    }
}
