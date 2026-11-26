import Foundation

/// A rule about where something may appear in an app's sources, checked by a test.
///
/// Written-down architecture drifts: a screen starts holding a database object, a view model reads
/// the store's write counter, a `Views/` folder comes back. A test that reads the sources and fails
/// names the file and the line, so the drift breaks the build instead of waiting for a review.
public struct ArchitectureRule: Sendable {
    public let name: String
    let fileMatches: @Sendable (String) -> Bool
    let pattern: String

    /// Lines of the files `fileMatches` accepts (by path relative to the sources root) must not match
    /// `pattern` (a regular expression). Comment lines are skipped.
    public init(_ name: String, files fileMatches: @escaping @Sendable (String) -> Bool, forbidding pattern: String) {
        self.name = name
        self.fileMatches = fileMatches
        self.pattern = pattern
    }
}

public enum ArchitectureCheck {

    /// Every line that breaks a rule, as "path:line: rule: code", and every folder in `forbiddenFolders`
    /// found under `root`. Empty when the sources follow the rules.
    public static func violations(in root: URL, rules: [ArchitectureRule], forbiddenFolders: Set<String> = []) -> [String] {
        var found: [String] = []
        // Compiled once per check, not once per line: an app has thousands of lines and dozens of rules.
        // A pattern `NSRegularExpression` refuses (an unescaped `}`) keeps the slower `range(of:)`, as before 0.1.27.
        let compiled = rules.map { rule in (rule: rule, regex: try? NSRegularExpression(pattern: rule.pattern)) }

        for path in swiftFiles(in: root) {
            let components = path.split(separator: "/").dropLast().map(String.init)

            for folder in components where forbiddenFolders.contains(folder) {
                found.append("\(path): folder \(folder)/ is not allowed")
            }

            let applicable = compiled.filter { $0.rule.fileMatches(path) }
            guard !applicable.isEmpty, let text = try? String(contentsOf: root.appending(path: path), encoding: .utf8) else { continue }

            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }

                let range = NSRange(code.startIndex..., in: code)

                for (rule, regex) in applicable where regex.map({ $0.firstMatch(in: code, range: range) != nil })
                    ?? (code.range(of: rule.pattern, options: .regularExpression) != nil) {
                    found.append("\(path):\(index + 1): \(rule.name): \(code)")
                }
            }
        }

        return Array(Set(found)).sorted()
    }

    /// The names of the classes marked `@Model` under `root`: what a rule about database objects in
    /// views should forbid, read from the code instead of a list that goes stale.
    public static func modelTypeNames(in root: URL) -> [String] {
        var names: Set<String> = []

        for path in swiftFiles(in: root) {
            guard let text = try? String(contentsOf: root.appending(path: path), encoding: .utf8) else { continue }

            let lines = text.components(separatedBy: .newlines)

            for (index, line) in lines.enumerated() where line.trimmingCharacters(in: .whitespaces).hasPrefix("@Model") {
                let rest = ([line] + lines.dropFirst(index + 1).prefix(2)).joined(separator: " ")

                if let range = rest.range(of: #"class\s+([A-Za-z_][A-Za-z0-9_]*)"#, options: .regularExpression) {
                    let declaration = rest[range]
                    names.insert(String(declaration.split(whereSeparator: \.isWhitespace).last ?? ""))
                }
            }
        }

        return names.sorted()
    }

    /// Paths of the Swift files under `root`, relative to it.
    static func swiftFiles(in root: URL) -> [String] {
        let rootPath = root.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(atPath: rootPath) else { return [] }

        return enumerator.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }.sorted()
    }
}
