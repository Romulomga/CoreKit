import CoreKitAnalytics
import CoreKitTesting
import SwiftUI
import Testing
import UIKit

@MainActor
struct TrackScreenTests {
    @Test func logsEachTimeTheScreenAppears() async {
        let analytics = RecordingAnalyticsClient()
        let screen = ScreenState()
        let window = show(Probe(screen: screen), analytics: analytics)
        defer { window.isHidden = true }

        await waitUntil { analytics.screens.count == 1 }

        screen.isShown = false
        await waitUntil { false }

        screen.isShown = true
        await waitUntil { analytics.screens.count == 2 }

        #expect(analytics.screens == ["home", "home"])
    }

    @Test func reRenderDoesNotLogAgain() async {
        let analytics = RecordingAnalyticsClient()
        let screen = ScreenState()
        let window = show(Probe(screen: screen), analytics: analytics)
        defer { window.isHidden = true }

        await waitUntil { analytics.screens.count == 1 }

        screen.renders += 1
        await waitUntil { false }

        #expect(analytics.screens == ["home"])
    }

    private func show(_ view: some View, analytics: any AnalyticsClient) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))

        window.rootViewController = UIHostingController(rootView: view.environment(\.analytics, analytics))
        window.makeKeyAndVisible()

        return window
    }

    /// Lets SwiftUI run its updates until `condition` holds, or for a short while when it never will.
    private func waitUntil(_ condition: () -> Bool, timeout: Duration = .milliseconds(500)) async {
        let deadline = ContinuousClock.now + timeout

        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
@Observable
private final class ScreenState {
    var isShown = true
    var renders = 0
}

private struct Probe: View {
    let screen: ScreenState

    var body: some View {
        VStack {
            if screen.isShown {
                Text("Home \(screen.renders)")
                    .trackScreen("home")
            }
        }
    }
}
