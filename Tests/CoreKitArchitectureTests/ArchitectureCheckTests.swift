import CoreKitArchitecture
import Foundation
import Testing

@Suite struct ArchitectureCheckTests {

    private func makeSources(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

        for (path, text) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }

        return root
    }

    @Test func namesTheFileAndLineThatBreaksARule() throws {
        let root = try makeSources([
            "Features/Home/HomeView.swift": "struct HomeView {\n    let item: Item\n}\n",
            "Features/Home/HomeViewModel.swift": "final class HomeViewModel {\n    let item: Item\n}\n",
        ])
        let rule = ArchitectureRule("no database object in a view", files: { $0.hasSuffix("View.swift") }, forbidding: #"\bItem\b"#)

        let found = ArchitectureCheck.violations(in: root, rules: [rule])

        #expect(found == ["Features/Home/HomeView.swift:2: no database object in a view: let item: Item"])
    }

    @Test func commentsDoNotCount() throws {
        let root = try makeSources(["A/AView.swift": "// store.revision was here\n/// store.revision too\n"])
        let rule = ArchitectureRule("revision", files: { _ in true }, forbidding: #"store\.revision"#)

        #expect(ArchitectureCheck.violations(in: root, rules: [rule]).isEmpty)
    }

    @Test func aForbiddenFolderIsReported() throws {
        let root = try makeSources(["Features/Views/HomeView.swift": "struct HomeView {}\n"])

        let found = ArchitectureCheck.violations(in: root, rules: [], forbiddenFolders: ["Views", "ViewModels"])

        #expect(found == ["Features/Views/HomeView.swift: folder Views/ is not allowed"])
    }

    @Test func readsTheModelNamesFromTheCode() throws {
        let root = try makeSources([
            "Data/Schema.swift": "@Model\nfinal class Household {\n}\n\n@Model final class Person {}\n\nstruct Row {}\n",
        ])

        #expect(ArchitectureCheck.modelTypeNames(in: root) == ["Household", "Person"])
    }
}
