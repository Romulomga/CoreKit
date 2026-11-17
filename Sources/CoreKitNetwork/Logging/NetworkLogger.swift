import Foundation

public protocol NetworkLogger: Sendable {
    func log(level: LogLevel, message: String, metadata: [String: String])
}
