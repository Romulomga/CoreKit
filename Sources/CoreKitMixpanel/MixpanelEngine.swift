@_exported import CoreKitAnalytics
internal import Mixpanel
import StoreKit

extension AnalyticsEngine {
    /// Mixpanel with the app's project token, with its automatic events (first open, app updated,
    /// sessions) on, the counterpart of Firebase's own. `nil` or empty leaves the engine off, so a
    /// build without the secrets file still runs. Twin of CoreKit-Android's `mixpanel` module.
    ///
    /// `flushInterval` is how often, in seconds, queued events go out (Mixpanel's default is 60). A
    /// staging build traced with `--analytics-debug` passes something short, so QA sees an event
    /// right after the tap instead of a minute later.
    ///
    /// `screenEvent` is how a screen the navigation reports reaches Mixpanel: by default the names
    /// Firebase uses (`screen_view` with `screen_name`); an app whose reports already read another
    /// shape (a legacy `page_viewed` with `name_of_the_page_viewed`) passes that one.
    public static func mixpanel(
        token: String?,
        flushInterval: Double = 60,
        screenEvent: MixpanelScreenEvent = .standard
    ) -> AnalyticsEngine {
        AnalyticsEngine(name: "Mixpanel") {
            guard let token, !token.isEmpty else {
                analyticsLog.notice("Mixpanel off: no token")
                return nil
            }

            let mixpanel = Mixpanel.initialize(token: token, trackAutomaticEvents: true, flushInterval: flushInterval)

            // The opt-out persists on the device: a user who switched collection off and back on
            // in an earlier launch would otherwise stay silent.
            if mixpanel.hasOptedOutTracking() {
                mixpanel.optInTracking()
            }

            return MixpanelAnalyticsClient(screenEvent: screenEvent)
        } setCollectionEnabled: { enabled in
            let mixpanel = Mixpanel.mainInstance()

            if enabled {
                mixpanel.optInTracking()
            } else {
                mixpanel.optOutTracking()
            }
        }
    }
}

/// The only place that talks to the Mixpanel SDK. It reaches the main instance on each call instead
/// of keeping it: `MixpanelInstance` isn't `Sendable`, and the SDK guards its own state.
struct MixpanelAnalyticsClient: AnalyticsClient {
    let screenEvent: MixpanelScreenEvent

    func log(_ name: String, parameters: [String: AnalyticsValue]) {
        Mixpanel.mainInstance().track(event: name, properties: parameters.mapValues(Self.property))
    }

    /// Mixpanel has no screen event of its own: the app's `screenEvent` says which one.
    func screen(_ name: String) {
        Mixpanel.mainInstance().track(event: screenEvent.event, properties: screenEvent.properties(for: name))
    }

    /// As a super property, which rides on every later event: Mixpanel's counterpart of a GA4 user
    /// property for segmenting. The people profile would need an identified user.
    func setUserProperty(_ value: String?, forName name: String) {
        let mixpanel = Mixpanel.mainInstance()

        if let value {
            mixpanel.registerSuperProperties([name: value])
        } else {
            mixpanel.unregisterSuperProperty(name)
        }
    }

    /// Super properties with their types: a boolean stays a boolean.
    func setUserProperties(_ properties: [String: AnalyticsValue]) {
        Mixpanel.mainInstance().registerSuperProperties(properties.mapValues(Self.property))
    }

    /// Mixpanel's people profile (`people.set`), on the identified user.
    func setUserProfile(_ properties: [String: AnalyticsValue]) {
        Mixpanel.mainInstance().people.set(properties: properties.mapValues(Self.property))
    }

    /// Mixpanel isn't a crash reporter; errors go to the app's (Crashlytics, Sentry).
    func recordError(_ error: any Error, context: String?) {}

    /// `identify` merges the anonymous events of this device into the user; `reset` on sign-out starts
    /// a new anonymous id, so the next person on the device isn't counted as the last one.
    func setUserID(_ id: String?) {
        let mixpanel = Mixpanel.mainInstance()

        if let id {
            mixpanel.identify(distinctId: id)
        } else {
            mixpanel.reset()
        }
    }

    /// Mixpanel's revenue lives on the people profile, which needs an identified user; no app sells
    /// through Mixpanel yet.
    func logTransaction(_ transaction: StoreKit.Transaction) {}

    func logPurchase(_ purchase: PurchaseRevenue) {}

    /// Types survive: a property that changes type splits Mixpanel's reports (a numeric filter no
    /// longer sees `"3"`).
    static func property(_ value: AnalyticsValue) -> any MixpanelType {
        switch value {
        case .string(let text): text
        case .int(let number): number
        case .double(let number): number
        case .bool(let flag): flag
        }
    }
}
