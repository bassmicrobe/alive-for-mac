// Mac-only: size and times of a file through one stat(2) call.
// Why not FileManager.attributesOfItem: it also reads the extended attributes of every file, which is
// one more round trip on network volumes (SMB: ~28 ms per file instead of a cached stat). A set that
// references thousands of samples on a NAS took minutes to scan that way.
import Foundation

public struct FileStat: Equatable, Sendable {
    public var size: Int64
    public var modified: Date
    /// Birth time (creation date) where the file system has one, else the change time.
    public var created: Date
    public var isDirectory: Bool

    /// Follows symlinks, like .NET's FileInfo. nil when the path does not exist or cannot be read.
    public static func of(_ path: String) -> FileStat? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return FileStat(size: Int64(st.st_size), modified: date(st.st_mtimespec),
                        created: date(st.st_birthtimespec), isDirectory: (st.st_mode & S_IFMT) == S_IFDIR)
    }

    /// File size in bytes; 0 when the file is not there.
    public static func size(of path: String) -> Int64 { of(path)?.size ?? 0 }

    private static func date(_ t: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_nsec) / 1_000_000_000)
    }
}
