import Foundation
import os
@testable import CoreKitNetwork

final class MockNetworkLogger: NetworkLogger {

    struct LogEntry: Sendable {
        let level: LogLevel
        let message: String
        let metadata: [String: String]
    }

    private let state = OSAllocatedUnfairLock<[LogEntry]>(initialState: [])

    var entries: [LogEntry] {
        state.withLock { $0 }
    }

    func log(level: LogLevel, message: String, metadata: [String: String]) {
        state.withLock {
            $0.append(LogEntry(level: level, message: message, metadata: metadata))
        }
    }
}
