import Foundation

/// The rules that turn transactions into a right, apart from StoreKit and from the store's state so each one is
/// tested on its own.
struct EntitlementResolver: Sendable {
    let plans: [ProPlan]

    var productIDs: [String] { plans.map(\.productID) }

    func plan(for productID: String) -> ProPlan? {
        plans.first { $0.productID == productID }
    }

    /// One of the app's plans, not refunded, not superseded by an upgrade, and (a subscription) not run out.
    func entitles(_ transaction: StoreTransaction, at now: Date) -> Bool {
        guard let plan = plan(for: transaction.productID), !transaction.isRevoked, !transaction.isUpgraded else {
            return false
        }

        switch plan.type {
        case .lifetime: return true
        case .subscription: return (transaction.expirationDate ?? .distantPast) > now
        }
    }

    /// Lifetime beats any subscription; among subscriptions, the furthest expiry.
    func resolve(_ transactions: [StoreTransaction], at now: Date) -> EntitlementKind {
        let entitling = transactions.filter { entitles($0, at: now) }

        if entitling.contains(where: { plan(for: $0.productID)?.type == .lifetime }) {
            return .lifetime
        }

        if let expires = entitling.compactMap(\.expirationDate).max() {
            return .subscription(expires: expires)
        }

        return .none
    }

    /// Whether `history` proves the remembered right was refunded. Only that ends it before it runs out: silence from
    /// StoreKit doesn't, so the worst case is a refunded subscriber keeping Pro until the period they paid for ends.
    func isRefunded(_ confirmed: EntitlementKind, by history: [StoreTransaction]) -> Bool {
        let revoked = history.filter(\.isRevoked)

        switch confirmed {
        case .none:
            return false

        case .lifetime:
            return revoked.contains { plan(for: $0.productID)?.type == .lifetime }

        // A refund of an older period (one that ended before the remembered one) says nothing about it.
        case .subscription(let expires):
            return revoked.contains {
                plan(for: $0.productID)?.type == .subscription && ($0.expirationDate ?? .distantPast) >= expires
            }
        }
    }

    /// The transaction StoreKit just delivered is newer than any list read before it, so it replaces the copy with its
    /// id: a refund counts even while `currentEntitlements` still lists the purchase, and a purchase counts even while
    /// `currentEntitlements` lags behind it.
    func merging(_ evidence: StoreTransaction?, into transactions: [StoreTransaction]) -> [StoreTransaction] {
        guard let evidence else { return transactions }

        return transactions.filter { $0.id != evidence.id } + [evidence]
    }

    /// A new purchase is dated by the App Store when it happens; an older date is the existing transaction StoreKit
    /// hands back for a product the account already has. The hour absorbs a device clock running ahead.
    static func isAlreadyOwned(purchaseDate: Date, purchaseStartedAt: Date) -> Bool {
        purchaseDate < purchaseStartedAt.addingTimeInterval(-3600)
    }
}
