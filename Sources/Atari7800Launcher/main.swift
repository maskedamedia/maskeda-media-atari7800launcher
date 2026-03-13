import CoreHost
import SwiftUI
import UI

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
    }
}
