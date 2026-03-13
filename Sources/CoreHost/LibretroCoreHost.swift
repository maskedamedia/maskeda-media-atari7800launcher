import CLibretroBridge
import Audio
import Foundation
import Input
import Renderer

public struct BIOSStatus: Identifiable {
    public let id = UUID()
    public let fileName: String
    public let exists: Bool
}

public struct CoreMetadata {
    public let libraryName: String
    public let libraryVersion: String
    public let validExtensions: String
    public let needsFullPath: Bool
    public let blockExtract: Bool
}

public struct ROMItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let path: String
    public let relativePath: String

    public init(path: String, relativePath: String? = nil) {
        self.path = path
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.relativePath = relativePath ?? self.name
        self.id = path
    }
}

public enum CoreOptionCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case video = "Video"
    case audio = "Audio"

    public var id: String { rawValue }
}

public struct CoreOption: Identifiable, Hashable {
    public let key: String
    public let title: String
    public let values: [String]
    public let category: CoreOptionCategory

    public var id: String { key }
}

public final class LibretroCoreHost: ObservableObject, @unchecked Sendable {
    @Published public private(set) var statusLines: [String] = []
    @Published public private(set) var metadata: CoreMetadata?
    @Published public private(set) var biosStatus: [BIOSStatus] = []
    @Published public private(set) var isCoreLoaded = false
    @Published public private(set) var isGameLoaded = false
    @Published public private(set) var isPaused = false
    @Published public private(set) var availableROMs: [ROMItem] = []
    @Published public private(set) var coreOptions: [CoreOption] = []
    @Published public private(set) var inputMappings: [InputAction: UInt16]
    @Published public private(set) var availableInputDevices: [InputDeviceInfo] = []
    @Published public var player1DeviceID: String {
        didSet {
            guard oldValue != player1DeviceID else { return }
            assignInputDevice(player1DeviceID, to: 0)
        }
    }
    @Published public var player2DeviceID: String {
        didSet {
            guard oldValue != player2DeviceID else { return }
            assignInputDevice(player2DeviceID, to: 1)
        }
    }
    @Published public var debugLoggingEnabled = false {
        didSet { persistSettings() }
    }
    @Published public var sharpPixelsEnabled = true {
        didSet {
            renderer.sharpPixelsEnabled = sharpPixelsEnabled
            persistSettings()
        }
    }
    @Published public var selectedCorePath: String {
        didSet { persistSettings() }
    }
    @Published public var romDirectoryPath: String {
        didSet {
            guard oldValue != romDirectoryPath else { return }
            refreshROMDirectorySelection()
            persistSettings()
        }
    }
    @Published public var selectedROMName: String = "" {
        didSet {
            guard oldValue != selectedROMName else { return }
            applySelectedROMName()
            persistSettings()
        }
    }
    @Published public var selectedROMPath: String {
        didSet {
            guard oldValue != selectedROMPath else { return }
            syncSelectionFromROMPath()
            persistSettings()
        }
    }
    @Published public var systemDirectoryPath: String {
        didSet {
            guard oldValue != systemDirectoryPath else { return }
            ensureDirectories()
            updateBIOSStatus()
            persistSettings()
        }
    }
    @Published public var saveDirectoryPath: String {
        didSet {
            guard oldValue != saveDirectoryPath else { return }
            ensureDirectories()
            persistSettings()
        }
    }

    public let renderer: MetalRenderer
    public let audioOutput: AudioOutput
    public let inputManager: InputManager

    private var core = LBLoadedCore()
    private var emulationThread: Thread?
    private var shouldStop = false
    private var currentPixelFormat: LibretroPixelFormat = .rgb1555
    private var loadedROMData = Data()
    private var systemDirectoryCString: UnsafeMutablePointer<CChar>?
    private var saveDirectoryCString: UnsafeMutablePointer<CChar>?
    private let logWriter = FileLogWriter()
    private var hasLoggedUnhandledEnvironmentCommands = Set<UInt32>()
    private var targetFrameDuration = 1.0 / 60.0
    private let userDefaults = UserDefaults.standard
    private var isUpdatingROMSelection = false
    private var selectedCoreOptionValues: [String: String]
    private var coreOptionValuePointers: [String: UnsafeMutablePointer<CChar>] = [:]
    private var coreOptionUpdatePending = false

    public init(configuration: LaunchConfiguration = .init()) {
        let defaultPaths = Self.defaultDirectories()
        let saved = Self.savedSettings(defaultPaths: defaultPaths)
        renderer = MetalRenderer()
        audioOutput = AudioOutput()
        inputManager = InputManager()
        debugLoggingEnabled = saved.debugLoggingEnabled
        sharpPixelsEnabled = saved.sharpPixelsEnabled
        selectedCorePath = configuration.corePath ?? saved.corePath
        romDirectoryPath = saved.romDirectoryPath
        selectedROMPath = configuration.romPath ?? saved.selectedROMPath
        systemDirectoryPath = configuration.systemDirectory ?? saved.systemDirectoryPath
        saveDirectoryPath = configuration.saveDirectory ?? saved.saveDirectoryPath
        selectedCoreOptionValues = saved.coreOptionValues
        inputMappings = saved.inputMappings
        player1DeviceID = saved.player1DeviceID
        player2DeviceID = saved.player2DeviceID
        inputManager.debugLogger = { [weak self] line in
            self?.debugLog(line)
        }
        inputManager.devicesChanged = { [weak self] devices in
            self?.updateAvailableInputDevices(devices)
        }
        renderer.sharpPixelsEnabled = sharpPixelsEnabled
        inputManager.configureMappings(inputMappings)
        inputManager.configureAssignedDeviceID(player1DeviceID, for: 0)
        inputManager.configureAssignedDeviceID(player2DeviceID, for: 1)
        updateAvailableInputDevices(inputManager.currentDevices())
        ensureDirectories()
        refreshROMDirectorySelection()
        syncSelectionFromROMPath()
        updateBIOSStatus()
        appendStatus("log file: \(logWriter.logFilePath)")
        installCurrentHost(self)
    }

    deinit {
        shutdownForDeinit()
    }

    public func startIfConfigured() {
        guard selectedCorePath.isEmpty == false, selectedROMPath.isEmpty == false else {
            return
        }
        launch()
    }

    public func launch() {
        if isGameLoaded {
            appendStatus("launch ignored: game already running")
            return
        }

        do {
            ensureCoreLoaded()
            try loadGame()
            inputManager.beginCapturing()
            startRunLoopIfNeeded()
        } catch {
            appendStatus("launch failed: \(error.localizedDescription)")
        }
    }

    public func togglePause() {
        isPaused.toggle()
        appendStatus(isPaused ? "emulation paused" : "emulation resumed")
    }

    public func reset() {
        guard isCoreLoaded else {
            return
        }
        core.retro_reset?()
        appendStatus("core reset")
    }

    public func stop() {
        appendStatus("stop requested")
        requestStop()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.awaitThreadStopAndFinalize()
        }
    }

    public func serializeState() -> Data? {
        guard isCoreLoaded, let sizeFunction = core.retro_serialize_size, let serializeFunction = core.retro_serialize else {
            return nil
        }

        let size = sizeFunction()
        guard size > 0 else {
            return nil
        }

        var data = Data(count: Int(size))
        let success = data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return false
            }
            return serializeFunction(baseAddress, size)
        }

        return success ? data : nil
    }

    public func unserializeState(_ data: Data) -> Bool {
        guard let unserializeFunction = core.retro_unserialize else {
            return false
        }

        return data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return false
            }
            return unserializeFunction(baseAddress, data.count)
        }
    }

    public func chooseROMFile(at path: String) {
        selectedROMPath = path
        let directory = (path as NSString).deletingLastPathComponent
        if directory.isEmpty == false {
            romDirectoryPath = directory
        }
    }

    public func refreshROMDirectorySelection() {
        let fileManager = FileManager.default
        guard romDirectoryPath.isEmpty == false else {
            availableROMs = []
            if selectedROMPath.isEmpty == false, FileManager.default.fileExists(atPath: selectedROMPath) {
                selectedROMName = URL(fileURLWithPath: selectedROMPath).lastPathComponent
            } else {
                selectedROMName = ""
            }
            return
        }

        let rootURL = URL(fileURLWithPath: romDirectoryPath, isDirectory: true)
        let contents = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        availableROMs = recursiveROMItems(from: contents, rootURL: rootURL)
            .sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }

        if selectedROMPath.isEmpty == false,
           let current = availableROMs.first(where: { $0.path == selectedROMPath }) {
            selectedROMName = current.name
        } else if let first = availableROMs.first {
            selectedROMName = first.name
            selectedROMPath = first.path
        } else {
            selectedROMName = selectedROMPath.isEmpty ? "" : URL(fileURLWithPath: selectedROMPath).lastPathComponent
        }
    }

    public func coreOptions(for category: CoreOptionCategory) -> [CoreOption] {
        coreOptions.filter { $0.category == category }
    }

    public var selectedROMDisplayPath: String {
        if let rom = availableROMs.first(where: { $0.path == selectedROMPath }) {
            return rom.relativePath
        }

        if selectedROMPath.isEmpty == false {
            return URL(fileURLWithPath: selectedROMPath).lastPathComponent
        }

        return "No ROM selected"
    }

    public func selectedValue(for option: CoreOption) -> String {
        selectedCoreOptionValues[option.key] ?? option.values.first ?? ""
    }

    public func setCoreOption(_ option: CoreOption, value: String) {
        guard option.values.contains(value) else {
            return
        }

        selectedCoreOptionValues[option.key] = value
        updateCoreOptionPointer(forKey: option.key, value: value)
        coreOptionUpdatePending = true
        persistSettings()
        appendStatus("core option updated: \(option.title) = \(value)")
    }

    public func resetSavedSettings() {
        let defaults = Self.defaultDirectories()
        let defaultMappings = InputManager.defaultMappings()

        selectedCoreOptionValues.removeAll()
        clearCoreOptionPointers()
        coreOptionUpdatePending = false
        coreOptions = []

        debugLoggingEnabled = false
        sharpPixelsEnabled = true
        selectedCorePath = ""
        romDirectoryPath = defaults.roms
        selectedROMPath = ""
        selectedROMName = ""
        systemDirectoryPath = defaults.system
        saveDirectoryPath = defaults.save
        inputMappings = defaultMappings
        player1DeviceID = InputManager.keyboardDeviceID
        player2DeviceID = ""
        inputManager.configureMappings(defaultMappings)
        inputManager.configureAssignedDeviceID(player1DeviceID, for: 0)
        inputManager.configureAssignedDeviceID(player2DeviceID, for: 1)
        updateAvailableInputDevices(inputManager.currentDevices())
        renderer.sharpPixelsEnabled = sharpPixelsEnabled

        for key in DefaultsKey.allCases {
            userDefaults.removeObject(forKey: key.rawValue)
        }

        ensureDirectories()
        refreshROMDirectorySelection()
        syncSelectionFromROMPath()
        updateBIOSStatus()
        persistSettings()
        appendStatus("settings reset to defaults")
    }

    public func setInputMapping(_ keyCode: UInt16, for action: InputAction) {
        inputMappings[action] = keyCode
        inputManager.configureMappings(inputMappings)
        persistSettings()
        objectWillChange.send()
        appendStatus("input mapping updated: \(action.label) = \(InputManager.displayName(for: keyCode))")
    }

    public func keyDisplayName(for action: InputAction) -> String {
        InputManager.displayName(for: inputMappings[action] ?? action.defaultKeyCode)
    }

    public func inputDevices(forPlayer port: UInt32) -> [InputDeviceInfo] {
        let otherPort: UInt32 = port == 0 ? 1 : 0
        let otherSelection = inputManager.assignedDeviceID(for: otherPort)
        if otherSelection.isEmpty {
            return availableInputDevices
        }
        return availableInputDevices.filter { $0.id != otherSelection }
    }

    public func inputDeviceName(for deviceID: String) -> String {
        if deviceID.isEmpty {
            return "None"
        }
        return availableInputDevices.first(where: { $0.id == deviceID })?.name ?? deviceID
    }

    public func setInputDevice(_ deviceID: String, forPlayer port: UInt32) {
        if port == 0 {
            player1DeviceID = deviceID
        } else {
            player2DeviceID = deviceID
        }
    }

    nonisolated func handleEnvironment(command: UInt32, data: UnsafeMutableRawPointer?) -> Bool {
        switch command {
        case UInt32(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT):
            guard let data else {
                return false
            }
            let rawValue = data.assumingMemoryBound(to: Int32.self).pointee
            guard let format = LibretroPixelFormat(rawValue: rawValue) else {
                appendStatus("unsupported pixel format: \(rawValue)")
                return false
            }
            currentPixelFormat = format
            appendStatus("environment: pixel format \(rawValue)")
            return true
        case UInt32(RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY):
            guard let data else {
                return false
            }
            data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee = UnsafePointer(systemDirectoryCString)
            appendStatus("environment: system directory requested")
            return true
        case UInt32(RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY):
            guard let data else {
                return false
            }
            data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee = UnsafePointer(saveDirectoryCString)
            appendStatus("environment: save directory requested")
            return true
        case UInt32(RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS):
            appendStatus("environment: input descriptors received")
            return true
        case UInt32(RETRO_ENVIRONMENT_SET_GEOMETRY):
            guard let data else {
                return false
            }
            let geometry = data.assumingMemoryBound(to: retro_game_geometry.self).pointee
            renderer.updateGeometry(
                baseWidth: Int(geometry.base_width),
                baseHeight: Int(geometry.base_height),
                aspectRatio: Double(geometry.aspect_ratio)
            )
            appendStatus("geometry updated: \(geometry.base_width)x\(geometry.base_height) aspect=\(geometry.aspect_ratio)")
            return true
        case UInt32(RETRO_ENVIRONMENT_SET_VARIABLES):
            guard let data else {
                return false
            }
            updateCoreOptions(from: data.assumingMemoryBound(to: retro_variable.self))
            return true
        case UInt32(RETRO_ENVIRONMENT_GET_INPUT_BITMASKS):
            return true
        case UInt32(RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION):
            guard let data else {
                return false
            }
            data.assumingMemoryBound(to: UInt32.self).pointee = 0
            return true
        case UInt32(RETRO_ENVIRONMENT_GET_VARIABLE):
            guard let data else {
                return true
            }
            let variable = data.assumingMemoryBound(to: retro_variable.self)
            guard let key = variable.pointee.key.map({ String(cString: $0) }) else {
                variable.pointee.value = nil
                return true
            }
            variable.pointee.value = coreOptionValuePointers[key].map { UnsafePointer($0) }
            return true
        case UInt32(RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE):
            guard let data else {
                return true
            }
            data.assumingMemoryBound(to: Bool.self).pointee = coreOptionUpdatePending
            coreOptionUpdatePending = false
            return true
        case UInt32(RETRO_ENVIRONMENT_GET_LOG_INTERFACE):
            appendStatus("environment: log interface requested")
            return false
        case UInt32(RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL):
            return true
        case UInt32(RETRO_ENVIRONMENT_GET_CAN_DUPE):
            guard let data else {
                return false
            }
            data.assumingMemoryBound(to: Bool.self).pointee = true
            return true
        default:
            if hasLoggedUnhandledEnvironmentCommands.insert(command).inserted {
                appendStatus("environment: unhandled cmd \(command)")
            }
            return false
        }
    }

    nonisolated func handleVideo(buffer: UnsafeRawPointer?, width: UInt32, height: UInt32, pitch: Int) {
        guard let buffer else {
            return
        }

        renderer.updateFrame(
            buffer: buffer,
            width: Int(width),
            height: Int(height),
            pitch: pitch,
            format: currentPixelFormat
        )
    }

    nonisolated func handleAudio(left: Int16, right: Int16) {
        let samples = [left, right]
        samples.withUnsafeBufferPointer { pointer in
            if let baseAddress = pointer.baseAddress {
                audioOutput.enqueue(samples: baseAddress, frameCount: 1)
            }
        }
    }

    nonisolated func handleAudioBatch(samples: UnsafePointer<Int16>?, frames: Int) -> Int {
        guard let samples else {
            return 0
        }

        audioOutput.enqueue(samples: samples, frameCount: frames)
        return frames
    }

    nonisolated func handleInputState(port: UInt32, device: UInt32, index: UInt32, id: UInt32) -> Int16 {
        inputManager.state(port: port, device: device, index: index, id: id)
    }

    private func ensureCoreLoaded() {
        guard isCoreLoaded == false else {
            return
        }

        precondition(selectedCorePath.isEmpty == false, "core path must be set before launch")
        var loadedCore = LBLoadedCore()
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let result = selectedCorePath.withCString { path in
            lb_core_open(path, &loadedCore, &errorBuffer, errorBuffer.count)
        }

        guard result == 0 else {
            let message = String(decoding: errorBuffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
            appendStatus("core load failed: \(message)")
            return
        }

        core = loadedCore
        lb_core_set_callbacks(&core)
        core.retro_init?()

        var info = retro_system_info()
        core.retro_get_system_info?(&info)
        let metadata = CoreMetadata(
            libraryName: info.library_name.map(String.init(cString:)) ?? "Unknown",
            libraryVersion: info.library_version.map(String.init(cString:)) ?? "Unknown",
            validExtensions: info.valid_extensions.map(String.init(cString:)) ?? "",
            needsFullPath: info.need_fullpath,
            blockExtract: info.block_extract
        )
        self.metadata = metadata

        var avInfo = retro_system_av_info()
        core.retro_get_system_av_info?(&avInfo)
        audioOutput.configure(sampleRate: avInfo.timing.sample_rate)
        if avInfo.timing.fps > 1 {
            targetFrameDuration = 1.0 / avInfo.timing.fps
        }

        appendStatus("core loaded: \(metadata.libraryName) \(metadata.libraryVersion)")
        appendStatus("api version: \(core.retro_api_version?() ?? 0)")
        appendStatus("content mode: \(metadata.needsFullPath ? "full path" : "memory or path")")
        appendStatus("video: \(Int(avInfo.geometry.base_width))x\(Int(avInfo.geometry.base_height)) sample_rate=\(avInfo.timing.sample_rate) fps=\(avInfo.timing.fps)")
        renderer.updateGeometry(
            baseWidth: Int(avInfo.geometry.base_width),
            baseHeight: Int(avInfo.geometry.base_height),
            aspectRatio: Double(avInfo.geometry.aspect_ratio)
        )
        isCoreLoaded = true
    }

    private func loadGame() throws {
        guard isCoreLoaded else {
            throw NSError(domain: "LibretroCoreHost", code: 1, userInfo: [NSLocalizedDescriptionKey: "core is not loaded"])
        }
        guard selectedROMPath.isEmpty == false else {
            throw NSError(domain: "LibretroCoreHost", code: 2, userInfo: [NSLocalizedDescriptionKey: "rom path is empty"])
        }

        if isGameLoaded {
            core.retro_unload_game?()
            isGameLoaded = false
        }

        let romURL = URL(fileURLWithPath: selectedROMPath)
        let attributes = try FileManager.default.attributesOfItem(atPath: romURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        var game = retro_game_info()
        var pathCopy: UnsafeMutablePointer<CChar>?
        selectedROMPath.withCString { romPath in
            pathCopy = strdup(romPath)
            game.path = UnsafePointer(pathCopy)
        }
        game.meta = nil
        loadedROMData = Data()
        if metadata?.needsFullPath == false {
            loadedROMData = try Data(contentsOf: romURL)
            game.size = loadedROMData.count
            let loadSucceeded = loadedROMData.withUnsafeBytes { bytes -> Bool in
                guard let baseAddress = bytes.baseAddress else {
                    return false
                }
                game.data = baseAddress
                return core.retro_load_game?(&game) ?? false
            }

            defer {
                if let pathCopy {
                    free(pathCopy)
                }
            }

            guard loadSucceeded else {
                loadedROMData = Data()
                appendStatus("rom load failed: \(romURL.lastPathComponent)")
                throw NSError(domain: "LibretroCoreHost", code: 3, userInfo: [NSLocalizedDescriptionKey: "retro_load_game returned false"])
            }
        } else {
            game.data = nil
            game.size = fileSize
            defer {
                if let pathCopy {
                    free(pathCopy)
                }
            }

            let loaded = core.retro_load_game?(&game) ?? false
            guard loaded else {
                appendStatus("rom load failed: \(romURL.lastPathComponent)")
                throw NSError(domain: "LibretroCoreHost", code: 3, userInfo: [NSLocalizedDescriptionKey: "retro_load_game returned false"])
            }
        }

        appendStatus("rom loaded: \(romURL.lastPathComponent)")
        isGameLoaded = true
    }

    private func startRunLoopIfNeeded() {
        guard emulationThread == nil else {
            return
        }

        shouldStop = false
        isPaused = false

        let thread = Thread { [weak self] in
            guard let self else {
                return
            }

            while self.shouldStop == false {
                let frameStart = ProcessInfo.processInfo.systemUptime
                if self.isPaused {
                    Thread.sleep(forTimeInterval: 0.016)
                    continue
                }
                self.core.retro_run?()
                let elapsed = ProcessInfo.processInfo.systemUptime - frameStart
                let remaining = self.targetFrameDuration - elapsed
                if remaining > 0 {
                    Thread.sleep(forTimeInterval: remaining)
                }
            }
        }
        thread.name = "LibretroRunLoop"
        thread.qualityOfService = .userInteractive
        emulationThread = thread
        thread.start()
        appendStatus("emulation started")
    }

    private func requestStop() {
        shouldStop = true
        inputManager.endCapturing()
        audioOutput.stop()
    }

    private func awaitThreadStopAndFinalize() {
        if let emulationThread {
            while emulationThread.isExecuting {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }

        if Thread.isMainThread {
            finalizeShutdown()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.finalizeShutdown()
            }
        }
    }

    private func finalizeShutdown() {
        emulationThread = nil

        if isGameLoaded {
            core.retro_unload_game?()
            isGameLoaded = false
            loadedROMData = Data()
            appendStatus("game unloaded")
        }

        if isCoreLoaded {
            core.retro_deinit?()
            lb_core_close(&core)
            isCoreLoaded = false
            appendStatus("core closed")
        }

        targetFrameDuration = 1.0 / 60.0
        coreOptions = []
        clearCoreOptionPointers()
        coreOptionUpdatePending = false
    }

    private func shutdownForDeinit() {
        shouldStop = true
        inputManager.endCapturing()
        audioOutput.stop()
        if let emulationThread {
            while emulationThread.isExecuting {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        core.retro_unload_game?()
        core.retro_deinit?()
        lb_core_close(&core)
        clearCoreOptionPointers()
    }

    private func appendStatus(_ line: String) {
        let entry = "[\(Self.timestamp())] \(line)"
        print(entry)
        logWriter.append(entry)
        if Thread.isMainThread {
            statusLines.append(entry)
        } else {
            DispatchQueue.main.async {
                self.statusLines.append(entry)
            }
        }
    }

    private func debugLog(_ line: String) {
        guard debugLoggingEnabled else {
            return
        }
        appendStatus(line)
    }

    private func applySelectedROMName() {
        guard isUpdatingROMSelection == false else {
            return
        }

        isUpdatingROMSelection = true
        defer { isUpdatingROMSelection = false }

        if let rom = availableROMs.first(where: { $0.name == selectedROMName }) {
            selectedROMPath = rom.path
        } else if selectedROMPath.isEmpty == false {
            selectedROMName = URL(fileURLWithPath: selectedROMPath).lastPathComponent
        }
    }

    private func syncSelectionFromROMPath() {
        guard isUpdatingROMSelection == false else {
            return
        }

        isUpdatingROMSelection = true
        defer { isUpdatingROMSelection = false }

        if let rom = availableROMs.first(where: { $0.path == selectedROMPath }) {
            selectedROMName = rom.name
            return
        }

        if selectedROMPath.isEmpty {
            selectedROMName = ""
            return
        }

        selectedROMName = URL(fileURLWithPath: selectedROMPath).lastPathComponent
    }

    private func persistSettings() {
        userDefaults.set(debugLoggingEnabled, forKey: DefaultsKey.debugLoggingEnabled.rawValue)
        userDefaults.set(sharpPixelsEnabled, forKey: DefaultsKey.sharpPixelsEnabled.rawValue)
        userDefaults.set(player1DeviceID, forKey: DefaultsKey.player1DeviceID.rawValue)
        userDefaults.set(player2DeviceID, forKey: DefaultsKey.player2DeviceID.rawValue)
        userDefaults.set(selectedCorePath, forKey: DefaultsKey.corePath.rawValue)
        userDefaults.set(romDirectoryPath, forKey: DefaultsKey.romDirectoryPath.rawValue)
        userDefaults.set(selectedROMPath, forKey: DefaultsKey.selectedROMPath.rawValue)
        userDefaults.set(systemDirectoryPath, forKey: DefaultsKey.systemDirectoryPath.rawValue)
        userDefaults.set(saveDirectoryPath, forKey: DefaultsKey.saveDirectoryPath.rawValue)
        userDefaults.set(selectedCoreOptionValues, forKey: DefaultsKey.coreOptionValues.rawValue)
        userDefaults.set(serializedInputMappings(), forKey: DefaultsKey.inputMappings.rawValue)
    }

    private func assignInputDevice(_ deviceID: String, to port: UInt32) {
        let otherPort: UInt32 = port == 0 ? 1 : 0
        let otherSelection = inputManager.assignedDeviceID(for: otherPort)
        if deviceID.isEmpty == false, deviceID == otherSelection {
            if port == 0 {
                player1DeviceID = inputManager.assignedDeviceID(for: port)
            } else {
                player2DeviceID = inputManager.assignedDeviceID(for: port)
            }
            return
        }

        inputManager.configureAssignedDeviceID(deviceID, for: port)
        let resolved = inputManager.assignedDeviceID(for: port)
        if port == 0 {
            if player1DeviceID != resolved {
                player1DeviceID = resolved
                return
            }
        } else if player2DeviceID != resolved {
            player2DeviceID = resolved
            return
        }

        persistSettings()
        objectWillChange.send()
    }

    private func updateAvailableInputDevices(_ devices: [InputDeviceInfo]) {
        let apply = {
            self.availableInputDevices = devices
            let player1Resolved = devices.contains(where: { $0.id == self.player1DeviceID }) ? self.player1DeviceID : InputManager.keyboardDeviceID
            let player2Resolved = devices.contains(where: { $0.id == self.player2DeviceID }) ? self.player2DeviceID : ""
            self.inputManager.configureAssignedDeviceID(player1Resolved, for: 0)
            self.inputManager.configureAssignedDeviceID(player2Resolved, for: 1)
            self.player1DeviceID = self.inputManager.assignedDeviceID(for: 0)
            self.player2DeviceID = self.inputManager.assignedDeviceID(for: 1)
            self.persistSettings()
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async {
                apply()
            }
        }
    }

    private func ensureDirectories() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: romDirectoryPath, withIntermediateDirectories: true)
        try? fileManager.createDirectory(atPath: systemDirectoryPath, withIntermediateDirectories: true)
        try? fileManager.createDirectory(atPath: saveDirectoryPath, withIntermediateDirectories: true)

        systemDirectoryCString?.deallocate()
        saveDirectoryCString?.deallocate()
        systemDirectoryCString = strdup(systemDirectoryPath)
        saveDirectoryCString = strdup(saveDirectoryPath)
    }

    private func updateBIOSStatus() {
        biosStatus = [
            BIOSStatus(fileName: "7800 BIOS (U).rom", exists: FileManager.default.fileExists(atPath: (systemDirectoryPath as NSString).appendingPathComponent("7800 BIOS (U).rom"))),
            BIOSStatus(fileName: "7800 BIOS (E).rom", exists: FileManager.default.fileExists(atPath: (systemDirectoryPath as NSString).appendingPathComponent("7800 BIOS (E).rom"))),
        ]
        for item in biosStatus {
            appendStatus("bios \(item.fileName): \(item.exists ? "found" : "missing")")
        }
    }

    private static func defaultDirectories() -> (system: String, save: String, roms: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let documentsBase = home.appendingPathComponent("Documents/Atari7800Launcher", isDirectory: true)
        return (
            system: documentsBase.appendingPathComponent("System", isDirectory: true).path,
            save: documentsBase.path,
            roms: documentsBase.appendingPathComponent("ROMs", isDirectory: true).path
        )
    }

    private static func savedSettings(defaultPaths: (system: String, save: String, roms: String)) -> SavedSettings {
        let defaults = UserDefaults.standard
        return SavedSettings(
            debugLoggingEnabled: defaults.object(forKey: DefaultsKey.debugLoggingEnabled.rawValue) as? Bool ?? false,
            sharpPixelsEnabled: defaults.object(forKey: DefaultsKey.sharpPixelsEnabled.rawValue) as? Bool ?? true,
            corePath: defaults.string(forKey: DefaultsKey.corePath.rawValue) ?? "",
            romDirectoryPath: defaults.string(forKey: DefaultsKey.romDirectoryPath.rawValue) ?? defaultPaths.roms,
            selectedROMPath: defaults.string(forKey: DefaultsKey.selectedROMPath.rawValue) ?? "",
            systemDirectoryPath: defaults.string(forKey: DefaultsKey.systemDirectoryPath.rawValue) ?? defaultPaths.system,
            saveDirectoryPath: defaults.string(forKey: DefaultsKey.saveDirectoryPath.rawValue) ?? defaultPaths.save,
            coreOptionValues: defaults.dictionary(forKey: DefaultsKey.coreOptionValues.rawValue) as? [String: String] ?? [:],
            inputMappings: savedInputMappings(defaults: defaults),
            player1DeviceID: defaults.string(forKey: DefaultsKey.player1DeviceID.rawValue) ?? InputManager.keyboardDeviceID,
            player2DeviceID: defaults.string(forKey: DefaultsKey.player2DeviceID.rawValue) ?? ""
        )
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private static let supportedROMExtensions: Set<String> = ["a78", "bin"]

    private func recursiveROMItems(from urls: [URL], rootURL: URL) -> [ROMItem] {
        let fileManager = FileManager.default
        var roms: [ROMItem] = []

        for url in urls {
            if isDirectory(url) {
                let children = (try? fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                roms.append(contentsOf: recursiveROMItems(from: children, rootURL: rootURL))
                continue
            }

            guard Self.supportedROMExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }

            let relativePath = String(url.path.dropFirst(rootURL.path.count + 1))
            roms.append(ROMItem(path: url.path, relativePath: relativePath))
        }

        return roms
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func serializedInputMappings() -> [String: Int] {
        var raw: [String: Int] = [:]
        for (action, keyCode) in inputMappings {
            raw[action.rawValue] = Int(keyCode)
        }
        return raw
    }

    private static func savedInputMappings(defaults: UserDefaults) -> [InputAction: UInt16] {
        var mappings = InputManager.defaultMappings()
        if let raw = defaults.dictionary(forKey: DefaultsKey.inputMappings.rawValue) as? [String: Int] {
            for action in InputAction.allCases {
                if let value = raw[action.rawValue] {
                    mappings[action] = UInt16(value)
                }
            }
        }
        return mappings
    }

    private func updateCoreOptions(from variables: UnsafePointer<retro_variable>) {
        var parsedOptions: [CoreOption] = []
        var index = 0

        while let keyPointer = variables[index].key, let valuePointer = variables[index].value {
            let key = String(cString: keyPointer)
            let definition = String(cString: valuePointer)
            if let option = Self.parseCoreOption(key: key, definition: definition) {
                parsedOptions.append(option)
            }
            index += 1
        }

        let optionKeys = Set(parsedOptions.map(\.key))
        selectedCoreOptionValues = selectedCoreOptionValues.filter { optionKeys.contains($0.key) }
        clearCoreOptionPointers()

        for option in parsedOptions {
            let selectedValue = selectedCoreOptionValues[option.key].flatMap { option.values.contains($0) ? $0 : nil } ?? option.values.first ?? ""
            selectedCoreOptionValues[option.key] = selectedValue
            updateCoreOptionPointer(forKey: option.key, value: selectedValue)
        }

        coreOptions = parsedOptions
        coreOptionUpdatePending = false
        persistSettings()
        appendStatus("environment: core options declared (\(parsedOptions.count))")
    }

    private func updateCoreOptionPointer(forKey key: String, value: String) {
        if let existing = coreOptionValuePointers[key] {
            free(existing)
        }
        coreOptionValuePointers[key] = strdup(value)
    }

    private func clearCoreOptionPointers() {
        for pointer in coreOptionValuePointers.values {
            free(pointer)
        }
        coreOptionValuePointers.removeAll()
    }

    private static func parseCoreOption(key: String, definition: String) -> CoreOption? {
        let parts = definition.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }

        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let values = parts[1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        guard values.isEmpty == false else {
            return nil
        }

        return CoreOption(
            key: key,
            title: title.isEmpty ? key : title,
            values: values,
            category: categorizeCoreOption(key: key, title: title)
        )
    }

    private static func categorizeCoreOption(key: String, title: String) -> CoreOptionCategory {
        let haystack = "\(key) \(title)".lowercased()
        let videoTerms = ["video", "graphics", "filter", "render", "palette", "color", "aspect", "display", "crop", "overscan"]
        if videoTerms.contains(where: haystack.contains) {
            return .video
        }

        let audioTerms = ["audio", "sound", "sample", "volume", "stereo", "mono", "channel"]
        if audioTerms.contains(where: haystack.contains) {
            return .audio
        }

        return .general
    }
}

private extension LibretroCoreHost {
    enum DefaultsKey: String, CaseIterable {
        case debugLoggingEnabled
        case sharpPixelsEnabled
        case player1DeviceID
        case player2DeviceID
        case corePath
        case romDirectoryPath
        case selectedROMPath
        case systemDirectoryPath
        case saveDirectoryPath
        case coreOptionValues
        case inputMappings
    }

    struct SavedSettings {
        let debugLoggingEnabled: Bool
        let sharpPixelsEnabled: Bool
        let corePath: String
        let romDirectoryPath: String
        let selectedROMPath: String
        let systemDirectoryPath: String
        let saveDirectoryPath: String
        let coreOptionValues: [String: String]
        let inputMappings: [InputAction: UInt16]
        let player1DeviceID: String
        let player2DeviceID: String
    }
}

private final class FileLogWriter: @unchecked Sendable {
    let logFilePath: String

    private let queue = DispatchQueue(label: "LibretroCoreHost.logWriter")
    private let fileManager = FileManager.default

    init() {
        let logsBase = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("prosystem-macos-launcher", isDirectory: true)
        try? fileManager.createDirectory(at: logsBase, withIntermediateDirectories: true)
        logFilePath = logsBase.appendingPathComponent("app.log").path
    }

    func append(_ line: String) {
        queue.async {
            let payload = line + "\n"
            guard let data = payload.data(using: .utf8) else {
                return
            }

            if self.fileManager.fileExists(atPath: self.logFilePath) == false {
                self.fileManager.createFile(atPath: self.logFilePath, contents: data)
                return
            }

            do {
                let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: self.logFilePath))
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                fputs("failed to write log file: \(error)\n", stderr)
            }
        }
    }
}

nonisolated(unsafe) private var currentHost: LibretroCoreHost?

private func installCurrentHost(_ host: LibretroCoreHost) {
    currentHost = host
}

@_cdecl("lb_environment_callback")
func lb_environment_callback(_ cmd: UInt32, _ data: UnsafeMutableRawPointer?) -> Bool {
    currentHost?.handleEnvironment(command: cmd, data: data) ?? false
}

@_cdecl("lb_video_refresh_callback")
func lb_video_refresh_callback(_ data: UnsafeRawPointer?, _ width: UInt32, _ height: UInt32, _ pitch: Int) {
    currentHost?.handleVideo(buffer: data, width: width, height: height, pitch: pitch)
}

@_cdecl("lb_audio_sample_callback")
func lb_audio_sample_callback(_ left: Int16, _ right: Int16) {
    currentHost?.handleAudio(left: left, right: right)
}

@_cdecl("lb_audio_sample_batch_callback")
func lb_audio_sample_batch_callback(_ data: UnsafePointer<Int16>?, _ frames: Int) -> Int {
    currentHost?.handleAudioBatch(samples: data, frames: frames) ?? 0
}

@_cdecl("lb_input_poll_callback")
func lb_input_poll_callback() {}

@_cdecl("lb_input_state_callback")
func lb_input_state_callback(_ port: UInt32, _ device: UInt32, _ index: UInt32, _ id: UInt32) -> Int16 {
    currentHost?.handleInputState(port: port, device: device, index: index, id: id) ?? 0
}
