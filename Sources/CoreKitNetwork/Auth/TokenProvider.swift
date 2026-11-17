import Foundation

public protocol TokenProvider: Sendable {
    func getAccessToken() async throws -> String
}
