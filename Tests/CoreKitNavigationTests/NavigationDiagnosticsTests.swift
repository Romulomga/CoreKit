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
}
