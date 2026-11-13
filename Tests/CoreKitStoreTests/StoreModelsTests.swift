@testable import CoreKitStore
import Foundation
import StoreKit
import Testing

struct StoreModelsTests {
    @Test func planNameDefaultsToTheProductID() {
        #expect(ProPlan(productID: "pro.yearly", type: .subscription).analyticsName == "pro.yearly")
        #expect(Plans.yearly.analyticsName == "yearly")
    }

    @Test func priceCentsRoundsHalfUpWithoutFloatingPoint() throws {
        #expect(product(Plans.yearly, price: try #require(Decimal(string: "49.90"))).priceCents == 4990)
        #expect(product(Plans.yearly, price: try #require(Decimal(string: "9.995"))).priceCents == 1000)
        #expect(product(Plans.yearly, price: try #require(Decimal(string: "0.29"))).priceCents == 29)
    }

    @Test func freeTrialOnlyWhenTheAccountCanStillGetIt() {
        let trial = FreeTrial(value: 1, unit: .week)
        let eligible = ProProduct(plan: Plans.yearly, displayPrice: "R$ 49,90", price: 49.9, currencyCode: "BRL", freeTrial: trial)

        #expect(eligible.hasEligibleFreeTrial)
        #expect(eligible.freeTrial?.days == 7)
        #expect(!product(Plans.yearly, price: 49.9).hasEligibleFreeTrial)
    }

    /// "Couldn't reach the App Store" and "the App Store said no" are different problems to whoever reads the report.
    @Test func aNetworkErrorIsAnUnreachableStoreNotAFailedRequest() {
        #expect(StoreKitGateway.isUnreachable(StoreKitError.networkError(URLError(.notConnectedToInternet))))
        #expect(StoreKitGateway.isUnreachable(URLError(.timedOut)))
        #expect(!StoreKitGateway.isUnreachable(StoreKitError.notAvailableInStorefront))
        #expect(!StoreKitGateway.isUnreachable(StoreDown()))
    }

    @Test func firstChargeUsesTheCalendarNotThirtyDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))

        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 10)))
        let month = FreeTrial(value: 1, unit: .month)

        #expect(month.days == 30)
        #expect(month.firstChargeDate(startingAt: start, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 2, day: 28, hour: 10)))
        #expect(FreeTrial(value: 3, unit: .day).firstChargeDate(startingAt: start, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 2, day: 3, hour: 10)))
    }
}
