import CoreKit
import Testing

@Suite struct AsyncStreamMapTests {

    @Test func mapsEveryElementAndFinishesWithTheSource() async {
        let (source, continuation) = AsyncStream<Int>.makeStream()
        let mapped: AsyncStream<Bool> = source.map { $0 > 0 }

        continuation.yield(1)
        continuation.yield(0)
        continuation.finish()

        var values: [Bool] = []

        for await value in mapped {
            values.append(value)
        }

        #expect(values == [true, false])
    }

    @Test(.timeLimit(.minutes(1)))
    func aConsumerThatGoesAwayStopsTheSource() async {
        let (source, continuation) = AsyncStream<Int>.makeStream()
        let (sourceEnded, ended) = AsyncStream<Void>.makeStream()
        continuation.onTermination = { _ in ended.yield() }

        let mapped = source.map { $0 * 2 }
        let consumer = Task {
            for await _ in mapped {}
        }

        consumer.cancel()

        var iterator = sourceEnded.makeAsyncIterator()
        let didEnd: Void? = await iterator.next()
        #expect(didEnd != nil, "the forwarding task is cancelled with the consumer and lets go of the source")
    }
}
