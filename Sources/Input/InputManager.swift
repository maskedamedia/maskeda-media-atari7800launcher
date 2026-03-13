import AppKit
import CLibretroBridge
import Foundation

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

public final class InputManager: ObservableObject, @unchecked Sendable {
    private let lock = NSLock()
    private var pressedButtons = Set<UInt32>()
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var keyMappings: [InputAction: UInt16]
    public var debugLogger: ((String) -> Void)?

    public init() {
        keyMappings = InputManager.defaultMappings()
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
            pressedButtons.insert(button)
        } else {
            pressedButtons.remove(button)
        }
        lock.unlock()
        debugLogger?("input: \(isDown ? "down" : "up") keyCode=\(event.keyCode) action=\(action.label) button=\(buttonName(button))")
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
        pressedButtons.removeAll()
        lock.unlock()
    }

    public func state(port: UInt32, device: UInt32, index: UInt32, id: UInt32) -> Int16 {
        guard port == 0, index == 0, (device & 0xFF) == RETRO_DEVICE_JOYPAD else {
            return 0
        }

        lock.lock()
        if id == UInt32(RETRO_DEVICE_ID_JOYPAD_MASK) {
            let bitmask = pressedButtons.reduce(UInt32(0)) { partialResult, buttonID in
                partialResult | (UInt32(1) << buttonID)
            }
            lock.unlock()
            return Int16(truncatingIfNeeded: bitmask)
        }
        let isPressed = pressedButtons.contains(id)
        lock.unlock()
        return isPressed ? 1 : 0
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
