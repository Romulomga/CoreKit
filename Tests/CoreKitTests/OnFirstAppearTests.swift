@testable import CoreKit
import SwiftUI
import Testing

@MainActor
@Suite struct OnFirstAppearTests {

    @Test func aFinishedLoadDoesNotRunAgain() async {
        let gate = FirstRunGate()
        var loads = 0

        await gate.run { loads += 1 }
        await gate.run { loads += 1 }

        #expect(loads == 1)
        #expect(gate.hasFinished)
    }

    @Test func aLoadCancelledByLeavingRunsAgainOnReturn() async {
        let gate = FirstRunGate()
        var loads = 0

        let leftEarly = Task { @MainActor in
            await gate.run {
                loads += 1
                try? await Task.sleep(for: .seconds(60))
            }
        }

        await Task.yield()
        leftEarly.cancel()
        await leftEarly.value

        #expect(!gate.hasFinished)

        await gate.run { loads += 1 }

        #expect(loads == 2)
        #expect(gate.hasFinished)
    }

    @Test func bothFormsResolve() {
        @MainActor final class Model {
            func start() {}
            func load() async {}
        }

        let model = Model()

        _ = Text("sync").onFirstAppear { model.start() }
        _ = Text("sync ref").onFirstAppear(perform: model.start)
        _ = Text("async").onFirstAppear { await model.load() }
    }
}
