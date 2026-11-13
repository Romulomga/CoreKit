import Foundation
import Observation

/// The right to Pro, with a state for "not known yet".
///
/// A `Bool` that starts `false` shows a paying user the free experience at launch (the teaser, the free limit, a
/// counted paywall impression) until the remembered right is read and StoreKit answers. Gates and paywall impressions
/// wait for `isResolved`.
public enum EntitlementState: Sendable, Hashable {
    /// Neither the remembered right nor StoreKit has answered yet: draw no Pro gate and count no paywall impression.
    case unknown

    case free

    case pro

    public var isPro: Bool { self == .pro }

    public var isResolved: Bool { self != .unknown }
}

/// The one door to "is this user Pro?". Screens and models depend on this, never on the store, so a test hands them
/// a `FakeEntitlement` instead of StoreKit.
@MainActor
public protocol Entitlement: AnyObject, Observable {
    var state: EntitlementState { get }
}

extension Entitlement {
    /// `true` only for a confirmed Pro: `unknown` counts as `false`.
    public var isPro: Bool { state.isPro }
}

/// Where the right comes from.
///
/// The coding is the one the apps already persisted before this package (`{"lifetime":{}}`,
/// `{"subscription":{"expires":…}}`), so an app that moves to it reads the confirmation its users already have.
/// Renaming a case or its label breaks that, and every subscriber would open as free once.
public enum EntitlementKind: Sendable, Hashable, Codable {
    case none

    /// Carries the expiry so a remembered subscription runs out on its own, even when StoreKit can't be reached.
    case subscription(expires: Date)

    case lifetime

    public func isActive(at date: Date) -> Bool {
        switch self {
        case .none: false
        case .subscription(let expires): expires > date
        case .lifetime: true
        }
    }

    /// Stable name for an analytics user property, the same on CoreKit-Android.
    public var analyticsName: String {
        switch self {
        case .none: "none"
        case .subscription: "subscription"
        case .lifetime: "lifetime"
        }
    }
}
