import Foundation
import Observation

/// Tells a screen that stayed alive under another one to refresh: the start screen under the
/// main tab after a logout, a list under the screen that changed one of its items. The screen
/// never disappeared, so `onAppear` and `task` don't run again. Views react with `onReload(of:)`.
///
/// iOS only: on Android the screen's ViewModel observes its data instead.
@MainActor
@Observable
public final class ReloadNotifier<D: NavigableDestination> {

    private(set) var signal: ReloadSignal<D>?

    public init() {}

    public func notify(_ destination: D) {
        signal = ReloadSignal(destination: destination)
    }
}

/// One `notify`. Its own id makes two notifies for the same destination two changes, so the
/// second refresh is not swallowed as "nothing changed".
struct ReloadSignal<D: NavigableDestination>: Equatable {
    let id = UUID()
    let destination: D
}
