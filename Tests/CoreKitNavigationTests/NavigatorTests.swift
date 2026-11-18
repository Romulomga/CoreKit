@testable import CoreKitNavigation
import Foundation
import Testing

@MainActor
@Suite struct NavigatorTests {

    // MARK: - Stacks

    @Test func eachTabHasItsOwnStackCreatedOnDemand() {
        let navigator = Navigator<TabRoute>(tab: .home)

        let home = navigator.coordinator(for: .home)
        #expect(navigator.coordinator(for: .home) === home, "asking again gives the same stack")
        #expect(navigator.coordinator(for: .inbox) !== home)
        #expect(navigator.isAtRoot(.inbox), "a stack never asked for is at its root")
    }

    @Test func isAtRootSeesPushesAndModals() {
        let navigator = Navigator<TabRoute>(tab: .home)
        let home = navigator.coordinator(for: .home)

        home.navigate(to: .detail(1))
        #expect(!navigator.isAtRoot(.home))

        navigator.popToRoot(.home)
        #expect(navigator.isAtRoot(.home))

        home.navigate(to: .detail(2), type: .sheet)
        #expect(!navigator.isAtRoot(.home), "a sheet open on the tab is not its root")
    }

    // MARK: - Opening

    @Test func aTabRouteSwitchesTabAndPushesOnTheNextTurn() async {
        let navigator = Navigator<TabRoute>(tab: .inbox)
        let home = navigator.coordinator(for: .home)

        navigator.open(.detail(7))

        #expect(navigator.selection == .home)
        #expect(home.destinations.isEmpty, "the push waits for the tab switch to land")
        await waitUntil { home.destinations == [.detail(7)] }
    }

    @Test func aRouteOnTheSelectedTabPushesAtOnce() {
        let navigator = Navigator<TabRoute>(tab: .home)

        navigator.open(.detail(7))

        #expect(navigator.coordinator(for: .home).destinations == [.detail(7)])
    }

    @Test func aRouteThatOpensOnTheSelectedTabStaysOnIt() {
        let navigator = Navigator<TabRoute>(tab: .inbox)

        navigator.open(.profile)

        #expect(navigator.selection == .inbox)
        #expect(navigator.coordinator(for: .inbox).destinations == [.profile])
        #expect(navigator.root.destinations.isEmpty, "not behind the main tab's cover")
    }

    @Test func aRouteWithoutATabGoesOnTheBottomStack() {
        let navigator = Navigator<TabRoute>(tab: .home)

        navigator.open(.login)

        #expect(navigator.root.destinations == [.login])
        #expect(navigator.isAtRoot(.home))
    }

    @Test func theTabItselfPopsToItsRoot() {
        let navigator = Navigator<TabRoute>(tab: .home)
        navigator.open(.detail(1))
        navigator.open(.detail(2))

        navigator.open(.home)

        #expect(navigator.isAtRoot(.home))
    }

    @Test func theScreenAlreadyOnTopStays() {
        let navigator = Navigator<TabRoute>(tab: .home)
        navigator.open(.detail(1))

        navigator.open(.detail(1))

        #expect(navigator.coordinator(for: .home).destinations == [.detail(1)])
    }

    @Test func aRouteThatReplacesStackReplacesIt() {
        let navigator = Navigator<TabRoute>(tab: .inbox)
        navigator.open(.conversation(1))

        navigator.open(.conversation(2))

        #expect(navigator.coordinator(for: .inbox).destinations == [.conversation(2)], "back leads to the list, not to the other conversation")
    }

    @Test func aModalOnTheTabClosesBeforeThePush() async {
        let navigator = Navigator<TabRoute>(tab: .home)
        let home = navigator.coordinator(for: .home)
        home.navigate(to: .detail(1), type: .sheet)

        navigator.open(.detail(2))

        #expect(home.sheetDestination == nil, "the sheet goes at once")
        await waitUntil { home.destinations == [.detail(2)] }
    }

    @Test func aURLOpensItsRouteAndAnUnknownOneIsLeftToTheApp() async throws {
        let navigator = Navigator<TabRoute>(tab: .inbox)
        let home = navigator.coordinator(for: .home)

        #expect(navigator.open(try #require(URL(string: "app://detail/3"))))
        await waitUntil { home.destinations == [.detail(3)] }

        #expect(!navigator.open(try #require(URL(string: "https://example.com/page"))))
        #expect(navigator.selection == .home, "nothing changed")
    }

    @Test func aRouteOpensTheWayItSaysItShows() {
        let navigator = Navigator<SheetRoute>(tab: .list)

        navigator.open(.editor(1))

        #expect(navigator.coordinator(for: .list).sheetDestination == .editor(1), "a deep link shows the editor as the app does")
        #expect(navigator.isAtRoot(.list) == false)
        #expect(navigator.coordinator(for: .list).pathCount == 0)
    }

    @Test func navigateWithoutATypeUsesThePresentation() {
        let coordinator = Coordinator<SheetRoute>()

        coordinator.navigate(to: .editor(2))
        #expect(coordinator.sheetDestination == .editor(2))

        coordinator.navigate(to: .editor(3), type: .push)
        #expect(coordinator.destinations == [.editor(3)], "an explicit type still wins")
    }

    // MARK: - Holding links

    @Test func aHeldLinkOpensWhenTheAppBecomesReady() async {
        let readiness = Readiness()
        let navigator = Navigator<TabRoute>(tab: .inbox)
        navigator.holdLinks(until: { readiness.isReady })

        navigator.open(.detail(5))
        #expect(navigator.heldLink == .detail(5))
        #expect(navigator.isAtRoot(.home), "nothing opens while held")

        readiness.isReady = true

        await waitUntil { navigator.coordinator(for: .home).destinations == [.detail(5)] }
        #expect(navigator.heldLink == nil)
        #expect(navigator.selection == .home)
    }

    @Test func theBottomStackIsNotHeld() {
        let navigator = Navigator<TabRoute>(tab: .home)
        navigator.holdLinks(until: { false })

        navigator.open(.login)

        #expect(navigator.root.destinations == [.login], "the auth flow is what shows while links wait")
        #expect(navigator.heldLink == nil)
    }

    @Test func aDiscardedLinkNeverOpens() async {
        let readiness = Readiness()
        let navigator = Navigator<TabRoute>(tab: .home)
        navigator.holdLinks(until: { readiness.isReady })
        navigator.open(.detail(9))

        navigator.discardHeldLink()
        readiness.isReady = true
        await Task.yield()
        await Task.yield()

        #expect(navigator.isAtRoot(.home))
    }

    // MARK: - Reset and session

    @Test func resetClearsTheTabsAndKeepsTheBottomStack() {
        let navigator = Navigator<TabRoute>(tab: .home)
        navigator.open(.login)
        navigator.open(.conversation(1))
        navigator.holdLinks(until: { false })
        navigator.open(.detail(1))

        navigator.reset()

        #expect(navigator.selection == .home)
        #expect(navigator.isAtRoot(.inbox))
        #expect(navigator.heldLink == nil)
        #expect(navigator.root.destinations == [.login])
    }

    @Test func aLogoutResetsTheTabsOnceTheCoverIsGone() async {
        let navigator = Navigator<TabRoute>(tab: .home)
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        let observer = SessionObserver(navigator: navigator, isLoggedInStream: stream, coverPresentationDelay: .zero)

        continuation.yield(true)
        await waitUntil { navigator.root.fullCoverDestination == .mainTab }
        navigator.open(.conversation(1))

        continuation.yield(false)
        await waitUntil { navigator.root.fullCoverDestination == nil && navigator.isAtRoot(.inbox) }
        #expect(navigator.selection == .home, "the next session starts on the first tab")
        _ = observer
    }
}
