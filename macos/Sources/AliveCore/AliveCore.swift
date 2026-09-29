import CZlib

/// Namespace marker for the core library. Pure logic only — see docs/PORTING.md.
public enum AliveCore {
    /// zlib version linked at build time; proves CZlib is wired.
    public static var zlibVersion: String { String(cString: CZlib.zlibVersion()) }
}
