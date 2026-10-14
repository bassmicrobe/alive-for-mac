// swift-tools-version:5.10
// Alive for Mac — macOS port of Alive (https://github.com/rueblose/alive).
// Swift 5 language mode on purpose (tools 5.10): see docs/PORTING.md.
import PackageDescription

let extensionSwiftSettings: [SwiftSetting] = [.unsafeFlags(["-application-extension"])]
// Quick Look has no `@main`: its principal class is found by NSExtension, so the executable starts in
// _NSExtensionMain.
let quickLookLinkerSettings: [LinkerSetting] = [
    .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"]),
]
// The widget is a SwiftUI `@main WidgetBundle`: its generated `_main` (WidgetBundle.main()) must run,
// so the entry point is left alone.
// The linker flag goes straight to ld: the universal (xcbuild) link step drives clang, which
// rejects the swiftc spelling `-application-extension` (Xcode 26).
let widgetLinkerSettings: [LinkerSetting] = [.unsafeFlags(["-Xlinker", "-application_extension"])]

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
        // CoreGraphics drawing of an arrangement plus the Quick Look page: Foundation, CoreGraphics,
        // CoreText and ImageIO only, so the Quick Look extension can use it as well as the app.
        .target(name: "AliveRender", dependencies: ["AliveCore"], path: "Sources/AliveRender"),
        .target(name: "AliveUI", dependencies: ["AliveCore", "AliveRender"], path: "Sources/AliveUI"),
        // Thin @main entry.
        .executableTarget(name: "AliveForMac", dependencies: ["AliveUI"], path: "Sources/AliveForMac"),
        // App extensions (packaged into Contents/PlugIns by scripts/build-app.sh). SwiftPM has no
        // extension product type, so they are executables (Quick Look starts in _NSExtensionMain, the
        // widget in the `_main` its `@main WidgetBundle` generates).
        .executableTarget(name: "AliveQuickLook", dependencies: ["AliveCore", "AliveRender"], path: "Sources/AliveQuickLook",
                          swiftSettings: extensionSwiftSettings, linkerSettings: quickLookLinkerSettings),
        .executableTarget(name: "AliveWidget", dependencies: ["AliveCore"], path: "Sources/AliveWidget",
                          swiftSettings: extensionSwiftSettings, linkerSettings: widgetLinkerSettings),
        .testTarget(name: "AliveCoreTests", dependencies: ["AliveCore"], path: "Tests/AliveCoreTests"),
        .testTarget(name: "AliveRenderTests", dependencies: ["AliveRender", "AliveCore"], path: "Tests/AliveRenderTests"),
        .testTarget(name: "AliveUITests", dependencies: ["AliveUI", "AliveRender"], path: "Tests/AliveUITests"),
    ]
)
