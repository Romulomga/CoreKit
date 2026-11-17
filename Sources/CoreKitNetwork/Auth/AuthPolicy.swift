import Foundation

public protocol AuthPolicy: Sendable {
    func requiresAuthentication(for request: URLRequest) -> Bool
}

public struct AuthenticateAllPolicy: AuthPolicy {
    public init() {}

    public func requiresAuthentication(for request: URLRequest) -> Bool {
        true
    }
}
