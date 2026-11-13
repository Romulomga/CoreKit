@testable import CoreKitAnalytics
import CoreKitTesting
import SwiftUI
import Testing

@MainActor
struct AnalyticsHubTests {
    private let storeBuild = LaunchContext(isDebugBuild: false, arguments: [])
    private let debugBuild = LaunchContext(isDebugBuild: true, arguments: [])

    @Test func fansOutEveryCallToEveryEngine() {
        let firebase = EngineSpy()
        let mixpanel = EngineSpy()
        let hub = AnalyticsHub()

        hub.start(engines: [firebase.engine, mixpanel.engine], policy: .storeBuildsOnly, launch: storeBuild)

        hub.log("document_issued", parameters: ["kind": "receipt", "has_signature": true])
        hub.screen("home")
        hub.setUserProperty("true", forName: "is_pro")
        hub.recordError(SampleError(), context: "loadProducts")
        hub.logPurchase(PurchaseRevenue(itemID: "yearly", valueCents: 2490, currency: "BRL"))

        for spy in [firebase, mixpanel] {
            #expect(spy.client.events == [.init("document_issued", ["kind": "receipt", "has_signature": true])])
            #expect(spy.client.screens == ["home"])
            #expect(spy.client.userProperties == ["is_pro": "true"])
            #expect(spy.client.errors.map(\.context) == ["loadProducts"])
            #expect(spy.client.purchases.map(\.valueCents) == [2490])
        }
    }

    @Test func engineThatCantStartLeavesTheOthersRunning() {
        let running = EngineSpy()
        let withoutKey = AnalyticsEngine(name: "no key") { nil }
        let hub = AnalyticsHub()

        hub.start(engines: [withoutKey, running.engine], policy: .storeBuildsOnly, launch: storeBuild)
        hub.log("onboarding_complete", parameters: [:])

        #expect(hub.isCollecting)
        #expect(running.client.eventNames == ["onboarding_complete"])
    }

    @Test func debugBuildNeverStartsAnEngine() {
        let spy = EngineSpy()
        let hub = AnalyticsHub()

        hub.start(engines: [spy.engine], policy: .storeBuildsOnly, launch: debugBuild)
        hub.log("document_issued", parameters: [:])

        #expect(spy.starts == 0)
        #expect(spy.stayOffs == 1)
        #expect(!hub.isCollecting)
        #expect(spy.client.events.isEmpty)
    }

    @Test func secondStartIsIgnored() {
        let first = EngineSpy()
        let second = EngineSpy()
        let hub = AnalyticsHub()

        hub.start(engines: [first.engine], policy: .storeBuildsOnly, launch: storeBuild)
        hub.start(engines: [second.engine], policy: .storeBuildsOnly, launch: storeBuild)
        hub.screen("home")

        #expect(first.starts == 1)
        #expect(second.starts == 0)
        #expect(first.client.screens == ["home"])
    }

    /// The real entry point, in this process: a test run is a debug build.
    @Test func startInADebugProcessCollectsNothing() {
        let spy = EngineSpy()

        Analytics.start(engines: [spy.engine], policy: .storeBuildsOnly)
        Analytics.shared.log("first_open", parameters: [:])

        #expect(spy.starts == 0)
        #expect(!Analytics.isCollecting)
        #expect(spy.client.events.isEmpty)
    }

    /// A view outside the scope the app injects into still reaches the engines.
    @Test func environmentDefaultsToTheSharedClient() {
        #expect(EnvironmentValues().analytics as AnyObject === Analytics.shared as AnyObject)
    }
}

@MainActor
private final class EngineSpy {
    let client = RecordingAnalyticsClient()
    private(set) var starts = 0
    private(set) var stayOffs = 0

    var engine: AnalyticsEngine {
        AnalyticsEngine(name: "spy") { [self] in
            starts += 1
            return client
        } stayOff: { [self] in
            stayOffs += 1
        }
    }
}

private struct SampleError: Error {}
