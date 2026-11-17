import Foundation
import StoreKit

// MARK: - Plans

public enum ProPlanType: Sendable, Hashable {
    case subscription

    /// A non-consumable bought once.
    case lifetime
}

/// One of the app's Pro plans: its product id in App Store Connect and whether it renews. The ids come from the app;
/// a transaction for any other product never grants Pro.
public struct ProPlan: Sendable, Hashable {
    public let productID: String

    public let type: ProPlanType

    /// Stable plan name for analytics (`monthly`, `yearly`, `lifetime`); the product id when not given.
    public let analyticsName: String

    public init(productID: String, type: ProPlanType, analyticsName: String? = nil) {
        self.productID = productID
        self.type = type
        self.analyticsName = analyticsName ?? productID
    }
}

// MARK: - Products

/// The order of the plans on sale.
public enum ProductOrder: Sendable, Hashable {
    /// Cheapest first.
    case byPrice

    /// As the app listed its plans.
    case asPlanned
}

/// The catalog load, so the paywall shows a spinner, an error with "try again", or the plans.
public enum ProductsState: Sendable, Hashable {
    case loading

    case loaded

    case failed
}

/// A free introductory period, read from the real StoreKit offer: its length is edited in App Store Connect without a
/// release, so no copy may hard-code it.
public struct FreeTrial: Sendable, Hashable {
    public enum Unit: Sendable, Hashable {
        case day

        case week

        case month

        case year
    }

    public let value: Int

    public let unit: Unit

    public init(value: Int, unit: Unit) {
        self.value = value
        self.unit = unit
    }

    /// Days for the "N days free" copy. A month counts as 30 and a year as 365: only the copy, never a date.
    public var days: Int {
        switch unit {
        case .day: value
        case .week: value * 7
        case .month: value * 30
        case .year: value * 365
        }
    }

    /// The real first charge if the trial starts at `start`: calendar math, so a month is not 30 days.
    public func firstChargeDate(startingAt start: Date, calendar: Calendar = .current) -> Date? {
        let components = switch unit {
        case .day: DateComponents(day: value)
        case .week: DateComponents(day: value * 7)
        case .month: DateComponents(month: value)
        case .year: DateComponents(year: value)
        }

        return calendar.date(byAdding: components, to: start)
    }

    init?(_ period: Product.SubscriptionPeriod) {
        let unit: Unit

        switch period.unit {
        case .day: unit = .day
        case .week: unit = .week
        case .month: unit = .month
        case .year: unit = .year
        @unknown default: return nil
        }

        self.init(value: period.value, unit: unit)
    }
}

/// A plan on sale, with the App Store's price.
public struct ProProduct: Sendable, Identifiable, Equatable {
    public let plan: ProPlan

    /// Formatted in the account's storefront currency.
    public let displayPrice: String

    public let price: Decimal

    /// ISO 4217 code (`BRL`, `USD`) of `price`.
    public let currencyCode: String

    /// The free trial THIS account can still get; `nil` without one or once the account used it. StoreKit grants an
    /// introductory offer once per account, so announcing a trial from the offer alone promises "free" to someone
    /// StoreKit then charges on the spot.
    public let freeTrial: FreeTrial?

    /// The StoreKit product, for what the paywall reads beyond these fields. `nil` only for a product built in a test.
    public let storeProduct: Product?

    public init(
        plan: ProPlan,
        displayPrice: String,
        price: Decimal,
        currencyCode: String,
        freeTrial: FreeTrial? = nil,
        storeProduct: Product? = nil
    ) {
        self.plan = plan
        self.displayPrice = displayPrice
        self.price = price
        self.currencyCode = currencyCode
        self.freeTrial = freeTrial
        self.storeProduct = storeProduct
    }

    init(plan: ProPlan, product: Product, freeTrial: FreeTrial?) {
        self.init(
            plan: plan,
            displayPrice: product.displayPrice,
            price: product.price,
            currencyCode: product.priceFormatStyle.currencyCode,
            freeTrial: freeTrial,
            storeProduct: product
        )
    }

    public var id: String { plan.productID }

    /// The only gate the UI uses to announce "N days free".
    public var hasEligibleFreeTrial: Bool { freeTrial != nil }

    /// `price` in integer cents, rounded half up, for analytics parameters.
    public var priceCents: Int { Self.cents(price) }

    /// Integer cents, rounded half up: the one rounding every price in analytics goes through.
    static func cents(_ amount: Decimal) -> Int {
        var cents = amount * 100
        var rounded = Decimal()

        NSDecimalRound(&rounded, &cents, 0, .plain)

        return NSDecimalNumber(decimal: rounded).intValue
    }
}

// MARK: - Transactions

/// A verified transaction, with only what the rules read, so they run in a test without StoreKit.
public struct StoreTransaction: Sendable, Equatable {
    public let id: UInt64

    public let productID: String

    public let purchaseDate: Date

    /// When a subscription period ends; `nil` for a lifetime purchase.
    public let expirationDate: Date?

    /// Set by a refund or a revocation (Family Sharing, App Store support).
    public let revocationDate: Date?

    /// Superseded by a higher tier in the same group: the new tier carries the access.
    public let isUpgraded: Bool

    /// When the billing grace period ends, for a subscription whose renewal failed and that Apple keeps entitled while
    /// it retries the charge (the App Store Connect "Billing Grace Period" setting). `expirationDate` is already past
    /// then, and StoreKit still lists the transaction in `currentEntitlements`.
    public let gracePeriodExpirationDate: Date?

    /// Until when this transaction entitles: the grace period's end when there is one, else `expirationDate`.
    public var entitledUntil: Date? {
        [expirationDate, gracePeriodExpirationDate].compactMap { $0 }.max()
    }

    /// What was actually charged, which may differ from the listed price (an introductory or promotional offer, another
    /// storefront). `nil` when StoreKit doesn't say.
    public let price: Decimal?

    /// `price` in integer cents, rounded like `ProProduct.priceCents`: 0 for a free trial, `nil` when StoreKit didn't
    /// say. The revenue of a purchase event, the price charged rather than the listed one.
    public var priceCents: Int? { price.map(ProProduct.cents) }

    public let currencyCode: String?

    /// The StoreKit transaction, for what the app reads beyond these fields. `nil` only in a test.
    public let transaction: Transaction?

    public init(
        id: UInt64,
        productID: String,
        purchaseDate: Date = .now,
        expirationDate: Date? = nil,
        revocationDate: Date? = nil,
        isUpgraded: Bool = false,
        gracePeriodExpirationDate: Date? = nil,
        price: Decimal? = nil,
        currencyCode: String? = nil,
        transaction: Transaction? = nil
    ) {
        self.id = id
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.isUpgraded = isUpgraded
        self.gracePeriodExpirationDate = gracePeriodExpirationDate
        self.price = price
        self.currencyCode = currencyCode
        self.transaction = transaction
    }

    public init(_ transaction: Transaction, gracePeriodExpirationDate: Date? = nil) {
        self.init(
            id: transaction.id,
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded,
            gracePeriodExpirationDate: gracePeriodExpirationDate,
            price: transaction.price,
            currencyCode: transaction.currency?.identifier,
            transaction: transaction
        )
    }

    public var isRevoked: Bool { revocationDate != nil }
}

// MARK: - Purchase

public enum PurchaseResult: Sendable, Hashable {
    case purchased

    /// Waiting for approval (Ask to Buy, a payment to clear): no right yet. If it goes through, it arrives through
    /// `Transaction.updates`.
    case pending

    case cancelled

    /// The account already had it: StoreKit hands back the existing transaction and charges nothing. Counting it as a
    /// sale inflates revenue reads.
    case alreadyOwned

    case failed
}

/// How a purchase attempt ended. Purchase analytics belong to the app, on top of this.
public struct PurchaseOutcome: Sendable {
    public let result: PurchaseResult

    /// Only for `.purchased` and `.alreadyOwned`.
    public let transaction: StoreTransaction?

    /// Only for `.failed`: StoreKit's error, or the verification failure of the transaction it returned.
    public let error: (any Error)?

    public init(result: PurchaseResult, transaction: StoreTransaction? = nil, error: (any Error)? = nil) {
        self.result = result
        self.transaction = transaction
        self.error = error
    }
}
