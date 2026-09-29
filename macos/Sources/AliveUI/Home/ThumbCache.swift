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
    private let sweepLock = NSLock()
    private var swept = false

    private final class Box {
        let entry: ThumbEntry
        init(_ entry: ThumbEntry) { self.entry = entry }
    }

    /// `dataDir` is the app's data folder; the pictures live in its `thumbs` subfolder.
    init(dataDir: String) {
        dir = (dataDir as NSString).appendingPathComponent("thumbs")
        memory.totalCostLimit = Self.memoryLimit
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

    /// Only what is already decoded in memory: no disk read, safe on the main thread.
    func loadFromMemory(_ setPath: String) -> ThumbEntry? {
        guard let file = keyFile(for: setPath) else { return nil }
        return memory.object(forKey: file as NSString)?.entry
    }

    /// The remembered answer, or nil when there is none (parse the set as usual). A corrupt
    /// file is removed so the picture gets redrawn.
    func load(_ setPath: String) -> ThumbEntry? {
        guard let file = keyFile(for: setPath) else { return nil }
        if let hit = memory.object(forKey: file as NSString) { return hit.entry }
        // Read fully into memory: a file kept open by a lazy decoder could not be swept.
        guard let data = FileManager.default.contents(atPath: file) else { return nil }
        if data.isEmpty { return remember(.empty, file: file, cost: 1) }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            try? FileManager.default.removeItem(atPath: file)
            return nil
        }
        return remember(.image(ThumbImage(cgImage: image)), file: file, cost: image.bytesPerRow * image.height)
    }

    @discardableResult
    private func remember(_ entry: ThumbEntry, file: String, cost: Int) -> ThumbEntry {
        memory.setObject(Box(entry), forKey: file as NSString, cost: cost)
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
            remember(.image(ThumbImage(cgImage: image)), file: file, cost: image.bytesPerRow * image.height)
        } else {
            remember(.empty, file: file, cost: 1)
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

    /// Keeps the folder within `maxFiles`, deleting the oldest. Returns how many were removed.
    @discardableResult
    func sweep(keeping limit: Int = ThumbCache.maxFiles) -> Int {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return 0 }
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
