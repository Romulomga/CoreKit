@testable import CoreKitNavigation
import Testing

@MainActor
@Suite struct NavigationDiagnosticsTests {

    @Test func reportsReachTheObserverUntilItIsRemoved() {
        let routes = Recorder<String>()
        NavigationDiagnostics.observe { routes.append($0) }

        NavigationDiagnostics.report(route: "home")
        NavigationDiagnostics.report(route: "detail")

        NavigationDiagnostics.observe(nil)
        NavigationDiagnostics.report(route: "ignored")

        #expect(routes.items == ["home", "detail"])
    }

    @Test func moreThanOneObserverHearsEveryRoute() {
        let main = Recorder<String>()
        let crashes = Recorder<String>()

        NavigationDiagnostics.observe { main.append($0) }

        let token = NavigationDiagnostics.addObserver { crashes.append($0) }

        NavigationDiagnostics.report(route: "home")

        NavigationDiagnostics.observe(nil)
        NavigationDiagnostics.report(route: "detail")

        NavigationDiagnostics.removeObserver(token)
        NavigationDiagnostics.report(route: "ignored")

        #expect(main.items == ["home"])
        #expect(crashes.items == ["home", "detail"])
    }
}
