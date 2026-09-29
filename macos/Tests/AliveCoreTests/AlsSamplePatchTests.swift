import XCTest
@testable import AliveCore

final class AlsSamplePatchTests: XCTestCase {
    /// A pretty-printed FileRef the way Live writes it.
    private func ref(_ parent: String = "SampleRef", rel: String, abs: String, type: Int, pack: String = "") -> String {
        Fx.fileRef(parent: parent, rel: rel, abs: abs, type: type, pack: pack, size: 1234)
    }

    private func setWith(_ refs: [String]) -> String { RescueFx.set(devices: [RescueFx.serum], refs: refs) }

    func testOnlyTheAddressedReferencesAreRewritten() throws {
        let t = makeTemp()
        // Two clips share the very same path text; only the first one is addressed. A third node
        // is a provenance reference (OriginalFileRef) that must be left alone.
        let xml = setWith([
            ref(rel: "../Elsewhere/kick.wav", abs: "/Volumes/Old/kick.wav", type: 1),
            ref(rel: "../Elsewhere/kick.wav", abs: "/Volumes/Old/kick.wav", type: 1),
            ref("OriginalFileRef", rel: "Presets/a.adv", abs: "/x/a.adv", type: 5, pack: "Core Library"),
        ])
        let src = t.als("P Project/Set.als", xml)
        let info = AlsFile.read(path: src)
        XCTAssertEqual(info.files.count, 3)

        let dst = t.sub("out.als")
        let nr = NewRef(relativePath: "Samples/Imported/kick.wav", absolutePath: "/Out/X Project_export/Samples/Imported/kick.wav")
        XCTAssertEqual(try AlsSamplePatch.rewrite(src: src, dst: dst, byIndex: [0: nr], expectedRefCount: 3), 1)

        let out = AlsFile.read(path: dst)
        XCTAssertEqual(out.files.count, 3)
        XCTAssertEqual(out.files[0].relativePath, "Samples/Imported/kick.wav")
        XCTAssertEqual(out.files[0].absolutePath, "/Out/X Project_export/Samples/Imported/kick.wav")
        XCTAssertEqual(out.files[0].relativePathType, 3)
        XCTAssertEqual(out.files[0].livePackName, "")
        XCTAssertEqual(out.files[0].originalFileSize, 1234, "size and CRC describe the same, merely moved, file")
        XCTAssertEqual(out.files[1], info.files[1])
        XCTAssertEqual(out.files[2], info.files[2])
    }

    func testEverythingButThoseValuesIsByteIdentical() throws {
        let t = makeTemp()
        let src = t.als("P Project/Set.als", setWith([
            ref(rel: "a.wav", abs: "/a/a.wav", type: 6, pack: "P"),
            ref(rel: "b.wav", abs: "/a/b.wav", type: 6),
        ]))
        let dst = t.sub("out.als")
        try AlsSamplePatch.rewrite(src: src, dst: dst, byIndex: [1: NewRef(relativePath: "Samples/Imported/b.wav", absolutePath: "/T/Samples/Imported/b.wav")], expectedRefCount: 2)
        let l0 = try RescueFx.lines(of: src), l1 = try RescueFx.lines(of: dst)
        XCTAssertEqual(l0.count, l1.count)
        let changed = zip(l0, l1).filter { $0 != $1 }.map { $0.0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(changed.count, 3)      // RelativePathType, RelativePath, Path (no pack to clear)
        XCTAssertTrue(changed.allSatisfy {
            $0.hasPrefix("<RelativePathType ") || $0.hasPrefix("<RelativePath ") || $0.hasPrefix("<Path ")
        })
    }

    func testSpecialCharactersAreEscapedAndBackslashesNormalised() throws {
        let t = makeTemp()
        let src = t.als("P Project/Set.als", setWith([ref(rel: "a.wav", abs: "/a/a.wav", type: 0)]))
        let dst = t.sub("out.als")
        let nr = NewRef(relativePath: "Samples\\Imported\\Drum & Bass \"x\" <1>.wav", absolutePath: "/T/Drum & Bass/x.wav")
        try AlsSamplePatch.rewrite(src: src, dst: dst, byIndex: [0: nr], expectedRefCount: 1)
        let out = AlsFile.read(path: dst)
        XCTAssertNil(out.error, "the document is still well-formed XML")
        XCTAssertEqual(out.files[0].relativePath, "Samples/Imported/Drum & Bass \"x\" <1>.wav")
        XCTAssertEqual(out.files[0].absolutePath, "/T/Drum & Bass/x.wav")
    }

    func testReferenceCountMismatchDeletesTheCopy() throws {
        let t = makeTemp()
        let src = t.als("P Project/Set.als", setWith([ref(rel: "a.wav", abs: "/a/a.wav", type: 0)]))
        let before = RescueFx.sha(src)
        let dst = t.sub("out.als")
        XCTAssertThrowsError(try AlsSamplePatch.rewrite(src: src, dst: dst, byIndex: [:], expectedRefCount: 5)) {
            XCTAssertEqual($0 as? AlsSamplePatchError, .refCountMismatch(found: 1, expected: 5))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst))
        XCTAssertEqual(RescueFx.sha(src), before)
    }

    func testEmptySelfClosingFileRefsAreNotCounted() throws {
        let t = makeTemp()
        let xml = setWith(["<SampleRef><FileRef /></SampleRef>", ref(rel: "a.wav", abs: "/a/a.wav", type: 0)])
        let src = t.als("s.als", xml)
        let info = AlsFile.read(path: src)
        XCTAssertEqual(info.files.count, 1)
        let dst = t.sub("out.als")
        XCTAssertEqual(try AlsSamplePatch.rewrite(src: src, dst: dst, byIndex: [0: NewRef(relativePath: "n.wav", absolutePath: "/n.wav")],
                                                 expectedRefCount: info.files.count), 1)
        XCTAssertEqual(AlsFile.read(path: dst).files[0].relativePath, "n.wav")
    }

    func testCancelRemovesTheCopy() throws {
        let t = makeTemp()
        let src = t.als("s.als", setWith([ref(rel: "a.wav", abs: "/a/a.wav", type: 0)]))
        let dst = t.sub("out.als")
        XCTAssertThrowsError(try AlsSamplePatch.rewrite(src: src, dst: dst, byIndex: [:], expectedRefCount: 1,
                                                        isCancelled: { true }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst))
    }

    func testEscapeAndSetValueHelpers() {
        XCTAssertEqual(AlsSamplePatch.escape("a&b<c>\"d\\e"), "a&amp;b&lt;c&gt;&quot;d/e")
        XCTAssertEqual(AlsSamplePatch.escape(""), "")
        XCTAssertEqual(AlsSamplePatch.setValue("<A Value=\"1\"/>", "<B Value=\"", "2"), "<A Value=\"1\"/>")
        XCTAssertEqual(AlsSamplePatch.setValue("<A Value=\"1\"/>", "<A Value=\"", "2"), "<A Value=\"2\"/>")
    }
}
