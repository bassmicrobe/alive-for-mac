// Mac-only: the search box without refolding every field of every set at every keystroke.
import Foundation

/// The words of a search, folded once: case, diacritics and full/half width are ignored.
public struct SearchQuery: Sendable {
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    static func fold(_ text: String) -> String { text.folding(options: options, locale: nil) }

    let words: [String]

    /// The words of `text`, split on white space; nil when there are none (everything matches).
    public init?(_ text: String) {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.map(Self.fold)
        guard !words.isEmpty else { return nil }
        self.words = words
    }

    /// Every word occurs somewhere in `foldedText` (a `SearchHaystacks.text`).
    func matches(_ foldedText: String) -> Bool {
        words.allSatisfy { foldedText.range(of: $0) != nil }
    }
}

/// Per set, the text the search looks through — name, project, path, plugins, render names, the
/// project's tags and note — folded once and kept until the catalog or the tags and notes change.
/// The fields are joined by a line break, which no word of a query contains, so a word can only be
/// found inside one field, as when each field was searched on its own.
public final class SearchHaystacks: @unchecked Sendable {
    /// What the texts were made from: the catalog's revision and the tags-and-notes revision.
    public struct Stamp: Equatable, Sendable {
        public var catalog: Int
        public var meta: Int
        public init(catalog: Int, meta: Int) { self.catalog = catalog; self.meta = meta }
    }

    private let lock = NSLock()
    private var stamp: Stamp?
    private var texts: [String: String] = [:]

    public init() {}

    /// Forgets the texts when `stamp` is not the one they were made under.
    public func validate(_ stamp: Stamp) {
        lock.lock(); defer { lock.unlock() }
        guard self.stamp != stamp else { return }
        self.stamp = stamp
        texts.removeAll(keepingCapacity: true)
    }

    func text(for s: SetEntry, tagsOf: (String) -> [String], noteOf: (String) -> String) -> String {
        lock.lock()
        let known = texts[s.path]
        lock.unlock()
        if let known { return known }
        let built = Self.build(s, tagsOf: tagsOf, noteOf: noteOf)
        lock.lock(); texts[s.path] = built; lock.unlock()
        return built
    }

    static func build(_ s: SetEntry, tagsOf: (String) -> [String], noteOf: (String) -> String) -> String {
        let dir = s.projectDir
        var fields = [s.name, s.projectName, s.path]
        fields.append(contentsOf: s.plugins)
        fields.append(contentsOf: s.renderNames)
        fields.append(contentsOf: tagsOf(dir))
        fields.append(noteOf(dir))
        return SearchQuery.fold(fields.joined(separator: "\n"))
    }
}
