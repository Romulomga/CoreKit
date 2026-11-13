import Foundation

/// One entry of a `Coordinator` path. The identity is the entry, not the destination, so the same
/// route can sit twice in a stack (profile A → post → profile A) as two separate screens, each
/// with its own state.
struct NavigationStep<D: NavigableDestination>: Hashable {

    let id = UUID()
    let destination: D

    init(destination: D) {
        self.destination = destination
    }

    static func == (lhs: NavigationStep, rhs: NavigationStep) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
