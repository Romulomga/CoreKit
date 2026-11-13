import Foundation

/// Whether the App Store review prompt may be requested now: once per app version and, when the app sets
/// `minDaysBetween`, at least that many days after the last request. Twin of CoreKit-Android's `ReviewGate`.
///
/// The system shows the prompt at most three times a year and drops the rest without telling the app, so
/// asking on every good moment only spends those chances early, wherever they happen to land. WHEN a moment is
/// good is the app's product rule and stays in the app; the gate only says whether this one may still ask.
///
/// The marks live in the app's `UserDefaults`, under the keys it already used, so moving to the gate never
/// asks again someone the app already asked.
public struct ReviewGate {
    private let defaults: UserDefaults
    private let versionKey: String
    private let dateKey: String
    private let minDaysBetween: Int
    private let currentVersion: String
    private let now: () -> Date

    /// - Parameters:
    ///   - versionKey: where the version of the last request is kept (a string).
    ///   - dateKey: where the date of the last request is kept. Read as a `Date` or as seconds since 1970,
    ///     the two shapes the apps stored before the gate; written as a `Date`.
    ///   - minDaysBetween: the least number of days between two requests, even across versions. `0` leaves
    ///     only the once-per-version rule.
    ///   - currentVersion: the app's marketing version (`CFBundleShortVersionString`), not the build: a new
    ///     build of the same version must not ask again.
    public init(
        defaults: UserDefaults = .standard,
        versionKey: String,
        dateKey: String,
        minDaysBetween: Int = 0,
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.versionKey = versionKey
        self.dateKey = dateKey
        self.minDaysBetween = minDaysBetween
        self.currentVersion = currentVersion
        self.now = now
    }

    /// `true` when this version hasn't asked yet and the last request, if any, is old enough.
    public var isEligible: Bool {
        Self.isEligible(
            currentVersion: currentVersion,
            lastPromptVersion: defaults.string(forKey: versionKey),
            lastPromptAt: lastPromptAt,
            now: now(),
            minDaysBetween: minDaysBetween
        )
    }

    /// Records that the system was asked, in this version, now.
    ///
    /// Call it right after `requestReview()`, not before and not later. Before, a request that never happened
    /// (the app left during the wait) would spend the version's only chance. Later, nothing: the system never
    /// says whether the prompt showed, so a request that was made must never be retried.
    public func markRequested() {
        defaults.set(currentVersion, forKey: versionKey)
        defaults.set(now(), forKey: dateKey)
    }

    // MARK: - Rule

    /// The rule alone, the same as Android's `ReviewGate.isEligible`: whole days of 24 hours.
    static func isEligible(
        currentVersion: String,
        lastPromptVersion: String?,
        lastPromptAt: Date?,
        now: Date,
        minDaysBetween: Int
    ) -> Bool {
        if lastPromptVersion == currentVersion { return false }

        guard let lastPromptAt, minDaysBetween > 0 else { return true }

        return now.timeIntervalSince(lastPromptAt) >= TimeInterval(minDaysBetween) * 24 * 60 * 60
    }

    private var lastPromptAt: Date? {
        switch defaults.object(forKey: dateKey) {
        case let date as Date:
            date
        case let seconds as Double:
            Date(timeIntervalSince1970: seconds)
        default:
            nil
        }
    }
}
