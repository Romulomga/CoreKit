import Foundation
@testable import CoreKitNetwork

struct MockAuthPolicy: AuthPolicy {
    var unauthenticatedPaths: Set<String>

    init(unauthenticatedPaths: Set<String> = []) {
        self.unauthenticatedPaths = unauthenticatedPaths
    }

    func requiresAuthentication(for request: URLRequest) -> Bool {
        guard let path = request.url?.path.lowercased() else { return true }
        return !unauthenticatedPaths.contains(where: { path.contains($0) })
    }
}
