@testable import CoreKitNavigation
import Testing

@MainActor
@Suite struct ReloadNotifierTests {

    @Test func everyNotifyIsANewSignalEvenForTheSameDestination() throws {
        let notifier = ReloadNotifier<TestDestination>()
        #expect(notifier.signal == nil)

        notifier.notify(.root)
        let first = try #require(notifier.signal)
        #expect(first.destination == .root)

        notifier.notify(.root)
        let second = try #require(notifier.signal)
        #expect(second.destination == .root)
        #expect(second.id != first.id, "the second reload must be a change, or the screen never hears it")
    }
}
