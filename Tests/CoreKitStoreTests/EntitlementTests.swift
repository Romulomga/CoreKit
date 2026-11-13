import CoreKitStore
import Foundation
import Testing

struct EntitlementTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func unknownIsNeitherProNorResolved() {
        #expect(!EntitlementState.unknown.isPro)
        #expect(!EntitlementState.unknown.isResolved)
        #expect(!EntitlementState.free.isPro)
        #expect(EntitlementState.free.isResolved)
        #expect(EntitlementState.pro.isPro)
    }

    @Test func activityHonoursTheExpiry() {
        #expect(EntitlementKind.subscription(expires: now.addingTimeInterval(60)).isActive(at: now))
        #expect(!EntitlementKind.subscription(expires: now).isActive(at: now))
        #expect(EntitlementKind.lifetime.isActive(at: .distantFuture))
        #expect(!EntitlementKind.none.isActive(at: now))
    }

    /// The exact bytes apps stored before the package: a different coding would open every subscriber as unknown.
    @Test func codingMatchesTheConfirmationAppsAlreadyStored() throws {
        let decoder = JSONDecoder()

        let subscription = try decoder.decode(
            EntitlementKind.self,
            from: Data(#"{"subscription":{"expires":800000000}}"#.utf8)
        )

        #expect(subscription == .subscription(expires: now))
        #expect(try decoder.decode(EntitlementKind.self, from: Data(#"{"lifetime":{}}"#.utf8)) == .lifetime)
        #expect(try decoder.decode(EntitlementKind.self, from: Data(#"{"none":{}}"#.utf8)) == EntitlementKind.none)
        #expect(String(decoding: try JSONEncoder().encode(EntitlementKind.lifetime), as: UTF8.self) == #"{"lifetime":{}}"#)
    }

    @MainActor
    @Test func userDefaultsMemoryTellsNeverAnsweredFromNoPurchase() throws {
        let defaults = try #require(UserDefaults(suiteName: "EntitlementTests.\(UUID())"))
        let memory = UserDefaultsEntitlementMemory(key: "confirmed", defaults: defaults)

        #expect(memory.load() == nil)

        memory.save(.none)

        #expect(memory.load() == EntitlementKind.none)

        memory.save(.subscription(expires: now))

        #expect(memory.load() == .subscription(expires: now))

        defaults.set(Data("garbage".utf8), forKey: "confirmed")

        #expect(memory.load() == nil)
    }
}
