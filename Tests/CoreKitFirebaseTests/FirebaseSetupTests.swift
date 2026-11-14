@testable import CoreKitAnalytics
@testable import CoreKitFirebase
import FirebaseCore
import Foundation
import Testing

/// Setting Firebase up without setting it up: the closure stands in for `FirebaseApp.configure`, which raises without
/// a plist and raises again when the app already called it.
struct FirebaseSetupTests {
    private static let appID = "1:1234567890:ios:0123456789abcdef"

    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Configure

    @Test func aPlistSetsFirebaseUpWithItsOptions() throws {
        let plist = try writePlist(to: directory.appending(path: "Homolog.plist"))
        var appIDs: [String] = []

        let configured = FirebaseSetup.configure(.file(plist), isConfigured: false, bundle: try emptyBundle()) {
            appIDs.append($0.googleAppID)
        }

        #expect(configured)
        #expect(appIDs == [Self.appID])
    }

    /// The plist isn't committed in every app: a fresh checkout's release build would crash instead of not reporting.
    @Test func withoutAPlistFirebaseIsNotSetUp() throws {
        var calls = 0
        let missing = directory.appending(path: "GoogleService-Info.plist")
        let bundle = try emptyBundle()

        let fromFile = FirebaseSetup.configure(.file(missing), isConfigured: false, bundle: bundle) { _ in calls += 1 }
        let fromBundle = FirebaseSetup.configure(.bundled, isConfigured: false, bundle: bundle) { _ in calls += 1 }

        #expect(!fromFile)
        #expect(!fromBundle)
        #expect(calls == 0)
    }

    /// An app that set Firebase up itself (for Remote Config) would raise on a second `configure`; its plist is not
    /// even read.
    @Test func anAppThatAlreadySetFirebaseUpIsNotSetUpAgain() throws {
        var calls = 0
        let missing = directory.appending(path: "GoogleService-Info.plist")
        let configured = FirebaseSetup.configure(.file(missing), isConfigured: true, bundle: try emptyBundle()) { _ in
            calls += 1
        }

        #expect(configured)
        #expect(calls == 0)
    }

    // MARK: - Which plist

    @Test func bundledReadsTheBundlesPlistAndFileReadsTheOneGiven() throws {
        let bundleURL = directory.appending(path: "App.bundle", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let bundled = try writePlist(to: bundleURL.appending(path: "GoogleService-Info.plist"))
        let homolog = directory.appending(path: "Homolog.plist")
        let bundle = try #require(Bundle(url: bundleURL))

        #expect(FirebasePlist.bundled.url(in: bundle)?.resolvingSymlinksInPath() == bundled.resolvingSymlinksInPath())
        #expect(FirebasePlist.bundled.url(in: try emptyBundle()) == nil)
        #expect(FirebasePlist.file(homolog).url(in: bundle) == homolog)
    }

    // MARK: - Engine

    /// The real engine, in a process with no plist and Firebase never set up: a store build that runs and sends
    /// nothing.
    @MainActor
    @Test func aStoreBuildWithoutAPlistRunsWithoutFirebase() {
        let hub = AnalyticsHub()

        hub.start(engines: [.firebase()], policy: .storeBuildsOnly, launch: LaunchContext(isDebugBuild: false, arguments: []))

        #expect(!hub.isCollecting)
    }

    // MARK: - Support

    private func writePlist(to url: URL) throws -> URL {
        let options: [String: Any] = [
            "GOOGLE_APP_ID": Self.appID,
            "GCM_SENDER_ID": "1234567890",
            "API_KEY": "AIzaFakeKeyForTests",
            "PROJECT_ID": "corekit-tests",
            "BUNDLE_ID": "io.github.romulomga.corekit.tests",
        ]

        try PropertyListSerialization.data(fromPropertyList: options, format: .xml, options: 0).write(to: url)

        return url
    }

    private func emptyBundle() throws -> Bundle {
        let url = directory.appending(path: "Empty.bundle", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        return try #require(Bundle(url: url))
    }
}
