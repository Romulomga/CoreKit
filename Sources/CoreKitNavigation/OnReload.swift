import SwiftUI

extension View {

    /// Runs `action` whenever the `ReloadNotifier` of the enclosing `NavigationHost` is told to
    /// reload `destination`. Outside a host (a preview) it never runs.
    public func onReload<D: NavigableDestination>(
        of destination: D,
        perform action: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(OnReloadModifier(destination: destination, action: action))
    }
}

private struct OnReloadModifier<D: NavigableDestination>: ViewModifier {
    @Environment(ReloadNotifier<D>.self) private var notifier: ReloadNotifier<D>?

    let destination: D
    let action: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: notifier?.signal?.id) { _, _ in
                guard notifier?.signal?.destination == destination else { return }

                action()
            }
    }
}
