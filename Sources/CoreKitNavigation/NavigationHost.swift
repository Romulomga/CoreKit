import SwiftUI
import UIKit

/// What a `NavigationHost` does with the tab bar of an enclosing `TabView`.
public enum NavigationHostTabBarBehavior: Sendable {
    /// Hide it while something is pushed: the pushed screen gets the whole height, and the bar
    /// comes back at the root.
    case hidesOnPush

    /// Leave it alone: the bar stays on every screen, as in a plain `TabView`. Also for hosts
    /// outside a `TabView` (an auth flow, a modal, a single-stack app): toggling the bar there is a
    /// wasted navigation request per push.
    case untouched
}

/// One `NavigationStack` with its sheet and full-screen cover, driven by a `Coordinator`.
///
/// The root and every pushed or presented destination go through the same `viewBuilder`, so the
/// app maps routes to views in one place. A presented destination gets a host (and a stack) of
/// its own unless it `isStandalone`. The coordinator and the reload notifier go into the
/// environment: read them with `@Environment(Coordinator<Route>.self)`.
public struct NavigationHost<D: NavigableDestination, Content: View>: View {

    public typealias TabBarBehavior = NavigationHostTabBarBehavior

    // MARK: - State

    @State private var coordinator: Coordinator<D>

    @State private var reloadNotifier: ReloadNotifier<D>

    @State private var shouldShowTabBar = true

    private let root: D

    private let tint: Color?

    private let tabBarBehavior: TabBarBehavior

    private let viewBuilder: @MainActor (D) -> Content

    // MARK: - Initializers

    /// A host that owns a new coordinator, for a stack nothing outside needs to drive (a modal
    /// flow).
    public init(
        _ root: D,
        tint: Color? = nil,
        tabBarBehavior: TabBarBehavior = .hidesOnPush,
        @ViewBuilder viewBuilder: @escaping @MainActor (D) -> Content
    ) {
        self.init(root, tint: tint, coordinator: Coordinator<D>(), tabBarBehavior: tabBarBehavior, viewBuilder: viewBuilder)
    }

    /// A host bound to a coordinator owned outside it (the root view, one per tab), so code
    /// outside the stack can drive it.
    public init(
        _ root: D,
        tint: Color? = nil,
        coordinator: Coordinator<D>,
        reloadNotifier: ReloadNotifier<D> = ReloadNotifier<D>(),
        tabBarBehavior: TabBarBehavior = .hidesOnPush,
        @ViewBuilder viewBuilder: @escaping @MainActor (D) -> Content
    ) {
        self.root = root
        self.tint = tint
        self.tabBarBehavior = tabBarBehavior
        self.viewBuilder = viewBuilder
        self._coordinator = State(initialValue: coordinator)
        self._reloadNotifier = State(initialValue: reloadNotifier)
    }

    // MARK: - Body

    public var body: some View {
        @Bindable var coordinator = coordinator

        NavigationStack(path: $coordinator.path) {
            viewBuilder(root)
                .navigationDestination(for: NavigationStep<D>.self) { step in
                    viewBuilder(step.destination)
                }
        }
        .onAppear(perform: reportVisibleRoute)
        .modifier(OptionalTint(tint: tint))
        .sheet(item: $coordinator.sheetDestination) { destination in
            resolveModal(destination)
                .presentationDetents(destination.presentationDetent)
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $coordinator.fullCoverDestination) { destination in
            resolveModal(destination)
        }
        .onChange(of: coordinator.sheetDestination?.id) { _, _ in reportVisibleRoute() }
        .onChange(of: coordinator.fullCoverDestination?.id) { _, _ in reportVisibleRoute() }
        .onChange(of: coordinator.pathCount) { _, _ in reportVisibleRoute() }
        .modifier(KeyboardDismissOnPush(pathCount: coordinator.pathCount))
        .modifier(TabBarVisibility(behavior: tabBarBehavior, pathCount: coordinator.pathCount, isVisible: $shouldShowTabBar))
        .environment(coordinator)
        .environment(reloadNotifier)
    }

    // MARK: - Private

    @ViewBuilder
    private func resolveModal(_ destination: D) -> some View {
        if destination.isStandalone {
            viewBuilder(destination)
        } else {
            NavigationHost(destination, tint: tint, tabBarBehavior: .untouched, viewBuilder: viewBuilder)
        }
    }

    private func reportVisibleRoute() {
        NavigationDiagnostics.report(route: coordinator.visibleDestination(root: root).routeName)
    }
}

/// A host without a tint applies no `.tint` at all, so the enclosing tint (or the app's accent
/// color) reaches its screens.
private struct OptionalTint: ViewModifier {
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let tint {
            content.tint(tint)
        } else {
            content
        }
    }
}

/// The keyboard goes down with a push and stays down on the way back.
///
/// UIKit hides the keyboard when a screen is pushed over the focused field and makes that field
/// first responder again as the pop brings its view back into the window. SwiftUI is not told in
/// time: the keyboard came back over a layout that never moved (a chat composer under the
/// keyboard after a visit to the partner's profile). Resigning when the push is requested leaves
/// UIKit nothing to restore.
private struct KeyboardDismissOnPush: ViewModifier {
    let pathCount: Int

    func body(content: Content) -> some View {
        content.onChange(of: pathCount) { previous, count in
            guard count > previous else { return }

            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

/// Tab bar handling kept out of the navigation transaction: the toolbar visibility is a
/// navigation request of its own, so it is applied on the next run-loop tick instead of in the
/// same frame as the path change.
private struct TabBarVisibility: ViewModifier {
    let behavior: NavigationHostTabBarBehavior
    let pathCount: Int
    @Binding var isVisible: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        switch behavior {
        case .untouched:
            content

        case .hidesOnPush:
            content
                .onChange(of: pathCount) { _, count in
                    Task { @MainActor in
                        withAnimation(.easeInOut(duration: 0.35)) { isVisible = count == 0 }
                    }
                }
                .toolbar(isVisible ? .visible : .hidden, for: .tabBar)
        }
    }
}
