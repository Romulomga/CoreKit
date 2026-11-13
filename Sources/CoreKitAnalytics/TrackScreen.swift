import SwiftUI

extension View {
    /// Logs a screen view each time this view appears, with `.onAppear`'s count: coming back from a
    /// pushed screen or from another tab counts again, a re-render doesn't. CoreKit-Android's
    /// `TrackAppearance` counts the same way, so the funnels of the two platforms compare.
    ///
    /// An app with a screen enum keeps a one-line overload that passes its raw value.
    public func trackScreen(_ name: String) -> some View {
        modifier(TrackScreenModifier(name: name))
    }
}

private struct TrackScreenModifier: ViewModifier {
    @Environment(\.analytics) private var analytics

    let name: String

    func body(content: Content) -> some View {
        content.onAppear { analytics.screen(name) }
    }
}
