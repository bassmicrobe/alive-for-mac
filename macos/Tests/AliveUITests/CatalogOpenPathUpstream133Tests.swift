import XCTest
@testable import AliveCore
@testable import AliveUI

/// 9ce4b4b: a path inside "Song Project 2" begins with "Song Project" too, and landed on that
/// other project. Paths are matched on whole components.
final class CatalogOpenPathUpstream133Tests: XCTestCase {
    private func entry(_ path: String, modified: Double = 0) -> SetEntry {
        var e = SetEntry()
        e.path = path
        e.name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        e.modified = Date(timeIntervalSince1970: modified)
        return e
    }

    func testProjectFoldersAreMatchedOnWholePathComponents() {
        let sets = [entry("/Music/Proj/Song Project/a.als"), entry("/Music/Proj/Song Project 2/b.als")]
        func plan(_ paths: [String]) -> OpenPathPlan {
            OpenPathPlan.make(paths: paths, sets: sets, roots: ["/Music/Proj"], disabledRoots: [],
                              fileExists: { _ in true })
        }
        XCTAssertEqual(plan(["/Music/Proj/Song Project 2/Samples/kick.wav", "/Music/Proj/Song Project"]).select,
                       ["/Music/Proj/Song Project 2/b.als", "/Music/Proj/Song Project/a.als"],
                       "a file inside a project and the project folder itself each pick their own project")
        XCTAssertTrue(plan(["/Music/Proj/Song Project 3"]).select.isEmpty,
                      "a sibling that only shares a prefix with a project is nobody's")
    }
}
