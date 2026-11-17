import Testing
import Foundation
@testable import CoreKitNetwork

@Suite("ReachabilityInterceptor")
struct ReachabilityInterceptorTests {

    private let testURL = URL(string: "https://example.com")!

    @Test("Passes request through when network is connected")
    func passesRequestWhenConnected() async throws {
        let monitor = MockNetworkMonitor(isConnected: true)
        let interceptor = ReachabilityInterceptor(monitor: monitor)
        let request = URLRequest(url: testURL)

        let result = try await interceptor.intercept(request: request)

        #expect(result.url == testURL)
    }

    @Test("Throws NetworkMonitorError.notConnected when network is disconnected")
    func throwsWhenNotConnected() async {
        let monitor = MockNetworkMonitor(isConnected: false)
        let interceptor = ReachabilityInterceptor(monitor: monitor)
        let request = URLRequest(url: testURL)

        await #expect(throws: NetworkMonitorError.self) {
            try await interceptor.intercept(request: request)
        }
    }

    @Test("Preserves original request URL and headers when connected")
    func preservesRequestProperties() async throws {
        let monitor = MockNetworkMonitor(isConnected: true)
        let interceptor = ReachabilityInterceptor(monitor: monitor)

        var request = URLRequest(url: testURL)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"

        let result = try await interceptor.intercept(request: request)

        #expect(result.url == testURL)
        #expect(result.httpMethod == "POST")
        #expect(result.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
}
