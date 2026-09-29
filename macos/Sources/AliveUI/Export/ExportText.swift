// Mac-only: the words and numbers of the Export sheet, built from typed core state. Pure and
// localized at call time (a language switch shows at once; unit-testable).
import AliveCore
import Foundation

enum ExportText {
    /// "12 MB", "5.8 GB" in the UI language.
    static func bytes(_ n: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false      // "0 KB", not "Zero KB"
        return formatter.string(fromByteCount: n)
    }

    /// "3 files    25 MB", or "—" for none.
    static func groupNumbers(_ g: CollectGroup) -> String {
        g.files == 0 ? "—" : ExportStrings.files(g.files) + "    " + bytes(g.bytes)
    }

    static func label(_ origin: CollectOrigin) -> String {
        switch origin {
        case .elsewhere: return ExportStrings.rowElsewhere.s
        case .otherProject: return ExportStrings.rowOtherProjects.s
        case .userLibrary: return ExportStrings.rowUserLibrary.s
        case .factoryPack: return ExportStrings.rowFactoryPacks.s
        case .inProject: return ExportStrings.inProject.s
        case .missing: return ""
        }
    }

    /// The left of the bottom shelf: the total, or why Export cannot be pressed.
    static func summary(plan: CollectPlan?, failure: ExportFailure?, destinationExists: Bool, targetDir: String,
                        outputPath: String) -> (text: String, isError: Bool) {
        if let failure { return (message(failure), failure != .cancelled ? true : false) }
        guard let plan else { return ("", false) }
        if destinationExists { return (ExportStrings.errDestinationExists.f((outputPath as NSString).lastPathComponent), true) }
        if !plan.fits { return (ExportStrings.notEnoughSpace.s, true) }
        // Nothing outside the project to bring along: the four rows all read "—", and Export is
        // still allowed, so say what it will do instead of "0 files, 0 bytes".
        if plan.copy.isEmpty { return (ExportStrings.nothingToCopy.s, false) }
        return (ExportStrings.willCopy.f(ExportStrings.files(plan.copy.count), bytes(plan.totalBytes)), false)
    }

    static func message(_ f: ExportFailure) -> String {
        switch f {
        case .destinationExists(let p): return ExportStrings.errDestinationExists.f((p as NSString).lastPathComponent)
        case .notEnoughSpace(let n, let free): return ExportStrings.errNotEnoughSpace.f(bytes(n), bytes(free))
        case .pack(let s): return ExportStrings.errPack.f(firstLine(s))
        case .setNotWritten(let s): return ExportStrings.errSetNotWritten.f(firstLine(s))
        case .io(let s): return ExportStrings.errIO.f(firstLine(s))
        case .cancelled: return ExportStrings.errCancelled.s
        }
    }

    /// The bottom shelf is one line; the whole text stays in alive.log.
    private static func firstLine(_ s: String) -> String {
        s.split(separator: "\n").first.map(String.init) ?? s
    }

    /// "Exporting 12 of 66", "Writing the collected set…", "Packing the archive…".
    static func progress(_ p: CollectProgress?) -> String {
        guard let p else { return "" }
        switch p.phase {
        case .copying: return ExportStrings.exporting.f(p.done, p.total)
        case .writingSet: return ExportStrings.writingSet.s
        case .packing: return ExportStrings.packing.s
        }
    }

    /// ONE line for every file that was not found or not copied; nil when there is none.
    static func notFoundSummary(_ count: Int) -> String? {
        count == 0 ? nil : ExportStrings.notFoundSummary.f(ExportStrings.files(count))
    }

    /// ONE line for the files that were left out for safety; nil when there is none.
    static func refusedSummary(_ count: Int) -> String? {
        count == 0 ? nil : ExportStrings.refusedSummary.f(ExportStrings.files(count))
    }

    /// The folders "from elsewhere" reaches into, first few by name ("~" for the home folder).
    static func elsewhereFolders(_ folders: [String], home: String = NSHomeDirectory(), shown: Int = 3) -> String? {
        guard !folders.isEmpty else { return nil }
        let names = folders.prefix(shown).map { path -> String in
            path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        }
        let list = names.joined(separator: ", ")
        let line = folders.count > shown ? ExportStrings.andMore.f(list, folders.count - shown) : list
        return ExportStrings.elsewhereFrom.f(line)
    }

    static func failedSummary(_ count: Int) -> String? {
        count == 0 ? nil : ExportStrings.failedSummary.f(ExportStrings.files(count))
    }

    static func doneText(_ r: CollectResult) -> String {
        let name = (r.output as NSString).lastPathComponent
        let what = ExportStrings.files(r.copiedFiles)
        return (r.failed.isEmpty ? ExportStrings.done : ExportStrings.doneWithFailures).f(what, name)
    }
}
