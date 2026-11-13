import SwiftUI
import StoreKit

extension View {
    /// The point where a good moment becomes the system review prompt. Put it on a view that outlives the
    /// screens where moments happen (the root, or the screen the person lands back on), and set `moment` when
    /// one qualifies.
    ///
    /// When `moment` is set and `gate` allows it, this waits `delay` and calls `requestReview`, then marks the
    /// gate and clears `moment`. Each step fixes a way the copies in the apps lost or wasted the prompt:
    /// - The wait lets a closing sheet or a navigation pop finish: a presentation still in flight swallows the
    ///   prompt.
    /// - It only asks while the scene is active. In the background the call shows nothing and the mark would
    ///   still spend the version; the moment waits, and the return (from the share sheet's target app, say)
    ///   asks.
    /// - Leaving the view during the wait cancels the attempt instead of asking over whatever came next (a
    ///   `try?` around the sleep, as the copies had, asked anyway); the moment stays for the view's return. A
    ///   new moment restarts the wait.
    /// - The gate is marked right after the call, never before (see `ReviewGate.markRequested()`).
    ///
    /// A moment that arrives when the gate is closed is cleared at once: waiting doesn't open it.
    ///
    /// - Parameters:
    ///   - moment: the app's pending moment. `nil` means nothing to ask.
    ///   - delay: how long the screen needs to settle after the moment.
    ///   - isEnabled: `false` holds the request and keeps the moment (under UI tests, where the prompt would
    ///     cover the screen; over a forced-update wall).
    ///   - onRequest: called with the moment once the system was asked, for the app's analytics.
    public func reviewRequest<Moment: Equatable>(
        for moment: Binding<Moment?>,
        gate: ReviewGate,
        delay: Duration = .seconds(1),
        isEnabled: Bool = true,
        onRequest: @escaping @MainActor (Moment) -> Void = { _ in }
    ) -> some View {
        modifier(ReviewRequestModifier(moment: moment, gate: gate, delay: delay, isEnabled: isEnabled, onRequest: onRequest))
    }
}

private struct ReviewRequestModifier<Moment: Equatable>: ViewModifier {
    @Binding var moment: Moment?

    let gate: ReviewGate
    let delay: Duration
    let isEnabled: Bool
    let onRequest: @MainActor (Moment) -> Void

    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    /// What restarts the attempt: a new moment, or the scene (or the app) letting it ask again.
    private struct Attempt: Equatable {
        let moment: Moment?
        let canAsk: Bool
    }

    func body(content: Content) -> some View {
        let canAsk = isEnabled && scenePhase == .active

        content.task(id: Attempt(moment: moment, canAsk: canAsk)) {
            guard let pending = moment else { return }

            switch await ReviewAttempt.run(gate: gate, canAsk: canAsk, delay: delay, request: { requestReview() }) {
            case .asked:
                moment = nil
                onRequest(pending)
            case .gateClosed:
                moment = nil
            case .held:
                break
            }
        }
    }
}

/// One attempt of the request point, apart from SwiftUI so it can be tested.
@MainActor
enum ReviewAttempt {
    enum Outcome: Equatable {
        /// The system was asked and the gate marked: the moment is spent.
        case asked
        /// The gate is closed, and waiting won't open it: the moment is dropped.
        case gateClosed
        /// Not now (the scene isn't active, the app holds requests, or the wait was interrupted): the moment
        /// stays for the next attempt.
        case held
    }

    static func run(gate: ReviewGate, canAsk: Bool, delay: Duration, request: () -> Void) async -> Outcome {
        guard gate.isEligible else { return .gateClosed }

        guard canAsk else { return .held }

        do {
            try await Task.sleep(for: delay)
        } catch {
            return .held
        }

        guard !Task.isCancelled else { return .held }

        // Another request point may have asked during the wait.
        guard gate.isEligible else { return .gateClosed }

        request()
        gate.markRequested()

        return .asked
    }
}
