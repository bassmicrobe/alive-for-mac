import XCTest
@testable import AliveCore
@testable import AliveUI

@MainActor
final class SamplesLookupTests: XCTestCase {
    private func library(_ entries: [(String, [String])]) -> SampleIndex {
        var index = SampleIndex()
        for (path, names) in entries {
            var folder = SampleFolder()
            folder.path = path
            for name in names {
                var file = SampleFile()
                file.name = name
                file.folder = index.folders.count
                folder.files.append(index.files.count)
                index.files.append(file)
            }
            index.folders.append(folder)
        }
        return index
    }

    func testFileLookupKeepsFolderIdentityAndCaseInsensitiveNames() {
        let app = AppModel(dataDir: makeHomeScratch().path)
        let model = app.samples
        model.adopt(library([("/Lib/Kicks", ["Kick.WAV"]), ("/Lib/Snares", ["kick.wav"])]))
        XCTAssertEqual(model.kind(ofRow: "/LIB/KICKS"), .folder(0))
        XCTAssertEqual(model.kind(ofRow: "/lib/kicks/kick.wav"), .file(0))
        XCTAssertEqual(model.kind(ofRow: "/lib/snares/KICK.WAV"), .file(1))
        XCTAssertNil(model.kind(ofRow: "/lib/kicks/missing.wav"))
        XCTAssertNil(model.kind(ofRow: "/elsewhere/kick.wav"))
        XCTAssertNil(model.kind(ofRow: nil))
    }

    func testCaseOnlyFolderNamesPreserveAllFiles() {
        let app = AppModel(dataDir: makeHomeScratch().path)
        let model = app.samples
        model.adopt(library([("/Lib/Kicks", ["kick.wav", "same.wav"]),
                             ("/Lib/kicks", ["snare.wav", "same.wav"])]))
        XCTAssertEqual(model.kind(ofRow: "/Lib/Kicks/kick.wav"), .file(0))
        XCTAssertEqual(model.kind(ofRow: "/Lib/kicks/snare.wav"), .file(2))
        XCTAssertEqual(model.kind(ofRow: "/Lib/Kicks/same.wav"), .file(3))
    }

    func testReplacingIndexInvalidatesFileLookup() {
        let app = AppModel(dataDir: makeHomeScratch().path)
        let model = app.samples
        model.adopt(library([("/Lib/Drums", ["kick.wav"])]))
        XCTAssertEqual(model.kind(ofRow: "/Lib/Drums/kick.wav"), .file(0))
        model.adopt(library([("/Lib/Drums", ["snare.wav", "kick.wav"])]))
        XCTAssertEqual(model.kind(ofRow: "/Lib/Drums/kick.wav"), .file(1))
        model.adopt(library([("/Lib/Drums", ["snare.wav"])]))
        XCTAssertNil(model.kind(ofRow: "/Lib/Drums/kick.wav"))
    }

    func testFolderNavigationInLargeLibrary() {
        let app = AppModel(dataDir: makeHomeScratch().path)
        let model = app.samples
        let names = (0..<100_000).map { "sample-\($0).wav" }
        model.adopt(library([("/Lib/Large", names), ("/Lib/Drums", ["kick.wav"])]))
        let start = Date()
        XCTAssertEqual(model.kind(ofRow: "/Lib/Large"), .folder(0))
        XCTAssertEqual(model.kind(ofRow: "/Lib/Drums/kick.wav"), .file(100_000))
        print("SAMPLE LOOKUP: folder and small-folder selection in 100001-file library: \(Date().timeIntervalSince(start)) s")
    }
}
