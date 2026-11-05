// Mac-only: SwiftUI app entry. `Sources/AliveForMac/main.swift` calls `AliveApp.main()`.
import SwiftUI

public struct AliveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app: AppModel

    public init() {
        // The log first, then the models: whatever they do at start-up ends up in alive.log.
        Startup.begin()
        _app = State(initialValue: AppModel())
    }

    public var body: some Scene {
        Window(CommonStrings.appName.s, id: "main") {
            MainWindow().environment(app)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(MainWindowSize.current.ideal)
        .commands { AppCommands(app: app) }

        Window(CommonStrings.windowStat.s, id: "stat") {
            StatWindow().environment(app).preferredColorScheme(.dark)
        }
        .defaultSize(width: Theme.s(1320), height: Theme.s(820))

        Window(CommonStrings.windowPlayer.s, id: "player") {
            PlayerWindow().environment(app).preferredColorScheme(.dark)
        }

        MenuBarExtra(CommonStrings.appName.s, systemImage: "waveform",
                     isInserted: Binding(get: { app.prefs.menuBar }, set: { app.prefs.menuBar = $0 })) {
            MenuBarContent().environment(app)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(app).preferredColorScheme(.dark)
        }
    }
}
