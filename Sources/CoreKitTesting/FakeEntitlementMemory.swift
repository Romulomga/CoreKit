import CoreKitStore

/// Keeps the confirmed right in memory. `saved` starts as what was "remembered" before the launch.
@MainActor
public final class FakeEntitlementMemory: EntitlementMemory {
    public var saved: EntitlementKind?

    public private(set) var saves = 0

    public init(_ saved: EntitlementKind? = nil) {
        self.saved = saved
    }

    public func load() -> EntitlementKind? {
        saved
    }

    public func save(_ kind: EntitlementKind) {
        saved = kind
        saves += 1
    }
}
