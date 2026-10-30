import AppKit
import ApplicationServices

/// Windows virtual-key layer.
///
/// TinyTask 1.77 records and replays Windows virtual-key codes (VK_*) and
/// Windows window messages, and its .rec format stores them verbatim. To keep
/// the macOS port's recordings byte-compatible with the Windows original, the
/// whole engine keeps working in VK codes; this file translates them to and
/// from macOS virtual keycodes (kVK_*, ANSI/US positional layout).
///
/// Keys that do not exist on a Mac keyboard follow Apple's extended-keyboard
/// convention: Print Screen = F13, Scroll Lock = F14, Pause = F15,
/// Insert = Help, Num Lock = keypad Clear.
enum VK {
    static let lButton: Int = 0x01
    static let rButton: Int = 0x02
    static let mButton: Int = 0x04
    static let xButton1: Int = 0x05
    static let xButton2: Int = 0x06
    static let shift: Int = 0x10
    static let control: Int = 0x11
    static let menu: Int = 0x12      // Alt / Option
    static let pause: Int = 0x13
    static let capital: Int = 0x14
    static let snapshot: Int = 0x2C  // Print Screen
    static let lWin: Int = 0x5B
    static let rWin: Int = 0x5C
    static let apps: Int = 0x5D
    static let f8: Int = 0x77
    static let f12: Int = 0x7B
    static let numLock: Int = 0x90
    static let scroll: Int = 0x91
    static let lShift: Int = 0xA0
    static let rShift: Int = 0xA1
    static let lControl: Int = 0xA2
    static let rControl: Int = 0xA3
    static let lMenu: Int = 0xA4
    static let rMenu: Int = 0xA5
    static let keyR: Int = 0x52
    static let keyP: Int = 0x50
    static let keyO: Int = 0x4F
    static let `return`: Int = 0x0D

    /// VK -> macOS keycodes whose state makes up that VK.
    /// The first keycode is the one used when injecting the key.
    static let toMac: [Int: [CGKeyCode]] = {
        var m: [Int: [CGKeyCode]] = [
            0x08: [0x33], 0x09: [0x30], 0x0D: [0x24, 0x4C], 0x10: [0x38, 0x3C],
            0x11: [0x3B, 0x3E], 0x12: [0x3A, 0x3D], 0x13: [0x71], 0x14: [0x39],
            0x1B: [0x35], 0x20: [0x31], 0x21: [0x74], 0x22: [0x79], 0x23: [0x77],
            0x24: [0x73], 0x25: [0x7B], 0x26: [0x7E], 0x27: [0x7C], 0x28: [0x7D],
            0x2C: [0x69], 0x2D: [0x72], 0x2E: [0x75],
            0x5B: [0x37], 0x5C: [0x36],
            0x6A: [0x43], 0x6B: [0x45], 0x6D: [0x4E], 0x6E: [0x41], 0x6F: [0x4B],
            0x90: [0x47], 0x91: [0x6B],
            0xA0: [0x38], 0xA1: [0x3C], 0xA2: [0x3B], 0xA3: [0x3E], 0xA4: [0x3A], 0xA5: [0x3D],
            0xAD: [0x4A], 0xAE: [0x49], 0xAF: [0x48],
            0xBA: [0x29], 0xBB: [0x18], 0xBC: [0x2B], 0xBD: [0x1B], 0xBE: [0x2F],
            0xBF: [0x2C], 0xC0: [0x32], 0xDB: [0x21], 0xDC: [0x2A], 0xDD: [0x1E],
            0xDE: [0x27], 0xE2: [0x0A],
        ]
        let digits: [CGKeyCode] = [0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19]
        for (i, k) in digits.enumerated() { m[0x30 + i] = [k] }
        let letters: [CGKeyCode] = [0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26,
                                    0x28, 0x25, 0x2E, 0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11,
                                    0x20, 0x09, 0x0D, 0x07, 0x10, 0x06]
        for (i, k) in letters.enumerated() { m[0x41 + i] = [k] }
        let numpad: [CGKeyCode] = [0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C]
        for (i, k) in numpad.enumerated() { m[0x60 + i] = [k] }
        // F1..F20 (F13..F15 are already taken by Print Screen / Scroll Lock / Pause)
        let fkeys: [CGKeyCode] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
                                  0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A]
        for (i, k) in fkeys.enumerated() where !(12...14).contains(i) { m[0x70 + i] = [k] }
        return m
    }()

    /// Windows MapVirtualKey(vk, MAPVK_VK_TO_VSC) for a US keyboard. Only used
    /// so that saved .rec files carry the same scan codes as the original.
    static let scanCode: [Int: UInt32] = {
        var m: [Int: UInt32] = [
            0x08: 0x0E, 0x09: 0x0F, 0x0D: 0x1C, 0x10: 0x2A, 0x11: 0x1D, 0x12: 0x38,
            0x14: 0x3A, 0x1B: 0x01, 0x20: 0x39, 0x21: 0x49, 0x22: 0x51, 0x23: 0x4F,
            0x24: 0x47, 0x25: 0x4B, 0x26: 0x48, 0x27: 0x4D, 0x28: 0x50, 0x2C: 0x54,
            0x2D: 0x52, 0x2E: 0x53, 0x5B: 0x5B, 0x5C: 0x5C, 0x5D: 0x5D,
            0x6A: 0x37, 0x6B: 0x4E, 0x6D: 0x4A, 0x6E: 0x53, 0x6F: 0x35, 0x90: 0x45, 0x91: 0x46,
            0xA0: 0x2A, 0xA1: 0x36, 0xA2: 0x1D, 0xA3: 0x1D, 0xA4: 0x38, 0xA5: 0x38,
            0xBA: 0x27, 0xBB: 0x0D, 0xBC: 0x33, 0xBD: 0x0C, 0xBE: 0x34, 0xBF: 0x35,
            0xC0: 0x29, 0xDB: 0x1A, 0xDC: 0x2B, 0xDD: 0x1B, 0xDE: 0x28, 0xE2: 0x56,
        ]
        let digits: [UInt32] = [0x0B, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A]
        for (i, s) in digits.enumerated() { m[0x30 + i] = s }
        let letters: [UInt32] = [0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24,
                                 0x25, 0x26, 0x32, 0x31, 0x18, 0x19, 0x10, 0x13, 0x1F, 0x14,
                                 0x16, 0x2F, 0x11, 0x2D, 0x15, 0x2C]
        for (i, s) in letters.enumerated() { m[0x41 + i] = s }
        let numpad: [UInt32] = [0x52, 0x4F, 0x50, 0x51, 0x4B, 0x4C, 0x4D, 0x47, 0x48, 0x49]
        for (i, s) in numpad.enumerated() { m[0x60 + i] = s }
        let fkeys: [UInt32] = [0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x43, 0x44, 0x57, 0x58,
                               0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B]
        for (i, s) in fkeys.enumerated() { m[0x70 + i] = s }
        return m
    }()

    static func mapVirtualKey(_ vk: Int) -> UInt32 { scanCode[vk] ?? 0 }

    /// Equivalent of GetAsyncKeyState(vk) & 0x8000 / GetKeyState(vk) & 0x8000.
    static func isDown(_ vk: Int) -> Bool {
        let src = CGEventSourceStateID.combinedSessionState
        switch vk {
        case lButton: return CGEventSource.buttonState(src, button: .left)
        case rButton: return CGEventSource.buttonState(src, button: .right)
        case mButton: return CGEventSource.buttonState(src, button: .center)
        case xButton1: return CGEventSource.buttonState(src, button: CGMouseButton(rawValue: 3)!)
        case xButton2: return CGEventSource.buttonState(src, button: CGMouseButton(rawValue: 4)!)
        default:
            guard let codes = toMac[vk] else { return false }
            for c in codes where CGEventSource.keyState(src, key: c) { return true }
            return false
        }
    }

    /// Windows "extended key" set used by TinyTask for KEYEVENTF_EXTENDEDKEY.
    static func isExtended(_ vk: Int) -> Bool {
        (0x21...0x2E).contains(vk) || vk == control || vk == lWin || vk == rWin || vk == apps
    }
}

/// Synthesised input, standing in for keybd_event / mouse_event / SetCursorPos.
final class InputInjector {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var downVKs = Set<Int>()
    private var leftHeld = false
    private var rightHeld = false
    private var lastDownTime: TimeInterval = 0
    private var lastDownPoint = CGPoint(x: -10_000, y: -10_000)
    private var lastDownButton: CGMouseButton = .left
    private var clickState: Int64 = 1

    static var cursorLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private var flags: CGEventFlags {
        var f: CGEventFlags = []
        if !downVKs.isDisjoint(with: [VK.shift, VK.lShift, VK.rShift]) { f.insert(.maskShift) }
        if !downVKs.isDisjoint(with: [VK.control, VK.lControl, VK.rControl]) { f.insert(.maskControl) }
        if !downVKs.isDisjoint(with: [VK.menu, VK.lMenu, VK.rMenu]) { f.insert(.maskAlternate) }
        if !downVKs.isDisjoint(with: [VK.lWin, VK.rWin]) { f.insert(.maskCommand) }
        return f
    }

    /// keybd_event(vk, MapVirtualKey(vk), up ? KEYEVENTF_KEYUP : 0, 0)
    func key(_ vk: Int, up: Bool) {
        if up { downVKs.remove(vk) } else { downVKs.insert(vk) }
        guard let code = VK.toMac[vk]?.first,
              let ev = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: !up) else { return }
        ev.flags = flags
        ev.post(tap: .cghidEventTap)
    }

    /// mouse_event(MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE, ...) followed by SetCursorPos(x, y)
    func move(to p: CGPoint) {
        let type: CGEventType = leftHeld ? .leftMouseDragged : (rightHeld ? .rightMouseDragged : .mouseMoved)
        let button: CGMouseButton = rightHeld && !leftHeld ? .right : .left
        guard let ev = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
        ev.flags = flags
        ev.post(tap: .cghidEventTap)
    }

    /// mouse_event(MOUSEEVENTF_{LEFT,RIGHT}{DOWN,UP}) at the current cursor position.
    func button(_ button: CGMouseButton, down: Bool) {
        let p = InputInjector.cursorLocation
        if down {
            // Windows derives double-clicks from timing; macOS apps read the click count.
            let now = ProcessInfo.processInfo.systemUptime
            if button == lastDownButton,
               now - lastDownTime <= NSEvent.doubleClickInterval,
               abs(p.x - lastDownPoint.x) <= 4, abs(p.y - lastDownPoint.y) <= 4 {
                clickState += 1
            } else {
                clickState = 1
            }
            lastDownTime = now
            lastDownPoint = p
            lastDownButton = button
        }
        let type: CGEventType
        switch (button, down) {
        case (.left, true): type = .leftMouseDown; leftHeld = true
        case (.left, false): type = .leftMouseUp; leftHeld = false
        case (_, true): type = .rightMouseDown; rightHeld = true
        default: type = .rightMouseUp; rightHeld = false
        }
        guard let ev = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
        ev.setIntegerValueField(.mouseEventClickState, value: button == lastDownButton ? clickState : 1)
        ev.flags = flags
        ev.post(tap: .cghidEventTap)
    }
}
