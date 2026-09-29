import SwiftUI
import XCTest
import AliveCore
@testable import AliveUI

final class SetColumnsTests: XCTestCase {
    func testCatalogueHasUpstreamIdsInOrder() {
        XCTAssertEqual(SetColumnID.allCases.map(\.rawValue),
                       ["Set", "Place", "Modified", "Created", "Live", "BPM", "Key", "Tracks",
                        "PluginCount", "FileCount", "Plugins", "Files", "Tags", "Size"])
    }

    func testDefaultColumnsAreUpstreamsDefaultSetCols() {
        XCTAssertEqual(SetColumnID.defaults, [.set, .modified, .bpm, .pluginCount, .fileCount, .tags, .size])
        XCTAssertTrue(SetColumnID.set.isMandatory)
        XCTAssertFalse(SetColumnID.place.isDefault)
    }

    func testEveryColumnHasATitleInBothLanguages() {
        for column in SetColumnID.allCases {
            XCTAssertFalse(column.title.en.isEmpty)
            XCTAssertFalse(column.title.ja.isEmpty)
        }
    }

    func testLiveColumnSortsByVersionNumberNotText() {
        var a = SetEntry(), b = SetEntry()
        a.creator = "Ableton Live 9.7.1"
        b.creator = "Ableton Live 12.0"
        XCTAssertEqual(SetCompare.order(a, b, by: .live), .orderedAscending)
    }

    func testMissedColumnsSortByWhatIsLostNotByTotals() {
        var a = SetEntry(), b = SetEntry()
        a.plugins = ["x", "y", "z"]; a.missingPlugins = 0
        b.plugins = ["x"]; b.missingPlugins = 1
        XCTAssertEqual(SetCompare.order(a, b, by: .pluginsMissed), .orderedAscending)
        XCTAssertEqual(SetCompare.order(a, b, by: .pluginCount), .orderedDescending)
        a.missingFiles = 4; b.missingFiles = 1
        XCTAssertEqual(SetCompare.order(a, b, by: .filesMissed), .orderedDescending)
    }

    func testNamesSortNaturallyIgnoringCase() {
        var a = SetEntry(), b = SetEntry()
        a.name = "take 2"; b.name = "Take 10"
        XCTAssertEqual(SetCompare.order(a, b, by: .set), .orderedAscending)
    }

    func testEveryColumnComparesEqualEntriesAsSame() {
        let s = SetEntry()
        for column in SetColumnID.allCases {
            XCTAssertEqual(SetCompare.order(s, s, by: column), .orderedSame, column.rawValue)
        }
    }

    func testComparatorRoundTripsToSetSort() {
        let forward = SetSortComparator(.bpm)
        XCTAssertEqual(forward.sort, SetSort(column: .bpm, descending: false))
        var reverse = SetSortComparator(.key)
        reverse.order = .reverse
        XCTAssertEqual(reverse.sort, SetSort(column: .key, descending: true))
        var lo = SetEntry(), hi = SetEntry()
        lo.tempo = 90; hi.tempo = 140
        XCTAssertEqual(forward.compare(lo, hi), .orderedAscending)
        var backward = forward
        backward.order = .reverse
        XCTAssertEqual(backward.compare(lo, hi), .orderedDescending)
        XCTAssertEqual(backward.compare(lo, lo), .orderedSame)
    }
}

final class SetsColumnStoreTests: XCTestCase {
    private func scratch() throws -> String {
        let dir = NSTemporaryDirectory() + "alive-cols-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    func testMissingFileGivesTheDefaultLayout() throws {
        let layout = SetsColumnStore.load(dir: try scratch())
        XCTAssertNil(layout.sort)
        XCTAssertEqual(layout.version, SetsColumnLayout.currentVersion)
    }

    func testLayoutRoundTripsThroughJSON() throws {
        let dir = try scratch()
        var layout = SetsColumnLayout()
        layout.sort = SetSort(column: .size, descending: true)
        layout.columns[visibility: SetColumnID.place.id] = .visible
        layout.columns[visibility: SetColumnID.tags.id] = .hidden
        XCTAssertTrue(SetsColumnStore.save(layout, dir: dir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/sets-columns.json"))

        let back = SetsColumnStore.load(dir: dir)
        XCTAssertEqual(back.sort, layout.sort)
        XCTAssertEqual(back.columns[visibility: SetColumnID.place.id], .visible)
        XCTAssertEqual(back.columns[visibility: SetColumnID.tags.id], .hidden)
    }

    func testCorruptOrNewerFileFallsBackToDefaults() throws {
        let dir = try scratch()
        try Data("not json".utf8).write(to: URL(fileURLWithPath: dir + "/sets-columns.json"))
        XCTAssertNil(SetsColumnStore.load(dir: dir).sort)

        var newer = SetsColumnLayout()
        newer.version = 99
        newer.sort = SetSort(column: .bpm, descending: false)
        SetsColumnStore.save(newer, dir: dir)
        XCTAssertNil(SetsColumnStore.load(dir: dir).sort)
    }
}

final class SampleFolderGroupsTests: XCTestCase {
    func testGroupsByTheFirstFolderUnderTheLongestRootMostSamplesFirst() {
        let roots = ["/Users/me/Music/Ableton/User Library/Samples", "/Volumes/Packs", "/Users/me/Music"]
        let samples = [
            "/Users/me/Music/Ableton/User Library/Samples/Drums/kick.wav",
            "/Users/me/Music/Ableton/User Library/Samples/Drums/Sub/snare.wav",
            "/Users/me/Music/Ableton/User Library/Samples/loop.wav",
            "/Volumes/Packs/Cool Pack/Samples/a.wav",
            "/Volumes/Packs/Cool Pack/Samples/b.wav",
            "/Volumes/Packs/Cool Pack/c.wav",
            "/Users/me/Music/misc/x.wav",
            "/elsewhere/lost.wav",
        ]
        let groups = SampleFolderGroups.make(samples: samples, roots: roots)
        XCTAssertEqual(groups.map(\.title), ["Packs/Cool Pack", "Samples/Drums",
                                             "/Users/me/Music/Ableton/User Library/Samples", "Music/misc"])
        XCTAssertEqual(groups.map(\.count), [3, 2, 1, 1])
        XCTAssertEqual(groups[0].folder, "/Volumes/Packs/Cool Pack")
    }

    func testNoSamplesNoGroups() {
        XCTAssertTrue(SampleFolderGroups.make(samples: [], roots: ["/a"]).isEmpty)
        XCTAssertTrue(SampleFolderGroups.make(samples: ["/a/b.wav"], roots: []).isEmpty)
    }

    func testRootsIncludeLiveFoldersAndEnabledSampleRoots() {
        var env = LiveEnvironment()
        env.userLibrary = "/U/User Library"
        env.packsFolder = "/U/Packs"
        env.coreLibrary = "/A/Core Library"
        let roots = SampleFolderGroups.roots(env: env, sampleRoots: ["/S/one", "/S/off", "/u/packs"], disabled: ["/S/off"])
        XCTAssertEqual(roots, ["/U/User Library/Samples", "/U/Packs", "/A/Core Library", "/S/one"])
    }
}

final class TagInputTests: XCTestCase {
    func testACommaClosesTagsAndKeepsTheTail() {
        let r = TagInput.absorb(draft: "drum, vocal, be", into: ["bass"])
        XCTAssertEqual(r.tags, ["bass", "drum", "vocal"])
        XCTAssertEqual(r.draft, " be")
        XCTAssertEqual(TagInput.absorb(draft: "kick,", into: []).draft, "")
        XCTAssertEqual(TagInput.absorb(draft: "no comma", into: ["a"]).tags, ["a"])
    }

    func testRepeatsAreIgnoredIgnoringCase() {
        XCTAssertEqual(TagInput.merge("Drum, drum,  , vocal", into: ["DRUM"]), ["DRUM", "vocal"])
        XCTAssertEqual(TagInput.commit(draft: "  lead ", into: ["a"]), ["a", "lead"])
    }
}

final class RootsDraftTests: XCTestCase {
    func testPageEditing() {
        var page = RootsDraft.Page(roots: ["/a", "/b"], disabled: ["/b"])
        XCTAssertTrue(page.isEnabled("/a"))
        XCTAssertFalse(page.isEnabled("/B"))
        XCTAssertFalse(page.add("/A"), "already there (case-insensitive)")
        XCTAssertTrue(page.add("/c"))
        page.set("/c", enabled: false)
        XCTAssertFalse(page.isEnabled("/c"))
        page.set("/b", enabled: true)
        XCTAssertTrue(page.isEnabled("/b"))
        page.remove("/c")
        XCTAssertEqual(page.roots, ["/a", "/b"])
        XCTAssertTrue(page.disabled.isEmpty)
    }

    func testAddingAgainSwitchesADisabledFolderBackOn() {
        var page = RootsDraft.Page(roots: ["/a"], disabled: ["/a"])
        XCTAssertFalse(page.add("/a"))
        XCTAssertTrue(page.isEnabled("/a"))
    }

    func testNestedFoldersCountAsPartOfTheirParent() {
        var page = RootsDraft.Page(roots: ["/lib", "/lib/drums", "/other"], disabled: [])
        XCTAssertTrue(page.isNested("/lib/drums"))
        XCTAssertFalse(page.isNested("/lib"))
        XCTAssertFalse(page.isNested("/other"))
        page.set("/lib", enabled: false)
        XCTAssertFalse(page.isNested("/lib/drums"), "the parent is switched off, so the child is walked on its own")
    }

    @MainActor
    func testChangeTrackingAndApplyRules() {
        let draft = RootsDraft(kind: .projects, projects: .init(roots: ["/a"], disabled: []), samples: .init())
        XCTAssertFalse(draft.hasChanges)
        XCTAssertTrue(draft.canApply)
        draft.kind = .samples
        draft.page.add("/s")
        XCTAssertTrue(draft.samplesChanged)
        XCTAssertFalse(draft.projectsChanged)
        XCTAssertEqual(draft.samples.roots, ["/s"])
        draft.kind = .projects
        draft.page.remove("/a")
        XCTAssertFalse(draft.canApply)
    }

    @MainActor
    func testCountsAreWalkedInTheBackgroundAndKeptPerPage() async throws {
        let dir = NSTemporaryDirectory() + "alive-roots-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir + "/P Project", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir + "/P Project/a.als", contents: Data("x".utf8))
        FileManager.default.createFile(atPath: dir + "/P Project/b.als", contents: Data("x".utf8))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }

        let draft = RootsDraft(kind: .projects, projects: .init(roots: [dir, "/nope/nothing"], disabled: []), samples: .init())
        draft.ensureCount(dir)
        draft.ensureCount("/nope/nothing")
        for _ in 0..<100 where draft.count(for: dir) == nil || draft.count(for: "/nope/nothing") == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(draft.count(for: dir), 2)
        XCTAssertEqual(draft.count(for: "/nope/nothing"), -1)
        draft.kind = .samples
        XCTAssertNil(draft.count(for: dir), "samples of the same folder are counted separately")
        draft.cancelCounting()
    }
}

final class RootCounterTests: XCTestCase {
    func testCountsOnlyLoadableSamples() throws {
        let dir = NSTemporaryDirectory() + "alive-samples-" + UUID().uuidString
        let fm = FileManager.default
        try fm.createDirectory(atPath: dir + "/Drums/Sub", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dir + "/Thing.app/Contents", withIntermediateDirectories: true)
        addTeardownBlock { try? fm.removeItem(atPath: dir) }
        for f in ["k.wav", "Drums/s.AIF", "Drums/Sub/t.mp3", "Drums/notes.txt", "Drums/.hidden.wav", "Thing.app/Contents/x.wav"] {
            fm.createFile(atPath: dir + "/" + f, contents: Data("x".utf8))
        }
        XCTAssertEqual(RootCounter.countSamples(in: dir), 3)
        XCTAssertEqual(RootCounter.countSamples(in: dir + "/missing"), -1)
        XCTAssertEqual(RootCounter.countSets(in: dir + "/missing"), -1)
        XCTAssertEqual(RootCounter.countSets(in: dir), 0)
    }

    func testCancelledWalkStopsEarly() throws {
        let dir = NSTemporaryDirectory() + "alive-samples-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        FileManager.default.createFile(atPath: dir + "/k.wav", contents: Data("x".utf8))
        XCTAssertEqual(RootCounter.countSamples(in: dir, isCancelled: { true }), 0)
    }
}

final class LiveFolderSuggestionsTests: XCTestCase {
    func testPlacesThenLibrariesWithoutRepeatsAndProjectsMarked() {
        var env = LiveEnvironment()
        env.places = [LivePlace(name: "Projects", path: "/M/Projects"), LivePlace(name: "Loops", path: "/M/Loops")]
        env.userLibrary = "/M/Ableton/User Library"
        env.packsFolder = "/M/Loops"          // already a Place: not offered twice
        env.coreLibrary = "/A/Core Library"
        let list = LiveFolderSuggestions.make(env: env, projectRoots: ["/M/Projects/Songs"], isDirectory: { _ in true })
        XCTAssertEqual(list.map(\.title), ["Projects", "Loops", "User Library", "Core Library"])
        XCTAssertEqual(list.map(\.isProjects), [true, false, false, false])
        XCTAssertEqual(list.map(\.startsGroup), [false, false, true, false])
    }

    func testMissingFoldersAreLeftOut() {
        var env = LiveEnvironment()
        env.userLibrary = "/nope/User Library"
        XCTAssertTrue(LiveFolderSuggestions.make(env: env, projectRoots: [], isDirectory: { _ in false }).isEmpty)
    }

    func testCovers() {
        XCTAssertTrue(LiveFolderSuggestions.covers(root: "/a/b", path: "/a/b/c"))
        XCTAssertTrue(LiveFolderSuggestions.covers(root: "/a/b/", path: "/A/B"))
        XCTAssertFalse(LiveFolderSuggestions.covers(root: "/a/b", path: "/a/bc"))
    }
}

final class PluginStatusTests: XCTestCase {
    func testAnEmptyInventoryIsUnknownNotMissing() {
        XCTAssertFalse(PluginStatus.isKnown(PluginInventory()))
        var inventory = PluginInventory()
        var plugin = InstalledPlugin()
        plugin.name = "Serum"
        plugin.uid = "vst3:abc"
        inventory.add(plugin)
        XCTAssertTrue(PluginStatus.isKnown(inventory))
    }
}
