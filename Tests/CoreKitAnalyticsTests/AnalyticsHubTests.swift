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
        hub.setUserProperties(["is_notification_enabled": true])
        hub.setUserProfile(["$name": "Ana"])
        hub.recordError(SampleError(), context: "loadProducts")
        hub.logPurchase(PurchaseRevenue(itemID: "yearly", valueCents: 2490, currency: "BRL"))

        for spy in [firebase, mixpanel] {
            #expect(spy.client.events == [.init("document_issued", ["kind": "receipt", "has_signature": true])])
            #expect(spy.client.screens == ["home"])
            #expect(spy.client.userProperties == ["is_pro": "true"])
            #expect(spy.client.typedUserProperties == ["is_notification_enabled": true])
            #expect(spy.client.profiles == [["$name": "Ana"]])
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

    // MARK: - The user's switch

    @Test func switchedOffBeforeStartNoEngineIsSetUp() {
        let spy = EngineSpy()
        let hub = AnalyticsHub()

        hub.setCollectionEnabled(false)
        hub.start(engines: [spy.engine], policy: .storeBuildsOnly, launch: storeBuild)
        hub.log("first_open", parameters: [:])

        #expect(spy.starts == 0, "nothing leaves the device, not even the launch events")
        #expect(spy.stayOffs == 1)
        #expect(!hub.isCollecting)
        #expect(spy.client.events.isEmpty)
    }

    @Test func switchedOnLaterTheEnginesStartThen() {
        let spy = EngineSpy()
        let hub = AnalyticsHub()

        hub.setCollectionEnabled(false)
        hub.start(engines: [spy.engine], policy: .storeBuildsOnly, launch: storeBuild)
        hub.setCollectionEnabled(true)
        hub.log("document_issued", parameters: [:])

        #expect(spy.starts == 1)
        #expect(spy.client.eventNames == ["document_issued"])
    }

    @Test func switchedOffWhileRunningEveryEngineStopsAndComesBack() {
        let firebase = EngineSpy()
        let mixpanel = EngineSpy()
        let hub = AnalyticsHub()

        hub.start(engines: [firebase.engine, mixpanel.engine], policy: .storeBuildsOnly, launch: storeBuild)
        hub.setCollectionEnabled(false)
        hub.log("while_off", parameters: [:])
        hub.screen("while_off")
        hub.setCollectionEnabled(true)
        hub.log("back_on", parameters: [:])

        for spy in [firebase, mixpanel] {
            #expect(spy.switches == [false, true], "each SDK switches its own collection")
            #expect(spy.starts == 1, "a running engine is not set up again")
            #expect(spy.client.eventNames == ["back_on"])
            #expect(spy.client.screens.isEmpty)
        }
    }

    @Test func anEngineThatDidntStartIsNotSwitched() {
        let running = EngineSpy()
        let withoutKey = EngineSpy(starts: false)
        let hub = AnalyticsHub()

        hub.start(engines: [withoutKey.engine, running.engine], policy: .storeBuildsOnly, launch: storeBuild)
        hub.setCollectionEnabled(false)

        #expect(withoutKey.switches.isEmpty, "an SDK never set up can trap when called")
        #expect(running.switches == [false])
    }

    @Test func theBuildsPolicyWinsOverTheSwitch() {
        let spy = EngineSpy()
        let hub = AnalyticsHub()

        hub.start(engines: [spy.engine], policy: .storeBuildsOnly, launch: debugBuild)
        hub.setCollectionEnabled(false)
        hub.setCollectionEnabled(true)

        #expect(spy.starts == 0)
        #expect(!hub.isCollecting)
    }

    // MARK: - Errors

    @Test func anErrorTravelsWithoutItsMessage() {
        let spy = EngineSpy()
        let hub = AnalyticsHub()
        let typed = NSError(domain: "Save", code: 7, userInfo: [NSLocalizedDescriptionKey: "Maria da Silva, CPF 123"])

        hub.start(engines: [spy.engine], policy: .storeBuildsOnly, launch: storeBuild)
        hub.recordError(typed, context: "save")

        let recorded = spy.client.errors.map(\.description)
        #expect(recorded.count == 1)
        #expect(recorded.allSatisfy { $0.contains("Save") && $0.contains("7") })
        #expect(recorded.allSatisfy { !$0.contains("Maria") && !$0.contains("CPF") })
    }

    /// A view outside the scope the app injects into still reaches the engines.
    // MARK: - Who, and what came before a crash

    @Test func theUserAndTheCrashTrailReachEveryEngine() {
        let firebase = EngineSpy()
        let mixpanel = EngineSpy()
        let hub = AnalyticsHub()

        hub.start(engines: [firebase.engine, mixpanel.engine], policy: .storeBuildsOnly, launch: storeBuild)
        hub.setUserID("user-7f3a")
        hub.setCrashKey("pro", forKey: "plan")
        hub.addBreadcrumb("opened the editor")
        hub.setUserID(nil)

        for spy in [firebase, mixpanel] {
            #expect(spy.client.userIDs == ["user-7f3a", nil])
            #expect(spy.client.crashKeys == ["plan": "pro"])
            #expect(spy.client.breadcrumbs == ["opened the editor"])
        }
    }

    /// The app restores its session before `start`, or while the user had collection off: the id
    /// still reaches the engines when they begin.
    @Test func anIdGivenBeforeTheEnginesRunReachesThemWhenTheyStart() {
        let early = EngineSpy()
        let hub = AnalyticsHub()

        hub.setUserID("user-7f3a")
        hub.start(engines: [early.engine], policy: .storeBuildsOnly, launch: storeBuild)

        #expect(early.client.userIDs == ["user-7f3a"])

        let switched = EngineSpy()
        let other = AnalyticsHub()

        other.start(engines: [switched.engine], policy: .storeBuildsOnly, launch: storeBuild)
        other.setCollectionEnabled(false)
        other.setUserID("user-9b21")
        other.setCrashKey("free", forKey: "plan")
        other.setCollectionEnabled(true)

        #expect(switched.client.userIDs == ["user-9b21"])
        #expect(switched.client.crashKeys.isEmpty, "nothing else is replayed")
    }

    @Test func environmentDefaultsToTheSharedClient() {
        #expect(EnvironmentValues().analytics as AnyObject === Analytics.shared as AnyObject)
    }
}

@MainActor
private final class EngineSpy {
    let client = RecordingAnalyticsClient()
    private(set) var starts = 0
    private(set) var stayOffs = 0
    private(set) var switches: [Bool] = []
    private let canStart: Bool

    init(starts canStart: Bool = true) {
        self.canStart = canStart
    }

    var engine: AnalyticsEngine {
        AnalyticsEngine(name: "spy") { [self] in
            starts += 1
            return canStart ? client : nil
        } stayOff: { [self] in
            stayOffs += 1
        } setCollectionEnabled: { [self] enabled in
            switches.append(enabled)
        }
    }
}

private struct SampleError: Error {}
