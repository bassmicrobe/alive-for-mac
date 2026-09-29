// swift-tools-version:5.10
// Alive for Mac — macOS port of Alive (https://github.com/rueblose/alive).
// Swift 5 language mode on purpose (tools 5.10): see docs/PORTING.md.
import PackageDescription

let package = Package(
    name: "AliveForMac",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AliveForMac", targets: ["AliveForMac"]),
    ],
    targets: [
        // System zlib: gzip read/write for .als (inflateInit2 15+16 / deflateInit2 31).
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        // Pure logic. Foundation + CZlib only. No SwiftUI/AppKit, no user-visible strings.
        .target(name: "AliveCore", dependencies: ["CZlib"], path: "Sources/AliveCore"),
        // All UI: SwiftUI + AppKit bridging, L10n, feature views and models.
        .target(name: "AliveUI", dependencies: ["AliveCore"], path: "Sources/AliveUI"),
        // Thin @main entry.
        .executableTarget(name: "AliveForMac", dependencies: ["AliveUI"], path: "Sources/AliveForMac"),
        .testTarget(name: "AliveCoreTests", dependencies: ["AliveCore"], path: "Tests/AliveCoreTests"),
        .testTarget(name: "AliveUITests", dependencies: ["AliveUI"], path: "Tests/AliveUITests"),
    ]
)
