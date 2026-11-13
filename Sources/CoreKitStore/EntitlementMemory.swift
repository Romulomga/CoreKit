import Foundation

/// Where the last right StoreKit confirmed is kept, so a launch without an answer opens as Pro for someone who paid.
///
/// The app owns the storage and its keys: implement this over them, or use `UserDefaultsEntitlementMemory`.
@MainActor
public protocol EntitlementMemory {
    /// `nil` when StoreKit never answered on this device; `.none` is "it answered, and there is no purchase".
    func load() -> EntitlementKind?

    func save(_ kind: EntitlementKind)
}

/// The confirmed right as JSON under the app's key in `UserDefaults`.
///
/// The format is `EntitlementKind`'s coding, so a key an app already filled with that shape keeps working.
public struct UserDefaultsEntitlementMemory: EntitlementMemory {
    private let key: String

    private let defaults: UserDefaults

    public init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    public func load() -> EntitlementKind? {
        guard let data = defaults.data(forKey: key) else { return nil }

        return try? JSONDecoder().decode(EntitlementKind.self, from: data)
    }

    public func save(_ kind: EntitlementKind) {
        guard let data = try? JSONEncoder().encode(kind) else { return }

        defaults.set(data, forKey: key)
    }
}
