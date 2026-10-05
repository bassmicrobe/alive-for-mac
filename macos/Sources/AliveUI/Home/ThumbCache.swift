// Port of src/ThumbCache.cs (PNG files instead of GDI+ bitmaps; an NSCache in front of the disk).
import AliveCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A finished picture wrapped so it can cross concurrency domains (CGImage is immutable).
struct ThumbImage: @unchecked Sendable {
    let cgImage: CGImage
}

/// What the cache knows about a set.
enum ThumbEntry: @unchecked Sendable {
    /// The arrangement ruler is empty: that answer costs a full parse, so it is remembered too.
    case empty
    case image(ThumbImage)
}

/// Finished arrangement pictures on disk (`<data dir>/thumbs/<key>.png`).
///
/// A preview means fully parsing the .als (up to 20 MB of XML), about 120 ms a tile, so two dozen
/// tiles would cost seconds on every start for a picture that only changes with the set. The key
/// is the path, the modification time and the size: re-save the set and the key differs; the old
/// file is never found again and goes at the next sweep.
///
/// An empty file means "the arrangement ruler is empty". Read errors are NOT written: they can be
/// temporary (a drive that is switched off) and remembering one would declare the set empty until
/// its next edit.
final class ThumbCache: @unchecked Sendable {
    /// Nobody looks at more tiles at once; re-reading one that fell out costs milliseconds.
    static let maxFiles = 400
    /// Pictures kept decoded in memory.
    static let memoryLimit = 64 * 1024 * 1024

    let dir: String
    private let memory = NSCache<NSString, Box>()
    /// The last answer per set path, whatever its stamp was: lets the main thread show a picture
    /// without a `stat`. It is only a first draft; `load` (off the main thread) checks the stamp
    /// and replaces or drops it.
    private let latest = NSCache<NSString, Box>()
    private let sweepLock = NSLock()
    private var swept = false

    private final class Box {
        let entry: ThumbEntry
        let file: String
        let cost: Int
        init(_ entry: ThumbEntry, file: String = "", cost: Int) {
            self.entry = entry; self.file = file; self.cost = cost
        }
    }

    /// `dataDir` is the app's data folder; the pictures live in its `thumbs` subfolder.
    init(dataDir: String, memoryLimit: Int = ThumbCache.memoryLimit) {
        dir = (dataDir as NSString).appendingPathComponent("thumbs")
        memory.totalCostLimit = memoryLimit
        latest.totalCostLimit = memoryLimit
    }

    // MARK: key

    private static let fnvOffset: UInt64 = 14_695_981_039_346_656_037
    private static let fnvPrime: UInt64 = 1_099_511_628_211

    private static func fnv(_ text: String, _ start: UInt64) -> UInt64 {
        var h = start
        for unit in text.utf16 {
            h = (h ^ UInt64(unit & 0xFF)) &* fnvPrime
            h = (h ^ UInt64(unit >> 8)) &* fnvPrime
        }
        return h
    }

    /// The cache file for a set, or nil when the set is not there right now.
    func keyFile(for setPath: String) -> String? {
        guard !setPath.isEmpty,
              let attrs = FileStat.of(setPath) else { return nil }
        let modified = attrs.modified
        let size = attrs.size
        var h = Self.fnv(setPath.lowercased(), Self.fnvOffset)
        h = Self.fnv(String(Int64(modified.timeIntervalSince1970 * 1_000_000)), h)
        h = Self.fnv(String(size), h)
        return (dir as NSString).appendingPathComponent(String(format: "%016llx", h) + ".png")
    }

    // MARK: reading

    /// Whether there is a ready answer (memory or disk). Cheap.
    func has(_ setPath: String) -> Bool {
        guard let file = keyFile(for: setPath) else { return false }
        return memory.object(forKey: file as NSString) != nil || FileManager.default.fileExists(atPath: file)
    }

    /// Only what is already decoded in memory: no disk access at all (not even a `stat`), safe on
    /// the main thread. The answer is the last known one for the path; `load` validates it.
    func loadFromMemory(_ setPath: String) -> ThumbEntry? {
        latest.object(forKey: setPath as NSString)?.entry
    }

    /// The remembered answer, or nil when there is none (parse the set as usual). A corrupt
    /// file is removed so the picture gets redrawn.
    func load(_ setPath: String) -> ThumbEntry? {
        guard let file = keyFile(for: setPath) else {
            latest.removeObject(forKey: setPath as NSString)
            return nil
        }
        // The set changed since the last answer (re-saved): the remembered draft is stale.
        if let draft = latest.object(forKey: setPath as NSString), draft.file != file {
            latest.removeObject(forKey: setPath as NSString)
        }
        if let hit = memory.object(forKey: file as NSString) {
            // Revisiting a tile must retain its decoded image cost in both caches.
            latest.setObject(Box(hit.entry, file: file, cost: hit.cost),
                             forKey: setPath as NSString, cost: hit.cost)
            return hit.entry
        }
        // Read fully into memory: a file kept open by a lazy decoder could not be swept.
        guard let data = FileManager.default.contents(atPath: file) else { return nil }
        if data.isEmpty { return remember(.empty, setPath: setPath, file: file, cost: 1) }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            try? FileManager.default.removeItem(atPath: file)
            return nil
        }
        return remember(.image(ThumbImage(cgImage: image)), setPath: setPath, file: file,
                        cost: image.bytesPerRow * image.height)
    }

    @discardableResult
    private func remember(_ entry: ThumbEntry, setPath: String, file: String, cost: Int) -> ThumbEntry {
        memory.setObject(Box(entry, cost: cost), forKey: file as NSString, cost: cost)
        latest.setObject(Box(entry, file: file, cost: cost), forKey: setPath as NSString, cost: cost)
        return entry
    }

    // MARK: writing

    /// Saves a picture (nil saves the "arrangement is empty" mark). Call from the background.
    func save(_ setPath: String, image: CGImage?) {
        guard let file = keyFile(for: setPath) else { return }
        let bytes: Data
        if let image {
            guard let png = Self.pngData(image) else { return }
            bytes = png
        } else {
            bytes = Data()
        }
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            // Through a temporary file of our own: several threads may be saving at once.
            let tmp = file + "." + UUID().uuidString + ".tmp"
            try bytes.write(to: URL(fileURLWithPath: tmp))
            do {
                if FileManager.default.fileExists(atPath: file) { try FileManager.default.removeItem(atPath: file) }
                try FileManager.default.moveItem(atPath: tmp, toPath: file)
            } catch {
                try? FileManager.default.removeItem(atPath: tmp)   // somebody got there first
            }
        } catch {
            Diag.fail("thumbs write", error)      // the cache is not critical: worst case we redraw
            return
        }
        if let image {
            remember(.image(ThumbImage(cgImage: image)), setPath: setPath, file: file,
                     cost: image.bytesPerRow * image.height)
        } else {
            remember(.empty, setPath: setPath, file: file, cost: 1)
        }
        sweepOnce()
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    // MARK: sweeping

    /// Once per start, in the background: the excess goes, oldest first.
    private func sweepOnce() {
        sweepLock.lock()
        let first = !swept
        swept = true
        sweepLock.unlock()
        guard first else { return }
        DispatchQueue.global(qos: .utility).async { [self] in sweep() }
    }

    /// A temporary file this old belongs to a save that died, not to one in progress.
    static let orphanAge: TimeInterval = 60

    /// Keeps the folder within `maxFiles`, deleting the oldest, and removes orphaned `*.tmp` files
    /// (a crash between write and rename) from this folder only. Returns how many pictures were removed.
    @discardableResult
    func sweep(keeping limit: Int = ThumbCache.maxFiles) -> Int {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return 0 }
        for name in names where name.hasSuffix(".tmp") {
            let path = (dir as NSString).appendingPathComponent(name)
            guard let stat = FileStat.of(path), !stat.isDirectory,
                  Date().timeIntervalSince(stat.modified) > Self.orphanAge else { continue }
            try? fm.removeItem(atPath: path)
        }
        let files = names.filter { $0.hasSuffix(".png") }.compactMap { name -> (path: String, date: Date)? in
            let path = (dir as NSString).appendingPathComponent(name)
            guard let date = FileStat.of(path)?.modified else { return nil }
            return (path, date)
        }
        guard files.count > limit else { return 0 }
        let doomed = files.sorted { $0.date < $1.date }.prefix(files.count - limit)
        doomed.forEach { try? fm.removeItem(atPath: $0.path) }
        return doomed.count
    }
}
