import Foundation

/// A URL without what identifies a person, before it reaches a log that outlives the session: the whole query (an
/// e-mail in `?email=`, a search, a position) and the path segments that carry typed data, which are the ones right
/// after a `sensitiveParents` segment (`…/phone-number/{phone}/code/{code}`). Ids stay: they say which call failed.
/// Twin of CoreKit-Android's `UrlRedaction`.
///
/// The app names its own sensitive segments; with none, only the query and the fragment go.
public struct URLRedaction: Sendable, Hashable {
    public static let mask = "***"

    /// Segments whose next segment is data, compared case-insensitively.
    public let sensitiveParents: Set<String>

    /// Fixed route words that may follow a sensitive parent without being data (`…/code/check/…`).
    public let routeWords: Set<String>

    public init(sensitiveParents: Set<String> = [], routeWords: Set<String> = []) {
        self.sensitiveParents = Set(sensitiveParents.map { $0.lowercased() })
        self.routeWords = Set(routeWords.map { $0.lowercased() })
    }

    /// The URL without query or fragment, its sensitive segments replaced by `mask`.
    public func redact(_ url: URL) -> String {
        redact(url.absoluteString)
    }

    /// The same for a URL already turned into text.
    public func redact(_ url: String) -> String {
        let bare = String(url.prefix { $0 != "?" && $0 != "#" })

        guard let scheme = bare.range(of: "://") else { return maskPath(bare) }

        guard let pathStart = bare[scheme.upperBound...].firstIndex(of: "/") else { return bare }

        return String(bare[..<pathStart]) + maskPath(String(bare[pathStart...]))
    }

    /// The path with its sensitive segments replaced by `mask`.
    public func maskPath(_ path: String) -> String {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)

        return segments.indices
            .map { isSensitive(segments, at: $0) ? Self.mask : segments[$0] }
            .joined(separator: "/")
    }

    private func isSensitive(_ segments: [String], at index: Int) -> Bool {
        guard index > 0 else { return false }

        let segment = segments[index].lowercased()

        return !segment.isEmpty && !routeWords.contains(segment) && sensitiveParents.contains(segments[index - 1].lowercased())
    }
}
