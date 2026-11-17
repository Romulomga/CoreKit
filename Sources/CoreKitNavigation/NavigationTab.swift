import SwiftUI

/// One tab of a `TabNavigationRoot(navigator)`: a `NavigationHost` on the navigator's stack for `tab`, tagged with it,
/// with its label in the tab bar. The navigator comes from the environment; the app writes only the tab, how to build
/// a screen and the label.
public struct NavigationTab<D: NavigableDestination, Screen: View, Label: View>: View {

    @Environment(Navigator<D>.self) private var navigator

    private let tab: D

    private let tint: Color?

    private let tabBarBehavior: NavigationHostTabBarBehavior

    private let screen: @MainActor (D) -> Screen

    private let label: () -> Label

    public init(
        _ tab: D,
        tint: Color? = nil,
        tabBarBehavior: NavigationHostTabBarBehavior = .hidesOnPush,
        screen: @escaping @MainActor (D) -> Screen,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.tab = tab
        self.tint = tint
        self.tabBarBehavior = tabBarBehavior
        self.screen = screen
        self.label = label
    }

    public var body: some View {
        NavigationHost(tab, tint: tint, coordinator: navigator.coordinator(for: tab), tabBarBehavior: tabBarBehavior) { destination in
            screen(destination)
        }
        .tabItem(label)
        .tag(tab)
    }
}
