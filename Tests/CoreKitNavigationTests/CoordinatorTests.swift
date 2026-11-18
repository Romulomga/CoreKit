@testable import CoreKitNavigation
import Observation
import os
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

    // MARK: - The same destination twice

    @Test func pushingTheDestinationOnTopDoesNothing() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .detail(7))
        coordinator.navigate(to: .detail(7))

        #expect(coordinator.destinations == [.detail(7)], "a double tap opens the screen once")
    }

    @Test func aDifferentValueStillStacks() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .detail(7))
        coordinator.navigate(to: .detail(8))

        #expect(coordinator.destinations == [.detail(7), .detail(8)])
    }

    @Test func theSameDestinationFurtherDownIsPushedAgain() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .detail(7))
        coordinator.navigate(to: .settings)
        coordinator.navigate(to: .detail(7))

        #expect(coordinator.destinations == [.detail(7), .settings, .detail(7)])
    }

    /// The modal slots rely on `@Observable` skipping an equal value (no guard of their own): this
    /// pins that, with a different sheet as the control that the tracking does see changes.
    @Test func presentingTheSheetAlreadyUpChangesNothing() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .settings, type: .sheet)

        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = coordinator.sheetDestination
        } onChange: {
            changed.withLock { $0 = true }
        }

        coordinator.navigate(to: .settings, type: .sheet)
        #expect(coordinator.sheetDestination == .settings)
        #expect(!changed.withLock { $0 }, "no change, so nothing watching the sheet re-renders")

        coordinator.navigate(to: .detail(1), type: .sheet)
        #expect(changed.withLock { $0 }, "control: another sheet is a change")
    }

    @Test func presentingTheCoverAlreadyUpChangesNothing() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .mainTab, type: .fullScreenCover)

        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = coordinator.fullCoverDestination
        } onChange: {
            changed.withLock { $0 = true }
        }

        coordinator.navigate(to: .mainTab, type: .fullScreenCover)
        #expect(coordinator.fullCoverDestination == .mainTab)
        #expect(!changed.withLock { $0 })
    }

    @Test func anotherSheetReplacesTheOneUp() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .settings, type: .sheet)
        coordinator.navigate(to: .detail(1), type: .sheet)

        #expect(coordinator.sheetDestination == .detail(1))
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

    // MARK: - Changes from the stack's own controls

    @Test func aLinkTappedTwiceStacksItsScreenOnce() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .detail(1))

        coordinator.applyStackChange(coordinator.path + [NavigationStep(destination: .settings)])
        coordinator.applyStackChange(coordinator.path + [NavigationStep(destination: .settings)])

        #expect(coordinator.destinations == [.detail(1), .settings])
    }

    @Test func aLinkKeepsTheEntryItPushed() {
        let coordinator = Coordinator<TestDestination>()
        let step = NavigationStep<TestDestination>(destination: .detail(2))

        coordinator.applyStackChange([step])

        #expect(coordinator.path == [step])
    }

    @Test func aLinkIsOfferedToTheInterceptor() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.pushInterceptor = { $0 == .settings }

        coordinator.applyStackChange([NavigationStep(destination: .settings)])

        #expect(coordinator.pathCount == 0)
    }

    @Test func theBackGestureIsTakenAsItIs() {
        let coordinator = Coordinator<TestDestination>()
        coordinator.navigate(to: .detail(1))
        coordinator.navigate(to: .settings)
        coordinator.navigate(to: .detail(3))

        coordinator.applyStackChange(Array(coordinator.path.prefix(1)))

        #expect(coordinator.destinations == [.detail(1)])
    }
}

@Suite struct TabBarRuleTests {

    @Test func theTabBarShowsAtTheRootOnly() {
        #expect(TabBarRule.showsTabBar(pathCount: 0))
        #expect(!TabBarRule.showsTabBar(pathCount: 1), "a host created over a pushed screen starts with the bar hidden")
    }
}
