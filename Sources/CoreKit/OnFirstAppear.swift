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
