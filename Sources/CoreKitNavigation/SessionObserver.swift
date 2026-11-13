import SwiftUI

/// A route enum with a logged-in container, for `SessionObserver`. Only a login-gated app needs
/// it: the rest conform to `NavigableDestination` alone.
public protocol SessionDestination: NavigableDestination {

    /// Presented as a full-screen cover over the auth flow on login, dismissed on logout.
    static var mainTab: Self { get }
}

/// Bridges session state changes to navigation: login presents `D.mainTab` over the auth flow,
/// logout dismisses it. The app provides the login stream and its side effects as closures, so
/// CoreKit stays independent from the app's session and its SDKs.
///
/// iOS only: no Android app has a login yet.
@MainActor
public final class SessionObserver<D: SessionDestination> {

    private weak var coordinator: Coordinator<D>?

    private var stateTask: Task<Void, Never>?

    private var pendingReset: Task<Void, Never>?

    private let coverPresentationDelay: Duration

    /// - Parameters:
    ///   - coordinator: The navigation coordinator to drive on state changes.
    ///   - isLoggedInStream: Emits `true` on login and `false` on logout.
    ///   - onLoggedIn: Side effects after login navigation (push registration, analytics identify).
    ///   - onLoggedOut: Side effects after logout navigation.
    ///   - coverPresentationDelay: Time for the full-screen cover to finish presenting or
    ///     dismissing before the stack underneath is reset, so the user never sees the pop
    ///     animation. Tests pass `.zero`.
    public init(
        coordinator: Coordinator<D>,
        isLoggedInStream: AsyncStream<Bool>,
        onLoggedIn: @escaping @MainActor @Sendable () -> Void = {},
        onLoggedOut: @escaping @MainActor @Sendable () -> Void = {},
        coverPresentationDelay: Duration = .milliseconds(600)
    ) {
        self.coordinator = coordinator
        self.coverPresentationDelay = coverPresentationDelay

        stateTask = Task { [weak self] in
            // The app starts logged out with nothing presented, so a leading `false`
            // (the stream's current value on subscribe) is not a logout.
            var previous = false

            for await isLoggedIn in isLoggedInStream {
                guard isLoggedIn != previous else { continue }

                previous = isLoggedIn

                guard let self else { return }

                if isLoggedIn {
                    // Present first: the cover slides over whatever auth screen is on top
                    // (e.g. login). Only then reset the stack behind it, without animation,
                    // so logout lands on the root with a single dismiss.
                    coordinator.navigate(to: D.mainTab, type: .fullScreenCover)
                    onLoggedIn()

                    scheduleReset { coordinator in
                        coordinator.popToRoot()
                    }
                } else {
                    // One navigation change per frame: dismiss the cover (animated), then
                    // clear any sheet and the stack behind it once the dismissal is done.
                    coordinator.dismissFullCover()
                    onLoggedOut()

                    scheduleReset { coordinator in
                        coordinator.dismissSheet()
                        coordinator.popToRoot()
                    }
                }
            }
        }
    }

    /// Runs `reset` without animation after the cover transition. A state change in the
    /// meantime cancels it, so a quick login→logout never waits on the previous reset.
    private func scheduleReset(_ reset: @escaping @MainActor (Coordinator<D>) -> Void) {
        pendingReset?.cancel()

        pendingReset = Task { [weak self, delay = coverPresentationDelay] in
            try? await Task.sleep(for: delay)

            guard !Task.isCancelled, let coordinator = self?.coordinator else { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true

            withTransaction(transaction) {
                reset(coordinator)
            }
        }
    }

    deinit {
        stateTask?.cancel()
        pendingReset?.cancel()
    }
}
