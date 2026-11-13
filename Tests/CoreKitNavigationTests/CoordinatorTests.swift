@testable import CoreKitNavigation
import Testing

@MainActor
@Suite struct CoordinatorTests {

    // MARK: - Push and pop

    @Test func pushAndPop() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .detail(1))
        coordinator.navigate(to: .settings)
        #expect(coordinator.pathCount == 2)
        #expect(coordinator.currentDestination == .settings)

        coordinator.pop()
        #expect(coordinator.currentDestination == .detail(1))
    }

    @Test func popOnAnEmptyStackDoesNothing() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.pop()
        #expect(coordinator.pathCount == 0)
    }

    @Test func popToDestinationTrimsEverythingAbove() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .detail(1))
        coordinator.navigate(to: .detail(2))
        coordinator.navigate(to: .settings)

        coordinator.pop(to: .detail(1))
        #expect(coordinator.pathCount == 1)
        #expect(coordinator.currentDestination == .detail(1))

        coordinator.pop(to: .settings)
        #expect(coordinator.destinations == [.detail(1)], "a destination not in the stack pops nothing")
    }

    @Test func containsLooksAtTheWholeStack() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .detail(1))
        coordinator.navigate(to: .settings)

        #expect(coordinator.contains(.detail(1)))
        #expect(!coordinator.contains(.detail(2)))
    }

    @Test func sameDestinationCanBePushedTwice() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .detail(7))
        coordinator.navigate(to: .detail(7))
        #expect(coordinator.pathCount == 2)
    }

    // MARK: - Modals

    @Test func modalsWinOverPathWhenReportingVisibleDestination() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .detail(1))
        #expect(coordinator.visibleDestination(root: .root) == .detail(1))

        coordinator.navigate(to: .settings, type: .sheet)
        #expect(coordinator.visibleDestination(root: .root) == .settings)

        coordinator.navigate(to: .mainTab, type: .fullScreenCover)
        #expect(coordinator.visibleDestination(root: .root) == .mainTab)

        coordinator.dismissFullCover()
        coordinator.dismissSheet()
        coordinator.popToRoot()
        #expect(coordinator.visibleDestination(root: .root) == .root)
    }

    // MARK: - Replacing the stack

    @Test func replaceAllLeavesOnlyTheNewDestination() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .detail(1))
        coordinator.navigate(to: .settings)

        coordinator.replaceAll(with: .detail(2))
        #expect(coordinator.destinations == [.detail(2)], "back from the new screen lands on the root")
    }

    @Test func replaceAllWithAListKeepsItsOrder() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .detail(1))

        coordinator.replaceAll(with: [.settings, .detail(2)])
        #expect(coordinator.destinations == [.settings, .detail(2)])

        coordinator.replaceAll(with: [])
        #expect(coordinator.pathCount == 0)
    }

    // MARK: - Interceptor

    @Test func interceptorTakesThePushesItClaims() {
        let coordinator = Coordinator<TestDestination>()
        let taken = Recorder<TestDestination>()
        coordinator.pushInterceptor = { destination in
            guard case .detail = destination else { return false }

            taken.append(destination)
            return true
        }

        coordinator.navigate(to: .settings)
        coordinator.navigate(to: .detail(1))
        #expect(coordinator.destinations == [.settings])
        #expect(taken.items == [.detail(1)])

        coordinator.replaceAll(with: .detail(2))
        #expect(coordinator.pathCount == 0, "a claimed replacement still clears the stack")
        #expect(taken.items == [.detail(1), .detail(2)])

        coordinator.replaceAll(with: [.settings, .detail(3)])
        #expect(coordinator.destinations == [.settings], "a claimed destination of a list stays out of the stack")
        #expect(taken.items == [.detail(1), .detail(2), .detail(3)])

        coordinator.navigate(to: .detail(4), type: .sheet)
        #expect(coordinator.sheetDestination == .detail(4), "modals are never offered")

        coordinator.pushInterceptor = nil
        coordinator.navigate(to: .detail(5))
        #expect(coordinator.currentDestination == .detail(5))
    }
}
