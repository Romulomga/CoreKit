import CoreKitStore
import Observation

/// The right to Pro the test picks. Start it at `.unknown` to test a screen before the right is known.
@MainActor
@Observable
public final class FakeEntitlement: Entitlement {
    public var state: EntitlementState

    public init(_ state: EntitlementState = .free) {
        self.state = state
    }
}

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
