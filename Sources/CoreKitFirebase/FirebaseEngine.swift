@_exported import CoreKitAnalytics
internal import FirebaseAnalytics
internal import FirebaseCore
internal import FirebaseCrashlytics
import Foundation

/// Which `GoogleService-Info.plist` sets Firebase up.
public enum FirebasePlist: Sendable {
    /// `GoogleService-Info.plist` in the main bundle.
    case bundled

    /// A plist the app picks at runtime, such as one per environment (homolog, prod).
    case file(URL)
}

extension AnalyticsEngine {
    /// Firebase Analytics + Crashlytics, without the advertising id: the module links
    /// `FirebaseAnalytics` and never `FirebaseAnalyticsIdentitySupport`, so there is no ATT prompt.
    /// The twin of CoreKit-Android's `FirebaseMonitoring.start`.
    ///
    /// Firebase is set up only when the policy collects. If the app already set it up (for Remote
    /// Config), it is not set up again, which would raise; such an app must do it before
    /// `Analytics.start`, so a build that doesn't collect can still switch collection off.
    ///
    /// What stays in the app's `project.yml`: `-ObjC` in `OTHER_LDFLAGS`, the Crashlytics dSYM
    /// upload run script (with `ENABLE_USER_SCRIPT_SANDBOXING: NO`), and
    /// `FirebaseAutomaticScreenReportingEnabled: false` in the Info.plist, since `trackScreen` logs
    /// the screens.
    public static func firebase(options plist: FirebasePlist = .bundled) -> AnalyticsEngine {
        AnalyticsEngine(name: "Firebase") {
            guard FirebaseSetup.configure(plist) else { return nil }

            // Both settings persist on the device: a debug build that switched them off would
            // otherwise leave the store build installed over it silent.
            FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(true)
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)

            return FirebaseAnalyticsClient()
        } stayOff: {
            // Never set up means nothing runs; only an app that set Firebase up itself has
            // something to switch off.
            guard FirebaseApp.app() != nil else { return }

            FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(false)
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        } setCollectionEnabled: { enabled in
            FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(enabled)
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
        }
    }
}

enum FirebaseSetup {
    /// `false` when there is no plist to read. The plist isn't committed in every app, and
    /// `FirebaseApp.configure()` without one raises at launch, so a fresh checkout's release build
    /// would crash instead of just not reporting.
    @MainActor
    static func configure(_ plist: FirebasePlist) -> Bool {
        configure(plist, isConfigured: FirebaseApp.app() != nil, bundle: .main) { FirebaseApp.configure(options: $0) }
    }

    /// The rule apart from Firebase's singleton, so a test runs it without setting Firebase up.
    static func configure(
        _ plist: FirebasePlist,
        isConfigured: Bool,
        bundle: Bundle,
        configure: (FirebaseOptions) -> Void
    ) -> Bool {
        guard !isConfigured else { return true }

        guard let url = plist.url(in: bundle), let options = FirebaseOptions(contentsOfFile: url.path) else {
            analyticsLog.notice("Firebase off: no GoogleService-Info.plist to read")
            return false
        }

        configure(options)
        return true
    }
}

extension FirebasePlist {
    /// `.bundled` looks in `bundle`: the main bundle at launch.
    func url(in bundle: Bundle) -> URL? {
        switch self {
        case .bundled: bundle.url(forResource: "GoogleService-Info", withExtension: "plist")
        case .file(let url): url
        }
    }
}
