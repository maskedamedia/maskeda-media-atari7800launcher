import CoreHost
import SwiftUI
import UI

struct LauncherHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Atari7800Launcher Help") {
                openWindow(id: "help")
            }
        }
    }
}

@main
struct RetroLoaderApp: App {
    @StateObject private var host: LibretroCoreHost

    init() {
        let configuration = LaunchConfiguration.fromProcessArguments()
        _host = StateObject(wrappedValue: LibretroCoreHost(configuration: configuration))
    }

    var body: some Scene {
        WindowGroup("Atari 7800 Launcher") {
            ContentView(host: host)
        }
        .windowResizability(.contentSize)
        .commands {
            LauncherHelpCommands()
        }

        Window("Atari7800Launcher Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }
}
