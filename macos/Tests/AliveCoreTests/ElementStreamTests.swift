import XCTest
@testable import AliveCore

/// Unit tests for the byte-level tokenizer plus differential tests against the original
/// XMLParser engine (`ReferenceElementStream`).
final class ElementStreamTests: XCTestCase {
    private func run(_ xml: String) -> StreamResult { StreamEngines.newEngine(Data(xml.utf8)) }
    private func run(bytes: [UInt8]) -> StreamResult { StreamEngines.newEngine(Data(bytes)) }

    private func starts(_ r: StreamResult) -> [String] {
        r.events.compactMap { if case let .start(n, _, _, _) = $0 { return n } else { return nil } }
    }

    private func attrs(_ r: StreamResult, _ index: Int = 0) -> [String: String] {
        let all = r.events.compactMap { e -> [String: String]? in if case let .start(_, a, _, _) = e { return a } else { return nil } }
        return all[index]
    }

    // MARK: constructs

    func testDeclarationCommentsPIAndDoctypeAreSkipped() {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!-- c > < -->\n<!DOCTYPE a [ <!ENTITY x \"y>\"> <!-- ] --> ]>\n"
            + "<?pi data ?><a><!-- <b/> --><?p x?><b/></a>\n<!-- tail -->\n"
        let r = run(xml)
        XCTAssertNil(r.error)
        XCTAssertEqual(starts(r), ["a", "b"])
    }

    func testSelfClosingFiresStartThenEndWithDepths() {
        let r = run("<a><b/><c x='1'></c></a>")
        XCTAssertNil(r.error)
        XCTAssertEqual(r.events, [
            .start(name: "a", attrs: [:], parent: "", depth: 0),
            .start(name: "b", attrs: [:], parent: "a", depth: 1), .end(1),
            .start(name: "c", attrs: ["x": "1"], parent: "a", depth: 1), .end(1),
            .end(0),
        ])
    }

    func testCdataAndTextAreIgnored() {
        let r = run("<a>hello <![CDATA[ <b> ]]> world<b Value=\"1\"/>\n<Buffer>\n  00FF00FF\n</Buffer></a>")
        XCTAssertNil(r.error)
        XCTAssertEqual(starts(r), ["a", "b", "Buffer"])
    }

    func testQuotesAndWhitespaceAroundAttributes() {
        let r = run("<a\n\tx = \"1\"\r\n y='say \"hi\"' z=\"it's\"\n/>")
        XCTAssertNil(r.error)
        XCTAssertEqual(attrs(r), ["x": "1", "y": "say \"hi\"", "z": "it's"])
    }

    func testEndTagWithTrailingWhitespace() {
        XCTAssertNil(run("<a><b></b ></a\n>").error)
    }

    func testEntityDecodingInAttributes() {
        let r = run("<a v=\"&amp;&lt;&gt;&quot;&apos; &#65;&#x42;&#x3042;&#128512;\"/>")
        XCTAssertNil(r.error)
        XCTAssertEqual(attrs(r)["v"], "&<>\"' AB\u{3042}\u{1F600}")
    }

    func testAttributeWhitespaceNormalisation() {
        let r = run("<a v=\"x\ty\nz\r\nw&#10;\"/>")
        XCTAssertNil(r.error)
        XCTAssertEqual(attrs(r)["v"], "x y z w\n")
    }

    func testUtf8NamesAndValues() {
        let r = run("<セット 名前=\"日本語のファイル 🎹.als\"><子/></セット>")
        XCTAssertNil(r.error)
        XCTAssertEqual(starts(r), ["セット", "子"])
        XCTAssertEqual(attrs(r)["名前"], "日本語のファイル 🎹.als")
    }

    func testBomIsSkipped() {
        let r = run(bytes: [0xEF, 0xBB, 0xBF] + Array("<a><b/></a>".utf8))
        XCTAssertNil(r.error)
        XCTAssertEqual(starts(r), ["a", "b"])
    }

    func testDepthsAndParentsInNesting() {
        let r = run("<a><b><c/></b><d/></a>")
        XCTAssertEqual(r.events, [
            .start(name: "a", attrs: [:], parent: "", depth: 0),
            .start(name: "b", attrs: [:], parent: "a", depth: 1),
            .start(name: "c", attrs: [:], parent: "b", depth: 2), .end(2),
            .end(1),
            .start(name: "d", attrs: [:], parent: "a", depth: 1), .end(1),
            .end(0),
        ])
    }

    func testAttributeAccessorsUsedByParsers() {
        var seen: XMLTag?
        var vals: (Int, Double, Bool, String?)?
        let s = ElementStream(onStart: { t in
            seen = t
            vals = (t.int(), t.double(), t.bool, t.attrs["Missing"])
        }, onEnd: { _ in })
        XCTAssertNil(s.run(Data("<a Value=\"true\" Other=\"x\"/>".utf8)))
        XCTAssertEqual(seen?.name, "a")
        XCTAssertEqual(vals?.0, 0)
        XCTAssertEqual(vals?.2, true)
        XCTAssertNil(vals?.3)
    }

    // MARK: malformed input

    func testMalformedInputsReportAnError() {
        let bad = [
            "", "   ", "<a>", "<a><b></a>", "<a></b>", "<a", "<a x", "<a x=", "<a x=\"1", "<a x='1",
            "<a x=1/>", "<a x=\"1\"y=\"2\"/>", "<a x=\"1\" x=\"2\"/>", "<a>&", "</a>", "<a/><b/>", "text<a/>",
            "<a/>text", "<!-- unterminated", "<a><!-- x </a>", "<a><![CDATA[ x </a>", "<?pi", "<a x=\"&bogus;\"/>",
            "<a x=\"&#xZZ;\"/>", "<a x=\"&#0;\"/>", "<a x=\"a<b\"/>", "<a/ >", "< a/>", "<1a/>", "<a></a", "<a></a x>",
            "<!DOCTYPE a [ <a/>", "<a><", "<a><!", "<a></", "<a x=\"&amp\"/>", "<![CDATA[x]]><a/>", "\u{EF}\u{BB}",
        ]
        for xml in bad {
            let r = run(xml)
            XCTAssertNotNil(r.error, "expected an error for: \(xml.debugDescription)")
        }
    }

    func testTruncatedDocumentStillDeliversEarlierEvents() {
        let r = run("<a><b Value=\"1\"/><c>")
        XCTAssertNotNil(r.error)
        XCTAssertEqual(starts(r), ["a", "b", "c"])
    }

    func testEmptyDataReturnsError() {
        XCTAssertNotNil(ElementStream(onStart: { _ in }, onEnd: { _ in }).run(Data()))
    }

    func testEveryPrefixOfAValidDocumentTerminatesWithoutCrashing() {
        let doc = Array(Fx.simpleSet().utf8)
        for n in 0..<doc.count {
            let r = run(bytes: Array(doc[0..<n]))
            if n < doc.count { XCTAssertNotNil(r.error, "prefix of \(n) bytes parsed cleanly") }
        }
        XCTAssertNil(run(bytes: doc).error)
    }

    func testRandomByteCorruptionNeverCrashesOrHangs() {
        var rng = SplitMix(seed: 7)
        let doc = Array(GeneratedXML.document(&rng, elements: 60).utf8)
        for _ in 0..<3000 {
            var d = doc
            for _ in 0..<(1 + rng.next(4)) {
                switch rng.next(3) {
                case 0: d[rng.next(d.count)] = UInt8(truncatingIfNeeded: rng.next(256))
                case 1: d.remove(at: rng.next(d.count))
                default: d.insert(UInt8(truncatingIfNeeded: rng.next(256)), at: rng.next(d.count))
                }
            }
            _ = run(bytes: d)   // must return, error or not
        }
    }

    // MARK: differential (small)

    private func assertSame(_ xml: String, file: StaticString = #filePath, line: UInt = #line) {
        assertSame(Data(xml.utf8), label: xml.prefix(120).description, file: file, line: line)
    }

    private func assertSame(_ data: Data, label: String, file: StaticString = #filePath, line: UInt = #line) {
        let a = StreamEngines.newEngine(data), b = StreamEngines.reference(data)
        XCTAssertEqual(a.error == nil, b.error == nil, "error agreement for \(label): new=\(a.error ?? "ok") ref=\(b.error ?? "ok")",
                       file: file, line: line)
        if a.error == nil, b.error == nil {
            XCTAssertEqual(a.events, b.events, "events differ for \(label)", file: file, line: line)
        }
    }

    func testDifferentialOnHandwrittenConstructs() {
        let docs = [
            "<a/>", "<a></a>", "<?xml version=\"1.0\"?><a x='1' y=\"2\"><b/></a>", "<a><!-- c --><b/><?p?></a>",
            "<a>t<![CDATA[x<y]]>t</a>", "<a v=\"&amp;&#65;&#x42;\"/>", "<セット 名前=\"日本語\"><子/></セット>",
            "<a\n x = '1'\n/>", "<a v=\"x\ty\nz\r\nw\"/>", "<a><b>\n\t</b>\n</a>\n",
            Fx.simpleSet(), Fx.als(live: Fx.tracks(Fx.track("AudioTrack", name: "A &amp; B") + Fx.vst3(name: "V", fields: [1, 2, 3, 4]))),
        ]
        for d in docs { assertSame(d) }
        assertSame(Data([0xEF, 0xBB, 0xBF] + Array("<a><b/></a>".utf8)), label: "bom")
    }

    func testDifferentialOnGeneratedDocuments() {
        var rng = SplitMix(seed: 42)
        for i in 0..<1500 {
            let doc = GeneratedXML.document(&rng, elements: 1 + rng.next(80))
            assertSame(Data(doc.utf8), label: "generated #\(i): \(doc.prefix(200))")
        }
    }

    /// Byte-level mutations of valid documents: where both engines accept, the events must match;
    /// the two must also agree on accept/reject (control characters in text and other
    /// exotic XML-Char rules are not checked, the mutator does not produce them).
    func testDifferentialOnMutatedDocuments() {
        var rng = SplitMix(seed: 99)
        var disagreements: [String] = []
        for _ in 0..<4000 {
            var d = Array(GeneratedXML.document(&rng, elements: 1 + rng.next(30)).utf8)
            // Leave the XML declaration alone: libxml validates its pseudo-attributes, the tokenizer
            // (deliberately) treats it as an opaque processing instruction.
            var declEnd = 0
            if d.count > 2, let k = zip(d, d.dropFirst()).enumerated().first(where: { $0.element == (0x3F, 0x3E) }) {
                declEnd = k.offset + 2
            }
            let at = declEnd + rng.next(d.count - declEnd)
            if rng.next(2) == 0 { d.removeSubrange(at...) } else { d[at] = Array("<>&\"'/= x".utf8)[rng.next(9)] }
            let data = Data(d)
            let a = StreamEngines.newEngine(data), b = StreamEngines.reference(data)
            if a.error == nil, b.error == nil {
                XCTAssertEqual(a.events, b.events)
            } else if (a.error == nil) != (b.error == nil) {
                disagreements.append("new=\(a.error ?? "ok") ref=\(b.error ?? "ok") :: \(String(decoding: d, as: UTF8.self).debugDescription)")
            }
        }
        for d in disagreements.prefix(10) { print("MUTATION DISAGREEMENT: \(d)") }
        XCTAssertEqual(disagreements.count, 0, "engines disagree on corrupted documents")
    }

    // MARK: AlsInfo through both engines (fixtures)

    func testAlsInfoIdenticalOnFixtures() {
        let plug = Fx.vst3(name: "FabFilter Pro-Q 4", fields: [-313016974, 1549813374, -1504849164, 7703407],
                           browser: "query:Plugins#VST3:FabFilter:Pro-Q%203")
        let sets = [
            Fx.simpleSet(tempo: 128),
            Fx.als(live: Fx.tracks(Fx.track("AudioTrack", extra: plug + Fx.vst2(name: "Drums", uniqueId: 1234))
                + Fx.track("MidiTrack", extra: Fx.au(name: "X", vendor: "V", type: 1635085670, sub: -1, mfr: 1349087086)
                + Fx.fileRef(rel: "Samples/a.wav", abs: "/x/a.wav", type: 3, pack: "P", size: 10))) + Fx.main(tempo: 90.5)
                + Fx.scale(root: 1, name: 0, flat: true)),
        ]
        for xml in sets {
            let data = Data(xml.utf8)
            AlsInfoComparison.assertEqual(AlsFile.parse(xml: data), StreamEngines.referenceAls(xml: data), label: "fixture", testCase: self)
        }
    }
}

/// Field-by-field AlsInfo comparison (error text is engine specific: only its presence counts).
enum AlsInfoComparison {
    @discardableResult
    static func differences(_ a: AlsInfo, _ b: AlsInfo) -> [String] {
        var d: [String] = []
        if a.creator != b.creator { d.append("creator \(a.creator) vs \(b.creator)") }
        if a.tempo != b.tempo { d.append("tempo \(a.tempo) vs \(b.tempo)") }
        if a.scaleRoot != b.scaleRoot || a.scaleIndex != b.scaleIndex || a.preferFlat != b.preferFlat { d.append("key") }
        if (a.audioTracks, a.midiTracks, a.groupTracks) != (b.audioTracks, b.midiTracks, b.groupTracks) { d.append("tracks") }
        if a.plugins != b.plugins { d.append("plugins") }
        if a.files != b.files { d.append("files") }
        if (a.error == nil) != (b.error == nil) { d.append("error \(a.error ?? "nil") vs \(b.error ?? "nil")") }
        return d
    }

    static func assertEqual(_ a: AlsInfo, _ b: AlsInfo, label: String, testCase: XCTestCase,
                            file: StaticString = #filePath, line: UInt = #line) {
        let d = differences(a, b)
        XCTAssertTrue(d.isEmpty, "AlsInfo differs for \(label): \(d)", file: file, line: line)
    }
}

/// Deterministic RNG so a failing fuzz case reproduces.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func nextU64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func next(_ n: Int) -> Int { Int(nextU64() % UInt64(max(n, 1))) }
    mutating func pick<T>(_ a: [T]) -> T { a[next(a.count)] }
}

/// Random well-formed documents that exercise every construct the tokenizer handles.
enum GeneratedXML {
    static let names = ["A", "Note", "Value", "x:y", "a-b.c", "_u", "セット", "名前_1", "Ünï", "ns:Tag9"]
    static let values = ["", "1", "-3.5", "true", "Samples/a b.wav", "&amp;", "a&lt;b&gt;c", "&quot;q&quot;", "&apos;s&apos;",
                         "&#65;&#x3042;", "日本語 🎹", "tab\there", "line\nbreak", "cr\r\nlf", "it's", "say \"hi\"", "C:\\Users\\x", "  spaced  "]
    static let spaces = [" ", "  ", "\n", "\t", " \r\n ", "\n\t "]

    static func document(_ rng: inout SplitMix, elements: Int) -> String {
        var s = ""
        if rng.next(3) == 0 { s += "\u{FEFF}" }
        if rng.next(2) == 0 { s += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + rng.pick(["", "\n", " "]) }
        if rng.next(4) == 0 { s += "<!-- lead > comment -->\n" }
        if rng.next(6) == 0 { s += "<!DOCTYPE root>\n" }
        var budget = elements
        s += element(&rng, &budget, depth: 0, forceOpen: true)
        if rng.next(4) == 0 { s += "\n<!-- trailing -->\n" }
        return s
    }

    private static func element(_ rng: inout SplitMix, _ budget: inout Int, depth: Int, forceOpen: Bool = false) -> String {
        budget -= 1
        let name = rng.pick(names)
        var s = "<" + name
        var used = Set<String>()
        for _ in 0..<rng.next(4) {
            let an = rng.pick(names)
            if !used.insert(an).inserted { continue }
            let q = rng.next(2) == 0 ? "\"" : "'"
            var v = rng.pick(values)
            if q == "'" { v = v.replacingOccurrences(of: "'", with: "&apos;") } else { v = v.replacingOccurrences(of: "\"", with: "&quot;") }
            s += rng.pick(spaces) + an + rng.pick(["", " ", "\n"]) + "=" + rng.pick(["", " "]) + q + v + q
        }
        if !forceOpen, budget <= 0 || depth > 12 || rng.next(3) == 0 {
            if rng.next(2) == 0 { return s + rng.pick(["", " ", "\n"]) + "/>" }
            return s + "></" + name + rng.pick(["", " "]) + ">"
        }
        s += rng.pick(["", " "]) + ">"
        for _ in 0..<(1 + rng.next(4)) where budget > 0 {
            switch rng.next(8) {
            case 0: s += rng.pick(["text", "\n\t", "a > b", " 日本語 ", "0A0B0C0D"])
            case 1: s += "<!-- c " + rng.pick(["<x/>", "]]>", "&"]) + " -->"
            case 2: s += "<![CDATA[ <not/> & ]]>"
            case 3: s += "<?target some data?>"
            default: s += element(&rng, &budget, depth: depth + 1)
            }
        }
        return s + "</" + name + rng.pick(["", " "]) + ">"
    }
}
