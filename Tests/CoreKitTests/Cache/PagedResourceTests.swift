@testable import CoreKit
import CoreKitTesting
import Foundation
import Testing

/// The paging of an app's server caches: offset or page number, deduplicated by id, no next page while
/// the first one restarts, and fetches that outlive the screen.
@MainActor
@Suite struct PagedResourceTests {

    struct Row: Identifiable, Equatable, Sendable {
        let id: Int
        var isFollowing = false
    }

    /// Rows `start..<start + count`, with more after them while `hasMore`.
    static func page(_ start: Int, _ count: Int, hasMore: Bool) -> Page<Row> {
        Page(items: (start..<start + count).map { Row(id: $0) }, hasMore: hasMore)
    }

    @Test func loadingTwiceKeepsThePagesAndAsksTheServerOnce() async {
        let server = PageSpy { _ in Self.page(0, 3, hasMore: true) }
        let resource = server.resource()

        resource.load("list")
        await waitUntil { resource.list("list").status == .loaded }
        server.answer = { _ in Self.page(3, 3, hasMore: false) }
        await resource.loadMore("list")
        resource.load("list")

        #expect(resource.list("list").items.map(\.id) == Array(0..<6))
        #expect(server.requests == [PageRequest(offset: 0, number: 1), PageRequest(offset: 3, number: 2)])
    }

    @Test func theNextPageStartsAtTheRowsLoadedAndSkipsTheOnesAlreadyThere() async {
        let server = PageSpy { _ in Self.page(0, 3, hasMore: true) }
        let resource = server.resource()
        await resource.refresh("list")

        server.answer = { _ in Self.page(2, 3, hasMore: false) }
        #expect(await resource.loadMore("list") == nil)

        #expect(resource.list("list").items.map(\.id) == [0, 1, 2, 3, 4], "the repeated row is not drawn twice")
        #expect(!resource.list("list").hasMore)
        #expect(await resource.loadMore("list") == nil)
        #expect(server.requests.count == 2, "no page after the last")
    }

    /// The row's `.task` that asked for the page goes when the row scrolls away; the page lands anyway.
    @Test func aPageAskedByARowThatLeftStillLands() async {
        let server = PageSpy { _ in Self.page(0, 3, hasMore: true) }
        let resource = server.resource()
        await resource.refresh("list")
        server.answer = { _ in Self.page(3, 3, hasMore: false) }

        await runCancelled { await resource.loadMore("list") }

        await waitUntil { resource.list("list").items.count == 6 }
        #expect(!resource.list("list").isLoadingMore)
    }

    /// The rows on screen belong to the old list: their count would be the offset of the new one.
    @Test func noNextPageLeavesWhileThePageRestartsAndAPageOnItsWayIsLetGo() async {
        let server = PageSpy { _ in Self.page(0, 3, hasMore: true) }
        let resource = server.resource()
        await resource.refresh("list")
        server.gate.hold()

        let nextPage = Task { await resource.loadMore("list") }
        await waitUntil { server.gate.waitingCount == 1 }
        let refreshing = Task { await resource.refresh("list") }
        await waitUntil { server.gate.waitingCount == 2 }
        #expect(!resource.list("list").isLoadingMore, "the restart let the next page go")
        // In a task of its own: a next page asked by mistake would wait at the closed gate and hang the test.
        var askedDone = false
        let asked = Task {
            let failure = await resource.loadMore("list")
            askedDone = true
            return failure
        }

        // Either it returned at once (right) or it reached the closed gate (wrong): only then can the gate open.
        await waitUntil { askedDone || server.gate.waitingCount == 3 }
        server.gate.release()
        #expect(await nextPage.value == nil, "a page let go says nothing")
        _ = await refreshing.value
        #expect(await asked.value == nil)
        #expect(server.requests.count == 3, "no next page while the first one is on its way")
        #expect(resource.list("list").items.map(\.id) == [0, 1, 2])
    }

    @Test func aFailedFirstPageFailsAndAFailedRefreshKeepsTheRows() async {
        let server = PageSpy { _ in throw TestFailure.offline }
        let resource = server.resource()

        resource.load("list")
        await waitUntil { resource.list("list").status == .failed(.offline) }

        server.answer = { _ in Self.page(0, 3, hasMore: false) }
        #expect(await resource.refresh("list") == nil)
        server.answer = { _ in throw TestFailure.server }
        #expect(await resource.refresh("list") == .server)
        #expect(resource.list("list").items.count == 3)
        #expect(resource.list("list").status == .loaded)
    }

    /// The next opening of a list that failed asks for its first page again; a loaded one is left alone.
    @Test func theNextOpeningOfAFailedListAsksAgain() async {
        let server = PageSpy { _ in throw TestFailure.offline }
        let resource = server.resource()
        resource.load("list")
        await waitUntil { resource.list("list").status == .failed(.offline) }

        server.answer = { _ in Self.page(0, 3, hasMore: false) }
        resource.load("list")
        await waitUntil { resource.list("list").status == .loaded }
        resource.load("list")

        #expect(server.requests.count == 2)
        #expect(resource.list("list").items.count == 3)
    }

    @Test func aRowChangesInEveryListThatShowsIt() async {
        let server = PageSpy { _ in Self.page(0, 3, hasMore: false) }
        let resource = server.resource()
        await resource.refresh("followers")
        await resource.refresh("following")

        resource.updateItem(1) { $0.isFollowing = true }

        #expect(resource.list("followers").items[1].isFollowing)
        #expect(resource.list("following").items[1].isFollowing)
    }

    /// An opening that must not show what was kept: the rows go at once and the first page is read again; a next page
    /// on its way for the old rows never lands.
    @Test func aReloadDropsTheRowsAndThePagesOnTheirWay() async {
        let server = PageSpy { _ in Self.page(0, 3, hasMore: true) }
        let resource = server.resource()
        await resource.refresh("list")
        server.gate.hold()
        let nextPage = Task { await resource.loadMore("list") }
        await waitUntil { server.gate.waitingCount == 1 }

        server.answer = { _ in Self.page(10, 2, hasMore: false) }
        resource.reload("list")

        #expect(resource.list("list").items.isEmpty, "nothing kept on screen")
        #expect(resource.list("list").status == .loading)
        server.gate.release()
        _ = await nextPage.value
        await waitUntil { resource.list("list").status == .loaded }
        #expect(resource.list("list").items.map(\.id) == [10, 11])
        #expect(resource.list("list").pages == 1)
    }

    // MARK: - Total, rows taken out, and a refresh joined a restart replaced meanwhile

    @Test func theTotalFollowsTheServerAndKeepsWhenAPageDoesNotSayIt() async {
        let server = PageSpy { _ in Page(items: (0..<3).map { Row(id: $0) }, hasMore: true, total: 7) }
        let resource = server.resource()
        await resource.refresh("list")
        #expect(resource.list("list").total == 7)

        server.answer = { _ in Self.page(3, 3, hasMore: true) }
        await resource.loadMore("list")
        #expect(resource.list("list").total == 7, "a page that does not say keeps the last total")
    }

    /// QA 26/09 (Homer): 15 of 162 inactive posts deleted showed "nenhuma publicação". The page emptied by a write
    /// reads the server again under the skeleton; the empty state comes only when the server says so.
    @Test func aListEmptiedByAWriteReadsTheServerAgainUnderTheSkeleton() async {
        let server = PageSpy { _ in Page(items: (0..<3).map { Row(id: $0) }, hasMore: true, total: 10) }
        let resource = server.resource()
        await resource.refresh("list")
        server.gate.hold()
        server.answer = { _ in Page(items: (3..<6).map { Row(id: $0) }, hasMore: true, total: 7) }

        #expect(resource.removeItems([0, 1, 2], from: "list"))

        #expect(resource.list("list").items.isEmpty)
        #expect(resource.list("list").status == .loading, "the skeleton, never the empty state")
        #expect(resource.list("list").total == 7)
        server.gate.release()
        await waitUntil { resource.list("list").status == .loaded }
        #expect(resource.list("list").items.map(\.id) == [3, 4, 5])
        #expect(server.requests.last == PageRequest(offset: 0, number: 1))
    }

    /// The row near the end that asks for the next page already showed before the rows moved up: the list fills itself.
    @Test func rowsTakenOutBringTheNextPageWhenTheServerHasMore() async {
        let server = PageSpy { _ in Page(items: (0..<3).map { Row(id: $0) }, hasMore: true, total: 6) }
        let resource = server.resource()
        await resource.refresh("list")
        server.answer = { _ in Page(items: (3..<6).map { Row(id: $0) }, hasMore: false, total: 5) }

        #expect(resource.removeItems([1], from: "list"))

        await waitUntil { !resource.list("list").isLoadingMore && resource.list("list").items.count == 5 }
        #expect(resource.list("list").items.map(\.id) == [0, 2, 3, 4, 5])
        #expect(server.requests.last == PageRequest(offset: 2, number: 2), "the offset is the rows left")
        #expect(resource.list("list").total == 5)
    }

    @Test func rowsThatWereNotThereChangeNothing() async {
        let server = PageSpy { _ in Page(items: (0..<3).map { Row(id: $0) }, hasMore: false, total: 3) }
        let resource = server.resource()
        await resource.refresh("list")

        #expect(!resource.removeItems([9], from: "list"))
        #expect(resource.removeItems([0, 1, 2], from: "list"))

        #expect(resource.list("list").status == .loaded, "emptied with nothing more on the server: the empty state")
        #expect(resource.list("list").total == 0)
        #expect(server.requests.count == 1)
    }

    /// A pull joined a restart that a write replaced, and the replacement landed first: the pull says what decided
    /// the list, never the silence of the restart let go.
    @Test func aRefreshSaysWhatTheRestartThatReplacedItsAnswered() async {
        let server = PageSpy { _ in Self.page(0, 3, hasMore: false) }
        let resource = server.resource()
        await resource.refresh("list")
        server.gate.hold()
        let pulling = Task { await resource.refresh("list") }
        await waitUntil { server.gate.waitingCount == 1 }

        server.answer = { _ in throw TestFailure.offline }
        resource.invalidate("list")
        await waitUntil { server.gate.waitingCount == 2 }
        server.gate.release()

        #expect(await pulling.value == .offline)
    }

    @Test func theEndOfTheSessionEmptiesTheListsAndDropsAnswersOnTheirWay() async {
        let server = PageSpy { _ in Self.page(0, 3, hasMore: true) }
        let resource = server.resource()
        await resource.refresh("list")
        server.gate.hold()

        let refreshing = Task { await resource.refresh("list") }
        await waitUntil { server.gate.waitingCount == 1 }
        resource.clear()
        server.gate.release()
        _ = await refreshing.value

        #expect(resource.lists.isEmpty, "the previous user's answer never lands")
    }
}

/// A page fetch the test scripts: it records the requests, waits at the gate, then answers.
@MainActor
final class PageSpy {
    let gate = TestGate()
    private(set) var requests: [PageRequest] = []
    var answer: @MainActor (PageRequest) throws -> Page<PagedResourceTests.Row>

    init(_ answer: @escaping @MainActor (PageRequest) throws -> Page<PagedResourceTests.Row>) {
        self.answer = answer
    }

    func resource() -> PagedResource<String, PagedResourceTests.Row, TestFailure> {
        PagedResource(mapError: TestFailure.map) { [self] _, request in
            requests.append(request)
            await gate.pass()
            try Task.checkCancellation()
            return try answer(request)
        }
    }
}
