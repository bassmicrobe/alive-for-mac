import XCTest
@testable import AliveCore
@testable import AliveUI

@MainActor
final class SamplesFormatTests: XCTestCase {
    override func setUp() {
        Localizer.shared.preference = .en
    }

    override func tearDown() {
        Localizer.shared.preference = .system
    }

    func testSizesFollowUpstreamsRules() {
        XCTAssertEqual(SampleFormat.megabytes(0), "")
        XCTAssertEqual(SampleFormat.megabytes(5 * 1024 * 1024), "5.0 MB")
        XCTAssertEqual(SampleFormat.megabytes(297 * 1024 * 1024), "297 MB")
        XCTAssertEqual(SampleFormat.megabytes(Int64(1.5 * 1024 * 1024 * 1024)), "1.50 GB")
        XCTAssertEqual(SampleFormat.megabytes(Int64(120) * 1024 * 1024 * 1024), "120 GB")
        XCTAssertEqual(SampleFormat.sampleSize(0), "")
        XCTAssertEqual(SampleFormat.sampleSize(1), "1 KB")
        XCTAssertEqual(SampleFormat.sampleSize(300 * 1024), "300 KB")
        XCTAssertEqual(SampleFormat.sampleSize(3 * 1024 * 1024), "3.0 MB")
    }

    func testDatesNumbersSharesAndDurations() {
        XCTAssertEqual(SampleFormat.day(nil), "")
        XCTAssertEqual(SampleFormat.day(.distantPast), "")
        var c = DateComponents(); c.year = 2026; c.month = 8; c.day = 28; c.hour = 12
        XCTAssertEqual(SampleFormat.day(Calendar.current.date(from: c)), "2026-08-28")
        XCTAssertEqual(SampleFormat.number(31807, locale: Locale(identifier: "en_US")), "31,807")
        XCTAssertEqual(SampleFormat.share(5, of: 612), "0.8%")
        XCTAssertEqual(SampleFormat.share(477, of: 31311), "1.5%")
        XCTAssertEqual(SampleFormat.share(50, of: 100), "50%")
        XCTAssertEqual(SampleFormat.share(1, of: 0), "")
        XCTAssertEqual(SampleFormat.duration(ms: 0), "")
        XCTAssertEqual(SampleFormat.duration(ms: 4500), "0:04.5")
        XCTAssertEqual(SampleFormat.duration(ms: 83_000), "1:23")
        XCTAssertEqual(SampleFormat.duration(ms: 3_723_000), "1:02:03")
    }

    func testFormatLine() {
        var h = AudioHeader()
        h.rate = 44100; h.bits = 24; h.channels = 2
        XCTAssertEqual(SampleFormat.format(h), "44.1 kHz · 24-bit · stereo")
        h.rate = 48000; h.channels = 1
        XCTAssertEqual(SampleFormat.format(h), "48 kHz · 24-bit · mono")
        h.channels = 6
        XCTAssertEqual(SampleFormat.format(h), "48 kHz · 24-bit · 6 channels")
        XCTAssertEqual(SampleFormat.format(AudioHeader()), "")
        Localizer.shared.preference = .ja
        h.channels = 2
        XCTAssertEqual(SampleFormat.format(h), "48 kHz · 24 ビット · ステレオ")
    }

    func testTheNameColumnIsCalledAfterWhatTheViewLists() {
        XCTAssertEqual(SampleFormat.nameTitle(lens: .all, isFlat: false), "Folder")
        XCTAssertEqual(SampleFormat.nameTitle(lens: .all, isFlat: true), "Name")
        XCTAssertEqual(SampleFormat.nameTitle(lens: .neverUsed, isFlat: true), "Folder")
        XCTAssertEqual(SampleFormat.nameTitle(lens: .mostUsed, isFlat: true), "Sample")
        XCTAssertEqual(SampleFormat.nameTitle(lens: .duplicates, isFlat: true), "Sample")
        for c in SampleColumn.allCases { XCTAssertFalse(SampleFormat.title(of: c, lens: .all, isFlat: true).isEmpty) }
        for l in SampleLens.allCases { XCTAssertFalse(SampleFormat.title(of: l).isEmpty) }
    }

    // MARK: cells and counter

    private func library() throws -> (SampleIndex, String) {
        let base = NSTemporaryDirectory() + "alive-cells-" + UUID().uuidString
        addTeardownBlock { try? FileManager.default.removeItem(atPath: base) }
        try FileManager.default.createDirectory(atPath: base + "/Lib/Kicks", withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2048).write(to: URL(fileURLWithPath: base + "/Lib/Kicks/a.wav"))
        try Data(repeating: 2, count: 4096).write(to: URL(fileURLWithPath: base + "/Lib/Kicks/b.wav"))
        return (SampleIndex.build(roots: [base + "/Lib"], disabled: []), base + "/Lib")
    }

    func testCellsShowDashesNeverAndUnknown() throws {
        let (idx, root) = try library()
        let folderRow = SampleRow(id: "k", kind: .folder(1), depth: 1)
        let fileRow = SampleRow(id: "a", kind: .file(idx.files.firstIndex { $0.name == "a.wav" }!), depth: 2)

        var set = SetEntry()
        set.path = root + "/../Music/S Project/s.als"
        set.modified = Date(timeIntervalSince1970: 1_756_000_000)
        set.samples = [root + "/Kicks/a.wav"]
        let used = SampleUsage.compute(index: idx, sets: [set])
        let cells = SampleCells(index: idx, usage: used, copies: .empty, unknown: false)
        XCTAssertEqual(cells.text(.name, folderRow), "Kicks")
        XCTAssertEqual(cells.text(.samples, folderRow), "2")
        XCTAssertEqual(cells.text(.used, folderRow), "1")
        XCTAssertEqual(cells.text(.projects, folderRow), "1")
        XCTAssertFalse(cells.text(.lastUsed, folderRow).isEmpty)
        XCTAssertEqual(cells.text(.size, fileRow), "2 KB")
        XCTAssertEqual(cells.text(.samples, fileRow), "")
        XCTAssertEqual(cells.text(.copies, fileRow), "")
        XCTAssertEqual(cells.text(.location, folderRow), SampleIndex.norm(root))
        XCTAssertFalse(cells.isDim(fileRow))
        XCTAssertFalse(cells.isDim(folderRow))

        let unused = SampleCells(index: idx, usage: .empty, copies: .empty, unknown: false)
        XCTAssertEqual(unused.text(.used, folderRow), "—")
        XCTAssertEqual(unused.text(.lastUsed, fileRow), "never")
        XCTAssertTrue(unused.isDim(fileRow))

        let unknown = SampleCells(index: idx, usage: .empty, copies: .empty, unknown: true)
        XCTAssertEqual(unknown.text(.projects, fileRow), "…")
        XCTAssertEqual(unknown.text(.lastUsed, folderRow), "…")
        XCTAssertFalse(unknown.isDim(fileRow), "nothing is dim while the sets are being read")
    }

    func testCounterTellsTheStateOfTheList() throws {
        let (idx, _) = try library()
        let tree = SampleListing(rows: [], matches: 0, isFlat: false)
        XCTAssertEqual(SampleCounter.text(isScanning: true, found: 1234, listing: tree, lens: .all, hasQuery: false,
                                          index: idx, copies: .empty), "Indexing samples… 1,234")
        XCTAssertTrue(SampleCounter.text(isScanning: false, found: 0, listing: tree, lens: .all, hasQuery: false,
                                         index: idx, copies: .empty).hasPrefix("2 samples · "))
        let row = SampleRow(id: "x", kind: .folder(0), depth: 0)
        let flat = SampleListing(rows: [row, row], matches: 2, isFlat: true)
        XCTAssertEqual(SampleCounter.text(isScanning: false, found: 0, listing: flat, lens: .mostUsed, hasQuery: false,
                                          index: idx, copies: .empty), "2 shown")
        let cut = SampleListing(rows: [row], matches: 9000, isFlat: true)
        XCTAssertEqual(SampleCounter.text(isScanning: false, found: 0, listing: cut, lens: .all, hasQuery: true,
                                          index: idx, copies: .empty), "first 1 of 9,000")
    }

    // MARK: suggestions

    func testSuggestionsSkipProjectFoldersExistingRootsAndMissingFolders() {
        var env = LiveEnvironment()
        env.places = [LivePlace(name: "Drums", path: "/m/Drums"), LivePlace(name: "Projects", path: "/m/Projects"),
                      LivePlace(name: "Nested", path: "/m/Projects/Old"), LivePlace(name: "Gone", path: "/m/Gone")]
        env.userLibrary = "/m/Ableton/User Library"
        env.packsFolder = "/m/Ableton/Packs"
        env.coreLibrary = "/Applications/Live.app/Core Library"
        let exists: (String) -> Bool = { $0 != "/m/Gone" }

        let all = SampleRootSuggestions.make(env: env, projectRoots: ["/m/Projects"], existing: [], isDirectory: exists)
        XCTAssertEqual(all.map(\.path), ["/m/Drums", "/m/Ableton/User Library", "/m/Ableton/Packs",
                                         "/Applications/Live.app/Core Library"])
        XCTAssertEqual(all.map(\.kind), [.place("Drums"), .userLibrary, .packs, .coreLibrary])

        let some = SampleRootSuggestions.make(env: env, projectRoots: ["/m/Projects"], existing: ["/m/Ableton"], isDirectory: exists)
        XCTAssertEqual(some.map(\.path), ["/m/Drums", "/Applications/Live.app/Core Library"],
                       "folders inside an existing root are already indexed")
        XCTAssertEqual(all[1].title, "User Library")
        XCTAssertEqual(SampleRootSuggestion(kind: .packs, path: NSHomeDirectory() + "/Music/Packs").display(), "~/Music/Packs")
    }

    func testPacksComeFromTheirParentsWhenNoPacksFolderIsKnown() {
        var env = LiveEnvironment()
        env.setPack("Drone Lab", "/m/Ableton/Factory Packs/Drone Lab")
        env.setPack("Core Library", "/Applications/Live.app/Core Library")
        env.userLibrary = ""
        let s = SampleRootSuggestions.make(env: env, projectRoots: [], existing: [], isDirectory: { _ in true })
        XCTAssertEqual(s.map(\.path), ["/m/Ableton/Factory Packs"])
    }
}
