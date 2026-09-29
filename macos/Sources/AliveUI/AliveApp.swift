import SwiftUI
import AliveCore

/// Placeholder app — replaced by the shell agent (wave 1A).
public struct AliveApp: App {
    public init() {}
    public var body: some Scene {
        Window("Alive for Mac", id: "main") {
            Text("Alive for Mac — zlib \(AliveCore.zlibVersion)")
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
