import Foundation
import os
#if canImport(OSLog)
import OSLog
#endif

final class LoggingInterceptor: NetworkInterceptor {

    // MARK: - Properties

    private let logger: NetworkLogger
    private let logLevel: LogLevel
    private let includeSensitiveData: Bool
    /// Headers and body only on a failed response: a success is one line.
    private let sensitiveDataOnFailureOnly: Bool
    private let redactedHeaders: Set<String>

    // MARK: - Initializers
    init(
        logger: NetworkLogger = OSLogNetworkLogger(),
        logLevel: LogLevel = .info,
        includeSensitiveData: Bool = false,
        sensitiveDataOnFailureOnly: Bool = false,
        redactedHeaders: Set<String> = NetworkService.defaultRedactedHeaders
    ) {
        self.logger = logger
        self.logLevel = logLevel
        self.includeSensitiveData = includeSensitiveData
        self.sensitiveDataOnFailureOnly = sensitiveDataOnFailureOnly
        self.redactedHeaders = Set(redactedHeaders.map { $0.lowercased() })
    }

    // MARK: - NetworkInterceptor
    func intercept(request: URLRequest) async throws -> URLRequest {
        guard shouldLog(level: .debug) else { return request }

        let metadata = buildRequestMetadata(from: request)
        logger.log(level: .debug, message: "→ REQUEST", metadata: metadata)

        return request
    }

    func intercept<T: Decodable>(response: inout NetworkResponse<T>) async throws {
        let level: LogLevel = response.isSuccessful ? .info : .error
        guard shouldLog(level: level) else { return }

        let metadata = buildResponseMetadata(from: response)
        let prefix = response.isSuccessful ? "✓" : "✗"

        logger.log(level: level, message: "\(prefix) RESPONSE", metadata: metadata)
    }

    // MARK: - Private Methods

    private func shouldLog(level: LogLevel) -> Bool {
        level.rawValue >= logLevel.rawValue
    }

    private func buildRequestMetadata(from request: URLRequest) -> [String: String] {
        var metadata: [String: String] = [:]

        if let url = request.url {
            metadata["url"] = url.absoluteString
        }

        if let method = request.httpMethod {
            metadata["method"] = method
        }

        if includeSensitiveData {
            if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
                metadata["headers"] = redact(headers: headers).description
            }

            if let body = request.httpBody,
               let bodyString = String(data: body, encoding: .utf8) {
                metadata["body"] = bodyString
            }
        } else {
            if let headers = request.allHTTPHeaderFields {
                metadata["headers_count"] = "\(headers.count)"
            }

            if let body = request.httpBody {
                metadata["body_size"] = "\(body.count) bytes"
            }
        }

        return metadata
    }

    private func buildResponseMetadata<T: Decodable>(from response: NetworkResponse<T>) -> [String: String] {
        var metadata: [String: String] = [:]

        metadata["status_code"] = "\(response.statusCode.rawValue)"
        metadata["status"] = response.statusCode.description

        if let url = response.request.url {
            metadata["url"] = url.absoluteString
        }

        if let method = response.request.httpMethod {
            metadata["method"] = method
        }

        metadata["data_size"] = "\(response.data.count) bytes"
        metadata["duration_ms"] = String(format: "%.0f", response.duration * 1000)

        if includeSensitiveData, !sensitiveDataOnFailureOnly || !response.isSuccessful {
            let headers = redact(headers: response.headers)
            if !headers.isEmpty {
                metadata["headers"] = headers.description
            }

            if let bodyString = String(data: response.data, encoding: .utf8) {
                let maxLength = 500
                if bodyString.count > maxLength {
                    metadata["body"] = String(bodyString.prefix(maxLength)) + "... (truncated)"
                } else {
                    metadata["body"] = bodyString
                }
            }
        }

        return metadata
    }

    private func redact(headers: [String: String]) -> [String: String] {
        headers.reduce(into: [String: String]()) { partialResult, entry in
            if redactedHeaders.contains(entry.key.lowercased()) {
                partialResult[entry.key] = "[REDACTED]"
            } else {
                partialResult[entry.key] = entry.value
            }
        }
    }
}

// MARK: - OSLog Network Logger

#if canImport(OSLog)
/// The release logger: the URL goes out as `<private>`, the rest in clear.
///
/// A `String` interpolated into `Logger` is private by default, which turned every line into a useless one, hence
/// `.public` on the diagnostics. The URL is not harmless diagnostics, though: a path can carry the user's position or
/// what they typed (a search with coordinates and the term in the path itself), and in a release build the line goes
/// to the device's unified log (in memory on success, on disk on an error, and into any sysdiagnose). Method, status,
/// duration and size are enough to diagnose, so the URL stays private.
struct OSLogNetworkLogger: NetworkLogger {

    private let logger: Logger

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "CoreKit", category: String = "Network") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    func log(level: LogLevel, message: String, metadata: [String: String]) {
        var fields = metadata
        let url = fields.removeValue(forKey: "url") ?? "-"
        let metadataString = fields.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }.joined(separator: ", ")

        logger.log(
            level: level.osLogType,
            "\(message, privacy: .public) | url: \(url, privacy: .private) | \(metadataString, privacy: .public)"
        )
    }
}
#else
struct OSLogNetworkLogger: NetworkLogger {
    func log(level: LogLevel, message: String, metadata: [String: String]) {
        ConsoleNetworkLogger().log(level: level, message: message, metadata: metadata)
    }
}
#endif

// MARK: - Console Network Logger

/// The debug logger: everything to the attached debugger, and one safe line mirrored to the system log.
struct ConsoleNetworkLogger: NetworkLogger {

    /// A Sendable value, unlike `ISO8601DateFormatter`: no lock needed.
    private static let timestampStyle = Date.ISO8601FormatStyle()

    #if canImport(OSLog)
    /// Same subsystem and category as `OSLogNetworkLogger`, so one filter catches both.
    private static let systemLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CoreKit", category: "Network")
    #endif

    /// What the system-log mirror carries, in this order: most diagnostic first, because the syslog relay cuts a line
    /// at about 250 characters. A key not listed here is never mirrored.
    private static let mirroredKeys = ["method", "status_code", "url", "duration_ms", "data_size"]

    private let urlRedaction: URLRedaction

    init(urlRedaction: URLRedaction = URLRedaction()) {
        self.urlRedaction = urlRedaction
    }

    func log(level: LogLevel, message: String, metadata: [String: String]) {
        mirrorToSystemLog(message: message, metadata: metadata)

        // The mirrored line already says method, status, URL, duration and size (and the Xcode console shows it); the
        // print adds only what the mirror leaves out, if anything (`status` is `status_code` spelled out).
        let extra = metadata.filter { !Self.mirroredKeys.contains($0.key) && $0.key != "status" }
        guard !extra.isEmpty else { return }
        let timestamp = Date().formatted(Self.timestampStyle)
        print("\(timestamp) \(iconForLevel(level)) [\(level)] \(message)")
        extra.sorted { $0.key < $1.key }.forEach { key, value in
            print("  ├─ \(key): \(value)")
        }
    }

    /// `print` only reaches an attached debugger: the stdout of an app opened from the home screen goes nowhere, and no
    /// cable log tool sees it (measured: 57 thousand lines of `idevicesyslog` without one of ours). The mirror at
    /// `.default` (`notice`, which is persisted and relayed, unlike `.debug`) keeps the request readable with the device
    /// on a cable, without Xcode.
    ///
    /// **Nothing sensitive goes through here, and the list is an allow list.** The mirror only exists in debug builds,
    /// but a debug build can be handed to testers. In debug `includeSensitiveData` is on, so the metadata of a failure
    /// (or of everything, when verbose) carries headers and body: a password in a login body, in clear. Mirroring that
    /// at `.default` wrote a credential to the device log, where it outlives the app and leaves in any sysdiagnose. The
    /// `print` above carries the rest: it is volatile and reaches only whoever holds the debugger. The URL goes through
    /// `urlRedaction` (no query, no typed data in the path), and the success line is a single one.
    private func mirrorToSystemLog(message: String, metadata: [String: String]) {
        #if canImport(OSLog)
        Self.systemLog.log(level: .default, "\(message) | \(mirroredLine(metadata), privacy: .public)")
        #endif
    }

    func mirroredLine(_ metadata: [String: String]) -> String {
        Self.mirroredKeys
            .compactMap { key in
                metadata[key].map { "\(key): \(key == "url" ? urlRedaction.redact($0) : $0)" }
            }
            .joined(separator: ", ")
    }

    private func iconForLevel(_ level: LogLevel) -> String {
        switch level {
        case .debug:
            return "🔍"
        case .info:
            return "ℹ️"
        case .warning:
            return "⚠️"
        case .error:
            return "❌"
        }
    }
}
