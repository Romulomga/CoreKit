import CoreKit
import Testing

@MainActor
@Suite struct SingleFlightTests {

    private struct DiskFull: Error {}

    @Test func aSecondTapWhileSavingIsIgnored() async {
        let flight = SingleFlight()
        let gate = Gate()
        var saves = 0

        let first = flight.launch {
            saves += 1
            await gate.wait()
        }

        let second = flight.launch { saves += 1 }

        #expect(first != nil)
        #expect(second == nil)
        #expect(flight.isRunning)

        gate.open()
        await first?.value

        #expect(saves == 1)
        #expect(!flight.isRunning)
    }

    @Test func theLockClosesBeforeTheTaskStarts() {
        let flight = SingleFlight()

        flight.launch {}

        #expect(flight.isRunning)
        #expect(flight.launch {} == nil)
    }

    @Test func opensAgainAfterTheSaveEnds() async {
        let flight = SingleFlight()
        var saves = 0

        await flight.launch { saves += 1 }?.value
        await flight.launch { saves += 1 }?.value

        #expect(saves == 2)
    }

    @Test func opensAgainWhenTheSaveThrows() async {
        let flight = SingleFlight()

        await #expect(throws: DiskFull.self) {
            try await flight.run { throw DiskFull() }
        }

        #expect(!flight.isRunning)
    }

    @Test func opensAgainWhenTheTaskIsCancelled() async {
        let flight = SingleFlight()
        let task = flight.launch {
            try? await Task.sleep(for: .seconds(60))
        }

        task?.cancel()
        await task?.value

        #expect(!flight.isRunning)
    }

    @Test func runReturnsNilForTheIgnoredCall() async {
        let flight = SingleFlight()
        let gate = Gate()
        let first = flight.launch { await gate.wait() }

        #expect(await flight.run { "saved" } == nil)

        gate.open()
        await first?.value

        #expect(await flight.run { "saved" } == "saved")
    }

    @Test func aKeyedFlightLocksOnlyTheSameKey() async {
        let flight = KeyedSingleFlight<String>()
        let gate = Gate()
        var saved: [String] = []

        let a = flight.launch("a") {
            saved.append("a")
            await gate.wait()
        }

        #expect(a != nil)
        #expect(flight.launch("a") { saved.append("a") } == nil)

        let b = flight.launch("b") { saved.append("b") }

        #expect(b != nil)

        await b?.value

        #expect(flight.running == ["a"])
        #expect(flight.isRunning("a"))
        #expect(!flight.isRunning("b"))

        gate.open()
        await a?.value

        #expect(saved == ["a", "b"])
        #expect(flight.running.isEmpty)
    }

    @Test func aKeyedRunOpensAgainWhenItThrows() async {
        let flight = KeyedSingleFlight<Int>()

        await #expect(throws: DiskFull.self) {
            try await flight.run(1) { throw DiskFull() }
        }

        #expect(flight.running.isEmpty)
    }
}

/// Holds a test action until the test opens it.
@MainActor
private final class Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }

        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}
