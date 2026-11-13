@testable import CoreKitNavigation
import SwiftUI
import Testing

/// `PlainRoute` declares no requirement at all: these fail to compile without the defaults, and
/// it never has to name a `mainTab`.
@MainActor
@Suite struct NavigableDestinationTests {

    @Test func aPlainRouteGetsTheDefaults() {
        let route = PlainRoute.detail(id: 3)

        #expect(route.id == route, "the route is its own identity")
        #expect(!route.isStandalone, "a presented route gets a stack of its own")
        #expect(route.presentationDetent == [.large])
        #expect(route.routeName == "detail(id: 3)")
    }

    @Test func aDeclaredIdentityWinsOverTheDefault() {
        #expect(TestDestination.detail(2).id == "detail(2)")
        #expect(TestDestination.detail(2).routeName == "detail(2)")
        #expect(TestDestination.mainTab.isStandalone)
        #expect(TestDestination.root.presentationDetent.isEmpty)
    }

    @Test func aPlainRouteNavigatesAndSwitchesTabs() {
        let coordinator = Coordinator<PlainRoute>()
        coordinator.navigate(to: .list)
        coordinator.navigate(to: .detail(id: 1))
        coordinator.navigate(to: .detail(id: 1))
        #expect(coordinator.destinations == [.list, .detail(id: 1)])

        coordinator.navigate(to: .detail(id: 2), type: .sheet)
        #expect(coordinator.visibleDestination(root: .home) == .detail(id: 2))

        let tabs = TabNavigation<PlainRoute>(selection: .home)
        tabs.switch(to: .list)
        #expect(tabs.selection == .list)
    }
}
