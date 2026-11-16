import SwiftUI

extension View {

    /// Runs `action` the first time the view appears, and never again for the same view identity.
    ///
    /// `onAppear` runs again every time the view comes back: a pop back to it, a tab switch, a
    /// sheet closing over it. Launch work (starting the session, binding the app delegate) ran
    /// twice that way. Once per entry in the stack is the count CoreKit-Android's `TrackOnce`
    /// keeps.
    public func onFirstAppear(perform action: @escaping () -> Void) -> some View {
        modifier(OnFirstAppearModifier(action: action))
    }

    /// Runs the async `action` the first time the view appears, in a task tied to the view, and
    /// never again once it has finished.
    ///
    /// A screen's first load used `.task { await viewModel.load() }`, which loads again on every
    /// return to the screen (a pop back, a tab switch, a sheet closing). Here it runs once per
    /// entry in the stack. Leaving before it finishes cancels it, and the next appearance runs it
    /// again: a screen left mid-load never comes back empty. Pull-to-refresh and retry call the
    /// view model directly. Twin of CoreKit-Android's `LaunchedOnce`.
    public func onFirstAppear(perform action: @escaping @MainActor () async -> Void) -> some View {
        modifier(OnFirstAppearTaskModifier(action: action))
    }
}

private struct OnFirstAppearModifier: ViewModifier {
    let action: () -> Void

    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !hasAppeared else { return }

                hasAppeared = true
                action()
            }
    }
}

private struct OnFirstAppearTaskModifier: ViewModifier {
    let action: @MainActor () async -> Void

    @State private var gate = FirstRunGate()

    func body(content: Content) -> some View {
        content
            .task {
                await gate.run(action)
            }
    }
}

/// Runs an action until one run finishes without being cancelled.
@MainActor
final class FirstRunGate {

    private(set) var hasFinished = false
    private var isRunning = false

    func run(_ action: @MainActor () async -> Void) async {
        guard !hasFinished, !isRunning else { return }

        isRunning = true
        defer { isRunning = false }

        await action()

        if !Task.isCancelled {
            hasFinished = true
        }
    }
}
