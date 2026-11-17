@testable import CoreKitNavigation
import SwiftUI
import Testing

/// A login-gated app's routes, declared the way Homer declares its own.
enum TestDestination: SessionDestination {
    case root, detail(Int), settings, mainTab

    var id: String { String(describing: self) }

    var isStandalone: Bool { self == .mainTab }

    var presentationDetent: Set<PresentationDetent> { [] }
}

/// An app without login: only the cases, every requirement left to its default.
enum PlainRoute: NavigableDestination {
    case home, list, detail(id: Int)
}

@MainActor
final class Recorder<Value> {
    private(set) var items: [Value] = []

    func append(_ value: Value) { items.append(value) }
}

/// The observers consume their streams on tasks of their own; poll briefly instead of relying on
/// a fixed number of yields.
@MainActor
func waitUntil(sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool) async {
    for _ in 0..<1_000 where !condition() {
        try? await Task.sleep(for: .milliseconds(5))
    }

    // Giving up is a failure here, not a silent go-ahead into a confusing expectation.
    if !condition() { Issue.record("waitUntil gave up before the condition held", sourceLocation: sourceLocation) }
}

/// A tab app with a bottom stack, declared the way Homer declares its own: two tabs, a pushed screen in each, a
/// conversation that replaces its tab's stack, and a login screen on the bottom stack.
enum TabRoute: DeepLinkDestination, SessionDestination {
    case home, inbox, mainTab
    case detail(Int)
    case conversation(Int)
    case login

    var tab: TabRoute? {
        switch self {
        case .home, .detail: .home
        case .inbox, .conversation: .inbox
        case .login, .mainTab: nil
        }
    }

    var replacesStack: Bool {
        if case .conversation = self { true } else { false }
    }

    init?(url: URL) {
        switch url.host() {
        case "detail": self = .detail(Int(url.lastPathComponent) ?? 0)
        case "conversation": self = .conversation(Int(url.lastPathComponent) ?? 0)
        case "login": self = .login
        default: return nil
        }
    }
}

/// An `@Observable` stand-in for the session a navigator holds links on.
@MainActor
@Observable
final class Readiness {
    var isReady = false
}
