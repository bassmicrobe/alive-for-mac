// Mac-only: SwiftUI app entry. `Sources/AliveForMac/main.swift` calls `AliveApp.main()`.
import SwiftUI

public struct AliveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppModel()

    public init() {}

    public var body: some Scene {
        Window(CommonStrings.appName.s, id: "main") {
            MainWindow().environment(app)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommands(app: app) }

        Window(CommonStrings.windowStat.s, id: "stat") {
            StatWindow().environment(app).preferredColorScheme(.dark)
        }

        Window(CommonStrings.windowPlayer.s, id: "player") {
            PlayerWindow().environment(app).preferredColorScheme(.dark)
        }

        Settings {
            SettingsView().environment(app).preferredColorScheme(.dark)
        }
    }
}
