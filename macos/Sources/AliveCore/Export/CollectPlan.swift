// Port of src/CollectAll.cs (CollectOptions, CollectPlan)
import Foundation

/// What to copy when collecting. The same four questions "Collect All and Save" asks in Live.
/// Files already lying in the set's folder are not asked about — Live does not ask either.
public struct CollectOptions: Equatable, Sendable {
    public var fromElsewhere = true
    public var fromOtherProjects = true
    public var fromUserLibrary = true
    /// The only one off by default. Anyone who bought a pack has it, while it weighs an order of
    /// magnitude more than everything else put together: on by default it turns "collect the
    /// project" into "copy half the library" for whoever pressed without looking.
    public var fromFactoryPacks = false
    /// Put the collected material into a .zip and leave no folder behind.
    public var toZip = false

    public init() {}

    /// The remembered choice (`settings.cfg`, upstream `Settings.Collect*`).
    public init(settings: Settings) {
        fromElsewhere = settings.collectElsewhere
        fromOtherProjects = settings.collectOtherProjects
        fromUserLibrary = settings.collectUserLibrary
        fromFactoryPacks = settings.collectFactoryPacks
        toZip = settings.collectToZip
    }

    /// Writes the choice back into a settings value (the caller saves it via `mutateSettings`).
    public func store(in settings: inout Settings) {
        settings.collectElsewhere = fromElsewhere
        settings.collectOtherProjects = fromOtherProjects
        settings.collectUserLibrary = fromUserLibrary
        settings.collectFactoryPacks = fromFactoryPacks
        settings.collectToZip = toZip
    }

    public func wants(_ origin: CollectOrigin) -> Bool {
        switch origin {
        case .inProject: return true               // already ours, always copied
        case .elsewhere: return fromElsewhere
        case .otherProject: return fromOtherProjects
        case .userLibrary: return fromUserLibrary
        case .factoryPack: return fromFactoryPacks
        case .missing: return false
        }
    }
}

/// One line of the plan shown BEFORE anything is copied: how many files and how many bytes come
/// from one origin. 5.8 GB of packs has to be seen before OK is pressed, not after.
public struct CollectGroup: Equatable, Identifiable, Sendable {
    public var origin: CollectOrigin
    public var files = 0
    public var bytes: Int64 = 0
    /// The switch is on (always true for `.inProject`).
    public var included = true

    public var id: String { "\(origin)" }
}

/// What exactly will be done. Computed before the switches are shown and recomputed on every
/// click.
public struct CollectPlan: Sendable {
    /// The folder that will be created (also the archive's name without ".zip").
    public var targetDir = ""
    public var zip = false
    public var copy: [CollectDependency] = []
    public var skipped: [CollectDependency] = []
    public var notFound: [CollectDependency] = []
    public var totalBytes: Int64 = 0
    public var freeBytes: Int64 = 0
    /// FileRef number → new path. Empty for in-project ones: their path is right as it is.
    public var rewrites: [Int: NewRef] = [:]
    /// Dependency id → where the file will land, relative to `targetDir`, forward slashes.
    public var dest: [Int: String] = [:]
    /// One row per origin, in display order: project, elsewhere, other projects, User Library,
    /// factory packs (`included` follows the options).
    public var groups: [CollectGroup] = []

    public init() {}

    /// An archive instead of a folder — same name, alongside.
    public var zipPath: String { targetDir + ".zip" }

    /// What the run will leave behind.
    public var outputPath: String { zip ? zipPath : targetDir }

    /// Whether there is room. In .zip mode twice as much is needed: the folder is staged next to
    /// the archive and until it is finished both are on disk. Compression is not counted on —
    /// samples do not compress.
    public var fits: Bool { (zip ? totalBytes * 2 : totalBytes) <= freeBytes }

    public var notFoundCount: Int { notFound.count }
}
