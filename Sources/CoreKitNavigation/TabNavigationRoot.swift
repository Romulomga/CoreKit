import SwiftUI

/// A `TabView` bound to a `TabNavigation`, which it puts in the environment and whose selection it
/// reports to `NavigationDiagnostics`. Each tab is usually a `NavigationHost` with a coordinator
/// of its own, tagged with its root destination.
public struct TabNavigationRoot<D: NavigableDestination, Content: View>: View {

    @State private var tabNavigation: TabNavigation<D>

    private let content: () -> Content

    private let animateSelection: Bool

    public init(
        tabNavigation: TabNavigation<D>,
        animateSelection: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.content = content
        self.animateSelection = animateSelection
        self._tabNavigation = State(initialValue: tabNavigation)
    }

    public var body: some View {
        @Bindable var tabNavigation = tabNavigation

        TabView(selection: $tabNavigation.selection) {
            content()
        }
        .onAppear {
            NavigationDiagnostics.report(route: tabNavigation.selection.routeName)
        }
        .onChange(of: tabNavigation.selection.id) { _, _ in
            NavigationDiagnostics.report(route: tabNavigation.selection.routeName)
        }
        .animation(animateSelection ? .easeInOut(duration: 0.25) : nil, value: tabNavigation.selection)
        .environment(tabNavigation)
    }
}
