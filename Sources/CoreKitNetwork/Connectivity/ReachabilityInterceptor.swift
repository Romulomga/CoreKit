import Foundation

final class ReachabilityInterceptor: NetworkInterceptor {
    
    // MARK: - Properties
    
    private let monitor: NetworkMonitoring
    
    // MARK: - Initializers
    init(monitor: NetworkMonitoring) {
        self.monitor = monitor
    }
    
    // MARK: - NetworkInterceptor
    
    func intercept(request: URLRequest) async throws -> URLRequest {
        try monitor.requireConnection()
        return request
    }
}
