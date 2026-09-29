import Foundation
@testable import AliveCore

/// The original XMLParser-based engine, kept only to differential-test the byte tokenizer.
final class ReferenceElementStream: NSObject, XMLParserDelegate {
    private var stack: [String] = []
    private let backing = XMLAttrs.TestBacking()
    private let onStart: (XMLTag) -> Void
    private let onEnd: (Int) -> Void

    init(onStart: @escaping (XMLTag) -> Void, onEnd: @escaping (Int) -> Void) {
        self.onStart = onStart
        self.onEnd = onEnd
    }

    func run(_ data: Data) -> String? {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        if parser.parse() { return nil }
        return parser.parserError?.localizedDescription ?? "XML parse error"
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        onStart(XMLTag(name: elementName, attrs: backing.attrs(attributeDict),
                       parent: stack.last ?? "", depth: stack.count))
        stack.append(elementName)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if !stack.isEmpty { stack.removeLast() }
        onEnd(stack.count)
    }
}

/// One recorded event, comparable across engines.
enum StreamEvent: Equatable {
    case start(name: String, attrs: [String: String], parent: String, depth: Int)
    case end(Int)
}

struct StreamResult {
    var events: [StreamEvent]
    var error: String?
}

enum StreamEngines {
    static func newEngine(_ data: Data) -> StreamResult {
        var ev: [StreamEvent] = []
        let s = ElementStream(
            onStart: { ev.append(.start(name: $0.name, attrs: $0.attrs.dictionary, parent: $0.parent, depth: $0.depth)) },
            onEnd: { ev.append(.end($0)) })
        let err = s.run(data)
        return StreamResult(events: ev, error: err)
    }

    static func reference(_ data: Data) -> StreamResult {
        var ev: [StreamEvent] = []
        let s = ReferenceElementStream(
            onStart: { ev.append(.start(name: $0.name, attrs: $0.attrs.dictionary, parent: $0.parent, depth: $0.depth)) },
            onEnd: { ev.append(.end($0)) })
        let err = s.run(data)
        return StreamResult(events: ev, error: err)
    }

    /// Flat-memory fingerprint of a whole event stream (names, sorted attributes, parents, depths),
    /// for comparing multi-hundred-MB documents without holding both event arrays.
    static func digest(_ data: Data, useReference: Bool) -> (hash: UInt64, events: Int, error: Bool) {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        var count = 0
        func mix(_ s: String) {
            for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
            h = (h ^ 0xFF) &* 0x100_0000_01b3
        }
        let onStart: (XMLTag) -> Void = { t in
            count += 1
            mix(t.name); mix(t.parent); mix(String(t.depth))
            for (k, v) in t.attrs.dictionary.sorted(by: { $0.key < $1.key }) { mix(k); mix(v) }
        }
        let onEnd: (Int) -> Void = { d in count += 1; mix("/" + String(d)) }
        let err = useReference
            ? ReferenceElementStream(onStart: onStart, onEnd: onEnd).run(data)
            : ElementStream(onStart: onStart, onEnd: onEnd).run(data)
        return (h, count, err != nil)
    }

    /// `Arrangement.parse` but driven by the reference engine.
    static func referenceArrangement(xml: Data) -> Arrangement {
        let parser = ArrangementParser()
        let stream = ReferenceElementStream(onStart: { parser.start($0) }, onEnd: { parser.end($0) })
        parser.arr.error = stream.run(xml)
        ArrangementParser.finish(&parser.arr)
        return parser.arr
    }

    /// `AlsFile.parse` but driven by the reference engine.
    static func referenceAls(xml: Data, path: String = "") -> AlsInfo {
        let parser = AlsParser()
        parser.info.path = path
        let stream = ReferenceElementStream(onStart: { parser.start($0) }, onEnd: { parser.end($0) })
        parser.info.error = stream.run(xml)
        return parser.info
    }
}
