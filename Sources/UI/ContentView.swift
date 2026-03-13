import AppKit
import CoreHost
import Input
import Renderer
import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    private enum PanelMode {
        case launcher
        case settings
    }

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case input = "Input"
        case video = "Video"
        case audio = "Audio"
        case help = "Help"
        case debug = "Debug"

        var id: String { rawValue }
    }

    @ObservedObject private var host: LibretroCoreHost
    @State private var panelMode: PanelMode = .launcher
    @State private var settingsTab: SettingsTab = .general

    private let editableKeyChoices: [(label: String, keyCode: UInt16)] = [
        ("Up Arrow", 126),
        ("Down Arrow", 125),
        ("Left Arrow", 123),
        ("Right Arrow", 124),
        ("W", 13),
        ("A", 0),
        ("S", 1),
        ("D", 2),
        ("Z", 6),
        ("X", 7),
        ("J", 38),
        ("K", 40),
        ("L", 37),
        ("I", 34),
        ("Tab", 48),
        ("Space", 49),
        ("Return", 36),
        ("Delete", 51),
        ("Escape", 53),
    ]

    public init(host: LibretroCoreHost) {
        self.host = host
    }

    public var body: some View {
        VSplitView {
            GeometryReader { proxy in
                Group {
                    if host.renderer.isSupported {
                        MetalViewRepresentable(renderer: host.renderer, inputManager: host.inputManager)
                            .frame(width: max(proxy.size.width, 320), height: max(proxy.size.height, 240))
                            .background(Color.black)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Metal is unavailable on this machine.")
                            Text("The core host can still load and log status, but video presentation needs Metal.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            ScrollView([.horizontal, .vertical]) {
                bottomPanel
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 150, idealHeight: 150, maxHeight: 420)
            .background(.regularMaterial)
        }
        .frame(minWidth: 980, minHeight: 620)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Group {
                switch panelMode {
                case .launcher:
                    launcherPanel
                case .settings:
                    settingsPanel
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(20)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Atari 7800 Launcher")
                    .font(.title2.weight(.semibold))
                Text(panelMode == .launcher ? "Choose content and launch quickly." : "Saved paths, input, and diagnostics.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if panelMode == .launcher {
                    settingsTab = .general
                    panelMode = .settings
                } else {
                    panelMode = .launcher
                }
            } label: {
                Image(systemName: panelMode == .launcher ? "gearshape.fill" : "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(panelMode == .launcher ? "Open settings" : "Close settings")
        }
    }

    private var launcherPanel: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("ROM Library") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(host.romDirectoryPath.isEmpty ? "No ROM library path saved." : host.romDirectoryPath)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        if host.availableROMs.isEmpty {
                            Text("No `.a78` or `.bin` ROMs found in the saved library path.")
                                .foregroundStyle(.secondary)
                            Text("Place ROMs you own or have rights to use in this folder. This launcher does not provide or point users to game ROM downloads.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("ROM", selection: $host.selectedROMName) {
                                ForEach(host.availableROMs) { rom in
                                    Text(rom.relativePath).tag(rom.name)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text("Selected: \(host.selectedROMDisplayPath)")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        HStack(spacing: 10) {
                            Button("Refresh", action: host.refreshROMDirectorySelection)
                            Button("Browse ROM") {
                                if let path = openFilePanel(allowedTypes: ["a78", "bin"]) {
                                    host.chooseROMFile(at: path)
                                    panelMode = .launcher
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Button("Launch", action: host.launch)
                        .disabled(host.selectedCorePath.isEmpty || host.selectedROMPath.isEmpty)
                    Button(host.isPaused ? "Resume" : "Pause", action: host.togglePause)
                        .disabled(host.isGameLoaded == false)
                    Button("Reset", action: host.reset)
                        .disabled(host.isGameLoaded == false)
                    Button("Stop", action: host.stop)
                        .disabled(host.isCoreLoaded == false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            GroupBox("Controls") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Game")
                        .font(.headline)
                    Text("Arrow keys move. `\(host.keyDisplayName(for: .button1))` is Button 1. `\(host.keyDisplayName(for: .button2))` is Button 2.")
                        .foregroundStyle(.secondary)

                    Text("Console")
                        .font(.headline)
                    Text("`\(host.keyDisplayName(for: .consoleSelect))` selects game or mode on supported titles. `\(host.keyDisplayName(for: .consolePause))` pauses. `\(host.keyDisplayName(for: .consoleReset))` resets.")
                        .foregroundStyle(.secondary)

                    Text("You can change all mappings in Settings > Input.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Divider()

                    Text("Support: info@maskedamedia.com")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 320)

            Spacer(minLength: 0)
        }
    }

    private var visibleSettingsTabs: [SettingsTab] {
        var tabs: [SettingsTab] = [.general, .input, .video]
        if host.coreOptions(for: .audio).isEmpty == false {
            tabs.append(.audio)
        }
        tabs.append(.help)
        tabs.append(.debug)
        return tabs
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Settings", selection: $settingsTab) {
                ForEach(visibleSettingsTabs) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if visibleSettingsTabs.contains(settingsTab) == false {
                Color.clear
                    .frame(height: 0)
                    .onAppear {
                        settingsTab = .general
                    }
            }

            switch settingsTab {
            case .general:
                generalSettings
            case .input:
                inputSettings
            case .video:
                videoSettings
            case .audio:
                audioSettings
            case .help:
                helpSettings
            case .debug:
                debugSettings
            }
        }
    }

    private var generalSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                editablePathSection(
                    title: "Core Path",
                    text: $host.selectedCorePath,
                    browseTitle: "Browse Core",
                    action: {
                        if let path = openFilePanel(allowedTypes: ["dylib"]) {
                            host.selectedCorePath = path
                        }
                    }
                )

                GroupBox("Core Source") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Download the Atari 7800 libretro core from:")
                        Text("https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/prosystem_libretro.dylib.zip")
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                        Text("This app can point to a local core binary, but it does not bundle the core.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                editablePathSection(
                    title: "ROM Library Path",
                    text: $host.romDirectoryPath,
                    browseTitle: "Browse Folder",
                    action: {
                        if let path = openDirectoryPanel() {
                            host.romDirectoryPath = path
                        }
                    }
                )

                GroupBox("ROMs") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Use ROMs you personally own or otherwise have the rights to use.")
                        Text("This project does not provide ROM files or direct users to ROM download sources.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                editablePathSection(
                    title: "System Directory",
                    text: $host.systemDirectoryPath,
                    browseTitle: "Browse Folder",
                    action: {
                        if let path = openDirectoryPanel() {
                            host.systemDirectoryPath = path
                        }
                    }
                )

                editablePathSection(
                    title: "Save Directory",
                    text: $host.saveDirectoryPath,
                    browseTitle: "Browse Folder",
                    action: {
                        if let path = openDirectoryPanel() {
                            host.saveDirectoryPath = path
                        }
                    }
                )

                GroupBox("Current Selection") {
                    VStack(alignment: .leading, spacing: 6) {
                        summaryLine("Core", summarizedPath(host.selectedCorePath, placeholder: "No saved core path"))
                        summaryLine("ROM", host.selectedROMPath.isEmpty ? "No ROM selected" : URL(fileURLWithPath: host.selectedROMPath).lastPathComponent)
                        summaryLine("System Dir", summarizedPath(host.systemDirectoryPath, placeholder: "Unset"))
                        summaryLine("Save Dir", summarizedPath(host.saveDirectoryPath, placeholder: "Unset"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                coreOptionsSection(
                    title: "Other Core Options",
                    options: host.coreOptions(for: .general),
                    emptyState: "This core has not exposed any additional general options yet."
                )

                HStack {
                    Button("Reset Settings", role: .destructive, action: host.resetSavedSettings)
                        .disabled(host.isCoreLoaded)
                    Text("Clears saved paths, selected ROM, key mappings, debug flags, and remembered core options.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("These paths are saved automatically and reused on the next launch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inputSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Keyboard Mapping") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("These mappings are saved automatically. Game controller support can be layered onto the same action model later.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        ForEach(InputAction.allCases) { action in
                            HStack(alignment: .center, spacing: 12) {
                                Text(action.label)
                                    .frame(width: 140, alignment: .leading)

                                Picker(action.label, selection: Binding(
                                    get: { host.inputMappings[action] ?? action.defaultKeyCode },
                                    set: { host.setInputMapping($0, for: action) }
                                )) {
                                    ForEach(editableKeyChoices, id: \.keyCode) { choice in
                                        Text(choice.label).tag(choice.keyCode)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)

                                Text(host.keyDisplayName(for: action))
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Control Guide") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Button 1 and Button 2 are game actions.")
                        Text("Console Select is used for system-level game selection on some titles.")
                        Text("Console Pause is the 7800 console pause switch.")
                        Text("Console Reset restarts the current title.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var videoSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Rendering") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Sharp Pixels", isOn: $host.sharpPixelsEnabled)
                        Text("Nearest-neighbor sampling keeps the Atari 7800 image crisp instead of smoothing the frame buffer.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                coreOptionsSection(
                    title: "Core Video Options",
                    options: host.coreOptions(for: .video),
                    emptyState: "This core has not exposed any video-specific options yet."
                )
            }
        }
    }

    private var audioSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                coreOptionsSection(
                    title: "Core Audio Options",
                    options: host.coreOptions(for: .audio),
                    emptyState: "This core has not exposed any audio-specific options yet."
                )
            }
        }
    }

    private var helpSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Support") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.headline)
                        Text("info@maskedamedia.com")
                            .textSelection(.enabled)

                        Text("Website")
                            .font(.headline)
                        Link("retrogaming.maskedamedia.com", destination: URL(string: "https://retrogaming.maskedamedia.com")!)

                        Text("Git Repository")
                            .font(.headline)
                        Link("github.com/mpro-maskeda/maskeda-media-atari7800launcher", destination: URL(string: "https://github.com/mpro-maskeda/maskeda-media-atari7800launcher")!)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Project Notes") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This launcher hosts the Atari 7800 libretro core as a focused native macOS frontend.")
                        Text("The repository may be private during development. Public release state depends on your GitHub workflow.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var debugSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Debug Logging", isOn: $host.debugLoggingEnabled)

            GroupBox("Core Status") {
                VStack(alignment: .leading, spacing: 6) {
                    if let metadata = host.metadata {
                        summaryLine("Core", metadata.libraryName)
                        summaryLine("Version", metadata.libraryVersion)
                        summaryLine("Extensions", metadata.validExtensions)
                        summaryLine("Needs Full Path", metadata.needsFullPath ? "Yes" : "No")
                    } else {
                        Text("No core loaded")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("BIOS Status") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(host.biosStatus) { item in
                        Text("\(item.fileName): \(item.exists ? "found" : "missing")")
                            .foregroundStyle(item.exists ? Color.primary : Color.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Log") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(host.statusLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func editablePathSection(title: String, text: Binding<String>, browseTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            HStack(alignment: .top, spacing: 8) {
                TextField("", text: text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.footnote, design: .monospaced))
                Button(browseTitle, action: action)
            }
        }
    }

    private func coreOptionsSection(title: String, options: [CoreOption], emptyState: String) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                if options.isEmpty {
                    Text(emptyState)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(options) { option in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(option.title)
                                .font(.headline)
                            Picker(option.title, selection: Binding(
                                get: { host.selectedValue(for: option) },
                                set: { host.setCoreOption(option, value: $0) }
                            )) {
                                ForEach(option.values, id: \.self) { value in
                                    Text(value).tag(value)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryLine(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text("\(key):")
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func summarizedPath(_ path: String, placeholder: String) -> String {
        path.isEmpty ? placeholder : path
    }

    private func openFilePanel(allowedTypes: [String]) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedTypes.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func openDirectoryPanel() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

private struct MetalViewRepresentable: NSViewRepresentable {
    let renderer: MetalRenderer
    let inputManager: InputManager

    func makeNSView(context: Context) -> EmulatorContainerView {
        EmulatorContainerView(renderer: renderer, inputManager: inputManager)
    }

    func updateNSView(_ nsView: EmulatorContainerView, context: Context) {
        nsView.activateInputFocus()
    }
}

private final class EmulatorContainerView: NSView {
    private let metalView: EmulatorMetalView

    init(renderer: MetalRenderer, inputManager: InputManager) {
        metalView = EmulatorMetalView(renderer: renderer, inputManager: inputManager)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        metalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metalView)
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func activateInputFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.window?.makeFirstResponder(self.metalView)
        }
    }
}
