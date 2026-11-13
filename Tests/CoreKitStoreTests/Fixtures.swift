import CoreKitStore
import Foundation

enum Plans {
    static let monthly = ProPlan(productID: "pro.monthly", type: .subscription, analyticsName: "monthly")

    static let yearly = ProPlan(productID: "pro.yearly", type: .subscription, analyticsName: "yearly")

    static let lifetime = ProPlan(productID: "pro.lifetime", type: .lifetime, analyticsName: "lifetime")

    static let all = [monthly, yearly, lifetime]
}

let day: TimeInterval = 86_400

func transaction(
    _ plan: ProPlan,
    id: UInt64 = 1,
    expires: Date? = nil,
    revoked: Bool = false,
    upgraded: Bool = false,
    purchased: Date = .now
) -> StoreTransaction {
    StoreTransaction(
        id: id,
        productID: plan.productID,
        purchaseDate: purchased,
        expirationDate: expires ?? (plan.type == .subscription ? Date.now.addingTimeInterval(30 * day) : nil),
        revocationDate: revoked ? .now : nil,
        isUpgraded: upgraded
    )
}

func product(_ plan: ProPlan, price: Decimal) -> ProProduct {
    ProProduct(plan: plan, displayPrice: "R$ \(price)", price: price, currencyCode: "BRL")
}

/// Holds whoever waits on it until the test opens it.
@MainActor
final class Gate {
    private var isOpen = false

    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }

        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// A value a stored closure can change and the test can read.
@MainActor
final class Box<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

struct StoreDown: Error {}

/// Polls in real time, for what a timer moves forward. Gives up after about five seconds; the caller's expectation
/// then fails.
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<500 {
        if condition() { return }

        try? await Task.sleep(for: .milliseconds(10))
    }
}
