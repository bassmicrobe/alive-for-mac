// Mac-only: a depth-aware push reader over XMLParser (upstream used XmlReader).
import Foundation

/// One XML start tag with the context the .als parsers need.
struct XMLTag {
    let name: String
    let attrs: [String: String]
    /// Name of the enclosing element ("" at the root).
    let parent: String
    /// Number of open ancestors, i.e. upstream's `stack.Count` before the push.
    let depth: Int

    /// The `Value` attribute, where nearly all Live data sits.
    var value: String? { attrs["Value"] }
    func int(_ fallback: Int = 0) -> Int { Int(attrs["Value"] ?? "") ?? fallback }
    func int64(_ fallback: Int64 = 0) -> Int64 { Int64(attrs["Value"] ?? "") ?? fallback }
    func double(_ fallback: Double = 0) -> Double { Double(attrs["Value"] ?? "") ?? fallback }
    var bool: Bool { (attrs["Value"] ?? "").lowercased() == "true" }
}

/// Streams an XML document as start/end events. `end` receives the open-element count after the
/// pop — the same number upstream's `stack.Count` has at an EndElement — so the "close the
/// context when we leave its depth" checks port one to one. An empty element fires start and end
/// back to back, which is equivalent to upstream's `IsEmptyElement` special cases.
final class ElementStream: NSObject, XMLParserDelegate {
    private var stack: [String] = []
    private let onStart: (XMLTag) -> Void
    private let onEnd: (Int) -> Void

    init(onStart: @escaping (XMLTag) -> Void, onEnd: @escaping (Int) -> Void) {
        self.onStart = onStart
        self.onEnd = onEnd
    }

    /// Parses; returns the parser error message when the document is broken or truncated
    /// (whatever was seen before the error has already been delivered).
    func run(_ data: Data) -> String? {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        if parser.parse() { return nil }
        return parser.parserError?.localizedDescription ?? "XML parse error"
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        onStart(XMLTag(name: elementName, attrs: attributeDict,
                           parent: stack.last ?? "", depth: stack.count))
        stack.append(elementName)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if !stack.isEmpty { stack.removeLast() }
        onEnd(stack.count)
    }
}
