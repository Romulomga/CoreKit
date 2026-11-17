import Foundation

public protocol TokenRefresher: Sendable {
    func refresh(using session: URLSession) async throws
}
