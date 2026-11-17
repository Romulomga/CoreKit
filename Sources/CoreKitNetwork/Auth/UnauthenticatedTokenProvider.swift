import Foundation

public struct UnauthenticatedTokenProvider: TokenProvider {

    public init() { }

    public func getAccessToken() async throws -> String {
        throw UnauthenticatedTokenProviderError.noToken
    }
}

public enum UnauthenticatedTokenProviderError: Error, Sendable {
    case noToken
}
