@_exported import CoreKitAnalytics
internal import Mixpanel
import StoreKit

extension AnalyticsEngine {
    /// Mixpanel with the app's project token, with its automatic events (first open, app updated,
    /// sessions) on, the counterpart of Firebase's own. `nil` or empty leaves the engine off, so a
    /// build without the secrets file still runs. iOS only: no Android app uses Mixpanel.
    public static func mixpanel(token: String?) -> AnalyticsEngine {
        AnalyticsEngine(name: "Mixpanel") {
            guard let token, !token.isEmpty else {
                analyticsLog.notice("Mixpanel off: no token")
                return nil
            }

            Mixpanel.initialize(token: token, trackAutomaticEvents: true)

            return MixpanelAnalyticsClient()
        }
    }
}

/// The only place that talks to the Mixpanel SDK. It reaches the main instance on each call instead
/// of keeping it: `MixpanelInstance` isn't `Sendable`, and the SDK guards its own state.
struct MixpanelAnalyticsClient: AnalyticsClient {
    func log(_ name: String, parameters: [String: AnalyticsValue]) {
        Mixpanel.mainInstance().track(event: name, properties: parameters.mapValues(Self.property))
    }

    /// Mixpanel has no screen event of its own; this one uses the names Firebase uses, so a screen
    /// reads the same in both.
    func screen(_ name: String) {
        Mixpanel.mainInstance().track(event: "screen_view", properties: ["screen_name": name])
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

    /// Mixpanel isn't a crash reporter; errors go to the app's (Crashlytics, Sentry).
    func recordError(_ error: any Error, context: String?) {}

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
