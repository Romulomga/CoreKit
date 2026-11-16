import CoreKit
import Observation
import Testing

@MainActor
@Observable
private final class Counter {
    var value = 0
    var unrelated = 0
}

@MainActor
@Suite struct AsyncStreamObservingTests {

    @Test func deliversTheValueNowAndAgainAfterAChange() async {
        let counter = Counter()
        let stream = AsyncStream.observing { counter.value * 10 }
        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next() == 0)

        counter.value = 2

        #expect(await iterator.next() == 20)
    }

    @Test func aChangeThatGivesTheSameValueIsNotDeliveredAgain() async throws {
        let counter = Counter()
        let stream = AsyncStream.observing { counter.value > 5 }
        var delivered: [Bool] = []
        let consumer = Task { @MainActor in
            for await value in stream {
                delivered.append(value)
            }
        }
        defer { consumer.cancel() }

        try await Task.sleep(for: .milliseconds(30))

        // Read again after each change: 1 still reads "false" and must not be delivered a second time.
        counter.value = 1
        try await Task.sleep(for: .milliseconds(30))

        counter.value = 9
        try await Task.sleep(for: .milliseconds(30))

        #expect(delivered == [false, true])
    }

    @Test func somethingTheReadDidNotTouchDoesNotRunItAgain() async throws {
        let counter = Counter()
        var reads = 0
        let stream = AsyncStream.observing {
            reads += 1
            return counter.value
        }
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        counter.unrelated = 1
        try await Task.sleep(for: .milliseconds(50))

        #expect(reads == 1)
    }

    @Test func aConsumerThatGoesAwayStopsTheReads() async throws {
        let counter = Counter()
        var reads = 0
        let stream = AsyncStream.observing {
            reads += 1
            return counter.value
        }

        let consumer = Task { for await _ in stream {} }
        try await Task.sleep(for: .milliseconds(20))
        consumer.cancel()
        await consumer.value
        try await Task.sleep(for: .milliseconds(20))
        let readsWhenGone = reads

        counter.value = 1
        try await Task.sleep(for: .milliseconds(50))

        #expect(reads <= readsWhenGone + 1, "at most the read already scheduled; nothing after the stop")
    }
}
