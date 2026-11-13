@testable import CoreKitNavigation
import Testing

@MainActor
@Suite struct SessionObserverTests {

    @Test func ignoresTheInitialLoggedOutValue() async {
        let coordinator = Coordinator<TestDestination>()
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        let logouts = Recorder<Void>()
        let observer = SessionObserver(
            coordinator: coordinator,
            isLoggedInStream: stream,
            onLoggedOut: { logouts.append(()) },
            coverPresentationDelay: .zero
        )

        continuation.yield(false)
        continuation.yield(true)
        await waitUntil { coordinator.fullCoverDestination == .mainTab }
        #expect(logouts.items.isEmpty, "the stream's first value is the current state, not a logout")

        continuation.yield(false)
        await waitUntil { coordinator.fullCoverDestination == nil }
        #expect(logouts.items.count == 1)
        _ = observer
    }

    @Test func presentsTheMainTabOnLoginAndResetsTheAuthStackBehindIt() async {
        let coordinator = Coordinator<TestDestination>()
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        let observer = SessionObserver(coordinator: coordinator, isLoggedInStream: stream, coverPresentationDelay: .zero)
        coordinator.navigate(to: .detail(1))

        continuation.yield(true)
        await waitUntil { coordinator.fullCoverDestination == .mainTab && coordinator.pathCount == 0 }
        #expect(coordinator.fullCoverDestination == .mainTab)
        #expect(coordinator.pathCount == 0, "auth stack is reset behind the cover")

        continuation.yield(false)
        await waitUntil { coordinator.fullCoverDestination == nil }
        #expect(coordinator.fullCoverDestination == nil)
        _ = observer
    }

    @Test func logoutClearsTheSheetAndTheStackAfterTheCoverGoes() async {
        let coordinator = Coordinator<TestDestination>()
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        let observer = SessionObserver(coordinator: coordinator, isLoggedInStream: stream, coverPresentationDelay: .zero)

        continuation.yield(true)
        await waitUntil { coordinator.fullCoverDestination == .mainTab }

        coordinator.navigate(to: .settings)
        coordinator.navigate(to: .detail(1), type: .sheet)

        continuation.yield(false)
        await waitUntil { coordinator.fullCoverDestination == nil && coordinator.sheetDestination == nil && coordinator.pathCount == 0 }
        #expect(coordinator.sheetDestination == nil)
        #expect(coordinator.pathCount == 0)
        _ = observer
    }
}
