import AppKit
import CLibretroBridge
import Foundation
import GameController
import IOKit.hid

public enum InputAction: String, CaseIterable, Identifiable, Sendable {
    case up
    case down
    case left
    case right
    case button1
    case button2
    case consoleSelect
    case consolePause
    case consoleReset

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .up:
            "Up"
        case .down:
            "Down"
        case .left:
            "Left"
        case .right:
            "Right"
        case .button1:
            "Button 1"
        case .button2:
            "Button 2"
        case .consoleSelect:
            "Console Select"
        case .consolePause:
            "Console Pause"
        case .consoleReset:
            "Console Reset"
        }
    }

    public var buttonID: UInt32 {
        switch self {
        case .up:
            UInt32(RETRO_DEVICE_ID_JOYPAD_UP)
        case .down:
            UInt32(RETRO_DEVICE_ID_JOYPAD_DOWN)
        case .left:
            UInt32(RETRO_DEVICE_ID_JOYPAD_LEFT)
        case .right:
            UInt32(RETRO_DEVICE_ID_JOYPAD_RIGHT)
        case .button1:
            UInt32(RETRO_DEVICE_ID_JOYPAD_B)
        case .button2:
            UInt32(RETRO_DEVICE_ID_JOYPAD_A)
        case .consoleSelect:
            UInt32(RETRO_DEVICE_ID_JOYPAD_SELECT)
        case .consolePause:
            UInt32(RETRO_DEVICE_ID_JOYPAD_START)
        case .consoleReset:
            UInt32(RETRO_DEVICE_ID_JOYPAD_X)
        }
    }

    public var defaultKeyCode: UInt16 {
        switch self {
        case .left:
            123
        case .right:
            124
        case .down:
            125
        case .up:
            126
        case .button1:
            6
        case .button2:
            7
        case .consoleSelect:
            48
        case .consolePause:
            36
        case .consoleReset:
            51
        }
    }
}

public enum InputDeviceKind: String, Sendable {
    case keyboard
    case controller
}

public struct InputDeviceInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let kind: InputDeviceKind

    public init(id: String, name: String, kind: InputDeviceKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

private struct HIDDeviceRecord {
    let device: IOHIDDevice
    let info: InputDeviceInfo
}

private struct HIDControllerState {
    var pressedButtons = Set<UInt32>()
    var hatValue: Int = -1
    var xAxis: Int = 0
    var yAxis: Int = 0
}

public final class InputManager: ObservableObject, @unchecked Sendable {
    public static let keyboardDeviceID = "keyboard"

    private let lock = NSLock()
    private var pressedKeyboardButtons = Set<UInt32>()
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var keyMappings: [InputAction: UInt16]
    private var controllersByID: [String: GCController] = [:]
    private var hidDevicesByID: [String: HIDDeviceRecord] = [:]
    private var hidStatesByID: [String: HIDControllerState] = [:]
    private var availableDevices: [InputDeviceInfo] = [InputDeviceInfo(id: InputManager.keyboardDeviceID, name: "Keyboard", kind: .keyboard)]
    private var assignedDeviceIDs: [UInt32: String] = [0: InputManager.keyboardDeviceID, 1: ""]
    private var notificationObservers: [NSObjectProtocol] = []
    fileprivate var hidManager: IOHIDManager?

    public var debugLogger: ((String) -> Void)?
    public var devicesChanged: (([InputDeviceInfo]) -> Void)?

    public init() {
        keyMappings = InputManager.defaultMappings()
        installControllerObservers()
        installHIDManager()
        refreshInputDevices()
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let hidManager {
            IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    public func configureMappings(_ mappings: [InputAction: UInt16]) {
        lock.lock()
        keyMappings = mappings
        lock.unlock()
    }

    public func currentMappings() -> [InputAction: UInt16] {
        lock.lock()
        let mappings = keyMappings
        lock.unlock()
        return mappings
    }

    public static func defaultMappings() -> [InputAction: UInt16] {
        Dictionary(uniqueKeysWithValues: InputAction.allCases.map { ($0, $0.defaultKeyCode) })
    }

    public static func displayName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0:
            "A"
        case 1:
            "S"
        case 2:
            "D"
        case 6:
            "Z"
        case 7:
            "X"
        case 13:
            "W"
        case 17:
            "T"
        case 31:
            "O"
        case 34:
            "I"
        case 35:
            "P"
        case 37:
            "L"
        case 38:
            "J"
        case 40:
            "K"
        case 45:
            "N"
        case 46:
            "M"
        case 48:
            "Tab"
        case 49:
            "Space"
        case 36:
            "Return"
        case 51:
            "Delete"
        case 53:
            "Escape"
        case 123:
            "Left Arrow"
        case 124:
            "Right Arrow"
        case 125:
            "Down Arrow"
        case 126:
            "Up Arrow"
        default:
            "Key \(keyCode)"
        }
    }

    public func setKeyEvent(_ event: NSEvent, isDown: Bool) {
        guard let action = action(for: event.keyCode) else {
            return
        }
        let button = action.buttonID

        lock.lock()
        if isDown {
            pressedKeyboardButtons.insert(button)
        } else {
            pressedKeyboardButtons.remove(button)
        }
        lock.unlock()
        debugLogger?("input: keyboard \(isDown ? "down" : "up") keyCode=\(event.keyCode) action=\(action.label) button=\(buttonName(button))")
    }

    public func beginCapturing() {
        guard keyDownMonitor == nil, keyUpMonitor == nil else {
            return
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.action(for: event.keyCode) != nil else {
                return event
            }
            self.setKeyEvent(event, isDown: true)
            return nil
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self, self.action(for: event.keyCode) != nil else {
                return event
            }
            self.setKeyEvent(event, isDown: false)
            return nil
        }
    }

    public func endCapturing() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
            self.keyUpMonitor = nil
        }

        lock.lock()
        pressedKeyboardButtons.removeAll()
        lock.unlock()
    }

    public func currentDevices() -> [InputDeviceInfo] {
        lock.lock()
        let devices = availableDevices
        lock.unlock()
        return devices
    }

    public func assignedDeviceID(for port: UInt32) -> String {
        lock.lock()
        let id = assignedDeviceIDs[port] ?? ""
        lock.unlock()
        return id
    }

    public func configureAssignedDeviceID(_ deviceID: String, for port: UInt32) {
        lock.lock()
        let otherPort: UInt32 = port == 0 ? 1 : 0
        if deviceID.isEmpty == false, assignedDeviceIDs[otherPort] == deviceID {
            lock.unlock()
            return
        }
        assignedDeviceIDs[port] = deviceID
        lock.unlock()
    }

    public func state(port: UInt32, device: UInt32, index: UInt32, id: UInt32) -> Int16 {
        guard port <= 1, index == 0, (device & 0xFF) == RETRO_DEVICE_JOYPAD else {
            return 0
        }

        let assignment = assignedDeviceID(for: port)
        guard assignment.isEmpty == false else {
            return 0
        }

        let buttons: Set<UInt32>
        if assignment == InputManager.keyboardDeviceID {
            lock.lock()
            buttons = pressedKeyboardButtons
            lock.unlock()
        } else if let controller = controller(for: assignment) {
            buttons = pressedButtons(for: controller)
        } else if let hidButtons = hidPressedButtons(for: assignment) {
            buttons = hidButtons
        } else {
            return 0
        }

        if id == UInt32(RETRO_DEVICE_ID_JOYPAD_MASK) {
            let bitmask = buttons.reduce(UInt32(0)) { partialResult, buttonID in
                partialResult | (UInt32(1) << buttonID)
            }
            return Int16(truncatingIfNeeded: bitmask)
        }

        return buttons.contains(id) ? 1 : 0
    }

    private func installControllerObservers() {
        let center = NotificationCenter.default
        notificationObservers = [
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] notification in
                self?.handleControllerConnection(notification)
            },
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] notification in
                self?.handleControllerDisconnection(notification)
            },
        ]
    }

    private func installHIDManager() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop), kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_Joystick)],
            [kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop), kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_GamePad)],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidDeviceRemovedCallback, context)
        IOHIDManagerRegisterInputValueCallback(manager, hidInputValueCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager
        refreshHIDDevices(from: IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? [])
    }

    private func handleControllerConnection(_ notification: Notification) {
        if let controller = notification.object as? GCController {
            debugLogger?("input: controller connected \(controllerName(for: controller))")
        }
        refreshInputDevices()
    }

    private func handleControllerDisconnection(_ notification: Notification) {
        if let controller = notification.object as? GCController {
            debugLogger?("input: controller disconnected \(controllerName(for: controller))")
        }
        refreshInputDevices()
    }

    private func refreshInputDevices() {
        let keyboard = InputDeviceInfo(id: InputManager.keyboardDeviceID, name: "Keyboard", kind: .keyboard)
        var devices: [InputDeviceInfo] = [keyboard]
        var controllers: [String: GCController] = [:]

        for controller in GCController.controllers() {
            let identifier = controllerIdentifier(for: controller)
            controllers[identifier] = controller
            devices.append(InputDeviceInfo(id: identifier, name: controllerName(for: controller), kind: .controller))
        }

        lock.lock()
        controllersByID = controllers
        let hidDevices = hidDevicesByID.values.map(\.info)
        availableDevices = devices + hidDevices.filter { hid in
            devices.contains(where: { $0.name == hid.name }) == false
        }
        normalizeAssignmentsLocked()
        let snapshot = availableDevices
        lock.unlock()
        devicesChanged?(snapshot)
    }

    fileprivate func refreshHIDDevices(from devices: Set<IOHIDDevice>) {
        var records: [String: HIDDeviceRecord] = [:]
        var states: [String: HIDControllerState] = [:]

        for device in devices {
            let identifier = hidIdentifier(for: device)
            let info = InputDeviceInfo(id: identifier, name: hidDeviceName(for: device), kind: .controller)
            records[identifier] = HIDDeviceRecord(device: device, info: info)
            states[identifier] = hidStatesByID[identifier] ?? HIDControllerState()
        }

        lock.lock()
        hidDevicesByID = records
        hidStatesByID = states
        lock.unlock()

        for record in records.values {
            debugLogger?("input: hid device detected \(record.info.name) [\(record.info.id)]")
        }
        refreshInputDevices()
    }

    private func hidIdentifier(for device: IOHIDDevice) -> String {
        let vendorID = propertyInt(device, key: kIOHIDVendorIDKey)
        let productID = propertyInt(device, key: kIOHIDProductIDKey)
        let locationID = propertyInt(device, key: kIOHIDLocationIDKey)
        return "hid:\(vendorID):\(productID):\(locationID)"
    }

    private func hidDeviceName(for device: IOHIDDevice) -> String {
        if let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) {
            let text = String(describing: name).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty == false {
                return text
            }
        }
        let vendorID = propertyInt(device, key: kIOHIDVendorIDKey)
        let productID = propertyInt(device, key: kIOHIDProductIDKey)
        return "HID Controller \(vendorID):\(productID)"
    }

    private func propertyInt(_ device: IOHIDDevice, key: String) -> Int {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return 0
        }
        if CFGetTypeID(value) == CFNumberGetTypeID() {
            var number = 0
            CFNumberGetValue((value as! CFNumber), .intType, &number)
            return number
        }
        return 0
    }

    private func controllerIdentifier(for controller: GCController) -> String {
        if #available(macOS 11.0, *) {
            return controller.productCategory + "::" + controllerName(for: controller)
        }
        return controllerName(for: controller)
    }

    private func controllerName(for controller: GCController) -> String {
        controller.vendorName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? controller.vendorName!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "Game Controller"
    }

    private func controller(for deviceID: String) -> GCController? {
        lock.lock()
        let controller = controllersByID[deviceID]
        lock.unlock()
        return controller
    }

    private func hidPressedButtons(for deviceID: String) -> Set<UInt32>? {
        lock.lock()
        let state = hidStatesByID[deviceID]
        lock.unlock()
        return state?.pressedButtons
    }

    private func pressedButtons(for controller: GCController) -> Set<UInt32> {
        var buttons = Set<UInt32>()

        if let gamepad = controller.extendedGamepad {
            if isPressed(gamepad.dpad.up) || gamepad.leftThumbstick.yAxis.value > 0.5 {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_UP))
            }
            if isPressed(gamepad.dpad.down) || gamepad.leftThumbstick.yAxis.value < -0.5 {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_DOWN))
            }
            if isPressed(gamepad.dpad.left) || gamepad.leftThumbstick.xAxis.value < -0.5 {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_LEFT))
            }
            if isPressed(gamepad.dpad.right) || gamepad.leftThumbstick.xAxis.value > 0.5 {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_RIGHT))
            }
            if isPressed(gamepad.buttonA) {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_B))
            }
            if isPressed(gamepad.buttonB) {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_A))
            }
            if isPressed(gamepad.buttonX) {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_SELECT))
            }
            if isPressed(gamepad.buttonY) {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_X))
            }
            if isPressed(gamepad.leftShoulder) {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_SELECT))
            }
            if isPressed(gamepad.rightShoulder) {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_X))
            }
            if isPressed(gamepad.buttonMenu) {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_START))
            }
            if #available(macOS 13.0, *), let buttonOptions = gamepad.buttonOptions, isPressed(buttonOptions) {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_SELECT))
            }
        } else if let gamepad = controller.microGamepad {
            if isPressed(gamepad.dpad.up) {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_UP))
            }
            if isPressed(gamepad.dpad.down) {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_DOWN))
            }
            if isPressed(gamepad.dpad.left) {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_LEFT))
            }
            if isPressed(gamepad.dpad.right) {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_RIGHT))
            }
            if isPressed(gamepad.buttonA) {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_B))
            }
            if isPressed(gamepad.buttonX) {
                buttons.insert(UInt32(RETRO_DEVICE_ID_JOYPAD_A))
            }
        }

        return buttons
    }

    private func isPressed(_ button: GCControllerButtonInput?) -> Bool {
        guard let button else {
            return false
        }
        return button.isPressed || button.value > 0.5
    }

    fileprivate func updateHIDValue(device: IOHIDDevice, value: IOHIDValue) {
        let identifier = hidIdentifier(for: device)
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        lock.lock()
        var state = hidStatesByID[identifier] ?? HIDControllerState()

        switch (usagePage, usage) {
        case (UInt32(kHIDPage_Button), 1):
            updateButton(&state, button: UInt32(RETRO_DEVICE_ID_JOYPAD_B), pressed: intValue != 0)
        case (UInt32(kHIDPage_Button), 2):
            updateButton(&state, button: UInt32(RETRO_DEVICE_ID_JOYPAD_A), pressed: intValue != 0)
        case (UInt32(kHIDPage_Button), 3):
            updateButton(&state, button: UInt32(RETRO_DEVICE_ID_JOYPAD_SELECT), pressed: intValue != 0)
        case (UInt32(kHIDPage_Button), 4):
            updateButton(&state, button: UInt32(RETRO_DEVICE_ID_JOYPAD_X), pressed: intValue != 0)
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Hatswitch)):
            state.hatValue = intValue
            applyHat(&state)
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_X)):
            state.xAxis = normalizedAxisValue(for: value)
            applyAxes(&state)
        case (UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Y)):
            state.yAxis = normalizedAxisValue(for: value)
            applyAxes(&state)
        default:
            break
        }

        hidStatesByID[identifier] = state
        lock.unlock()
    }

    private func normalizedAxisValue(for value: IOHIDValue) -> Int {
        let element = IOHIDValueGetElement(value)
        let raw = IOHIDValueGetIntegerValue(value)
        let min = IOHIDElementGetLogicalMin(element)
        let max = IOHIDElementGetLogicalMax(element)
        guard max > min else {
            return 0
        }
        let midpoint = (min + max) / 2
        let threshold = Swift.max(1, (max - min) / 4)
        if raw < midpoint - threshold {
            return -1
        }
        if raw > midpoint + threshold {
            return 1
        }
        return 0
    }

    private func applyAxes(_ state: inout HIDControllerState) {
        updateButton(&state, button: UInt32(RETRO_DEVICE_ID_JOYPAD_LEFT), pressed: state.xAxis < 0)
        updateButton(&state, button: UInt32(RETRO_DEVICE_ID_JOYPAD_RIGHT), pressed: state.xAxis > 0)
        updateButton(&state, button: UInt32(RETRO_DEVICE_ID_JOYPAD_UP), pressed: state.yAxis < 0)
        updateButton(&state, button: UInt32(RETRO_DEVICE_ID_JOYPAD_DOWN), pressed: state.yAxis > 0)
    }

    private func applyHat(_ state: inout HIDControllerState) {
        let hat = state.hatValue
        let up = [0, 1, 7].contains(hat)
        let right = [1, 2, 3].contains(hat)
        let down = [3, 4, 5].contains(hat)
        let left = [5, 6, 7].contains(hat)
        updateButton(&state, button: UInt32(RETRO_DEVICE_ID_JOYPAD_UP), pressed: up)
        updateButton(&state, button: UInt32(RETRO_DEVICE_ID_JOYPAD_RIGHT), pressed: right)
        updateButton(&state, button: UInt32(RETRO_DEVICE_ID_JOYPAD_DOWN), pressed: down)
        updateButton(&state, button: UInt32(RETRO_DEVICE_ID_JOYPAD_LEFT), pressed: left)
    }

    private func updateButton(_ state: inout HIDControllerState, button: UInt32, pressed: Bool) {
        if pressed {
            state.pressedButtons.insert(button)
        } else {
            state.pressedButtons.remove(button)
        }
    }

    private func normalizeAssignmentsLocked() {
        for port in [UInt32(0), UInt32(1)] {
            if let assigned = assignedDeviceIDs[port], assigned.isEmpty == false, availableDevices.contains(where: { $0.id == assigned }) == false {
                assignedDeviceIDs[port] = port == 0 ? InputManager.keyboardDeviceID : ""
            }
        }
    }

    private func action(for keyCode: UInt16) -> InputAction? {
        lock.lock()
        let mappings = keyMappings
        lock.unlock()
        return mappings.first(where: { $0.value == keyCode })?.key
    }

    private func buttonName(_ button: UInt32) -> String {
        switch button {
        case UInt32(RETRO_DEVICE_ID_JOYPAD_UP):
            "Up"
        case UInt32(RETRO_DEVICE_ID_JOYPAD_DOWN):
            "Down"
        case UInt32(RETRO_DEVICE_ID_JOYPAD_LEFT):
            "Left"
        case UInt32(RETRO_DEVICE_ID_JOYPAD_RIGHT):
            "Right"
        case UInt32(RETRO_DEVICE_ID_JOYPAD_B):
            "Button1/B"
        case UInt32(RETRO_DEVICE_ID_JOYPAD_A):
            "Button2/A"
        case UInt32(RETRO_DEVICE_ID_JOYPAD_X):
            "ConsoleReset"
        case UInt32(RETRO_DEVICE_ID_JOYPAD_SELECT):
            "ConsoleSelect"
        case UInt32(RETRO_DEVICE_ID_JOYPAD_START):
            "ConsolePause"
        default:
            "Button\(button)"
        }
    }
}

private func hidDeviceMatchedCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context else {
        return
    }
    let manager = Unmanaged<InputManager>.fromOpaque(context).takeUnretainedValue()
    if let hidManager = manager.hidManager {
        let devices = IOHIDManagerCopyDevices(hidManager) as? Set<IOHIDDevice> ?? []
        manager.refreshHIDDevices(from: devices)
    }
}

private func hidDeviceRemovedCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context else {
        return
    }
    let manager = Unmanaged<InputManager>.fromOpaque(context).takeUnretainedValue()
    if let hidManager = manager.hidManager {
        let devices = IOHIDManagerCopyDevices(hidManager) as? Set<IOHIDDevice> ?? []
        manager.refreshHIDDevices(from: devices)
    }
}

private func hidInputValueCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, value: IOHIDValue) {
    guard let context else {
        return
    }
    let manager = Unmanaged<InputManager>.fromOpaque(context).takeUnretainedValue()
    let device = IOHIDElementGetDevice(IOHIDValueGetElement(value))
    manager.updateHIDValue(device: device, value: value)
}
