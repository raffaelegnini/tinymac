import CoreGraphics
import TinyMacCore

/// Readable names for Windows virtual-key codes, and the reverse of VK.toMac.
enum KeyNames {
    private static let named: [Int: String] = [
        0x01: "Left Click", 0x02: "Right Click", 0x04: "Middle Click",
        0x08: "Delete", 0x09: "Tab", 0x0D: "Return", 0x10: "Shift", 0x11: "Control", 0x12: "Option",
        0x13: "Pause (F15)", 0x14: "Caps Lock", 0x1B: "Esc", 0x20: "Space", 0x21: "Page Up", 0x22: "Page Down",
        0x23: "End", 0x24: "Home", 0x25: "←", 0x26: "↑", 0x27: "→", 0x28: "↓",
        0x2C: "Print Screen (F13)", 0x2D: "Help", 0x2E: "Forward Delete", 0x5B: "Command", 0x5C: "Right Command",
        0x6A: "Keypad *", 0x6B: "Keypad +", 0x6D: "Keypad -", 0x6E: "Keypad .", 0x6F: "Keypad /",
        0x90: "Clear", 0x91: "Scroll Lock (F14)",
        0xA0: "Left Shift", 0xA1: "Right Shift", 0xA2: "Left Control", 0xA3: "Right Control",
        0xA4: "Left Option", 0xA5: "Right Option",
        0xBA: ";", 0xBB: "=", 0xBC: ",", 0xBD: "-", 0xBE: ".", 0xBF: "/", 0xC0: "`",
        0xDB: "[", 0xDC: "\\", 0xDD: "]", 0xDE: "'", 0xE2: "§",
    ]

    static func name(_ vk: Int) -> String {
        if let n = named[vk] { return n }
        switch vk {
        case 0x30...0x39, 0x41...0x5A: return String(UnicodeScalar(UInt8(vk)))
        case 0x60...0x69: return "Keypad \(vk - 0x60)"
        case 0x70...0x87: return "F\(vk - 0x6F)"
        default: return String(format: "VK 0x%02X", vk)
        }
    }

    /// The virtual key that TinyMac injects with this Mac keycode.
    static func vk(forMacKeyCode code: CGKeyCode) -> Int? {
        let modifiers: Set<Int> = [VK.shift, VK.control, VK.menu, VK.lShift, VK.rShift, VK.lControl,
                                   VK.rControl, VK.lMenu, VK.rMenu, VK.lWin, VK.rWin, VK.capital]
        return VK.toMac.filter { $0.value.first == code && !modifiers.contains($0.key) }.keys.min()
    }
}
