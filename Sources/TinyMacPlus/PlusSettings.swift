import Foundation
import TinyMacCore

/// Settings of the Plus extras, kept in the shared TinyMac.ini under [TinyMacPlus]
/// so that the [TinyTask] section stays exactly what TinyTask itself writes.
struct PlusSettings {
    static let section = "TinyMacPlus"

    var recordScroll = true
    var stopOnEsc = true
    var stopOnMouse = false
    var showHUD = true
    var countdown = 0             // seconds before recording starts, 0 = off
    var scaleToScreen = true
    var rememberPerFile = true
    var menuBarIcon = true
    var recordHotkey: Hotkey?     // replaces the TinyTask record hotkey when set
    var playHotkey: Hotkey?
    var loops = 1
    var continuous = false

    static func load(_ ini: IniFile) -> PlusSettings {
        var s = PlusSettings()
        func flag(_ key: String, _ def: Bool) -> Bool { ini.int(section, key, default: def ? 1 : 0) != 0 }
        s.recordScroll = flag("record_scroll", s.recordScroll)
        s.stopOnEsc = flag("stop_on_esc", s.stopOnEsc)
        s.stopOnMouse = flag("stop_on_mouse", s.stopOnMouse)
        s.showHUD = flag("show_hud", s.showHUD)
        s.countdown = max(0, min(ini.int(section, "countdown", default: 0), 10))
        s.scaleToScreen = flag("scale_to_screen", s.scaleToScreen)
        s.rememberPerFile = flag("remember_per_file", s.rememberPerFile)
        s.menuBarIcon = flag("menu_bar_icon", s.menuBarIcon)
        s.recordHotkey = Hotkey(string: ini.string(section, "record_hotkey", default: ""))
        s.playHotkey = Hotkey(string: ini.string(section, "play_hotkey", default: ""))
        s.loops = max(1, ini.int(section, "loops", default: 1))
        s.continuous = flag("continuous", false)
        return s
    }

    func save(_ ini: IniFile) {
        func flag(_ key: String, _ v: Bool) { ini.write(Self.section, key, v ? 1 : 0) }
        flag("record_scroll", recordScroll)
        flag("stop_on_esc", stopOnEsc)
        flag("stop_on_mouse", stopOnMouse)
        flag("show_hud", showHUD)
        ini.write(Self.section, "countdown", countdown)
        flag("scale_to_screen", scaleToScreen)
        flag("remember_per_file", rememberPerFile)
        flag("menu_bar_icon", menuBarIcon)
        ini.write(Self.section, "record_hotkey", recordHotkey?.string)
        ini.write(Self.section, "play_hotkey", playHotkey?.string)
        ini.write(Self.section, "loops", loops)
        flag("continuous", continuous)
    }
}

/// A user-defined hotkey: one Windows virtual key plus modifiers.
struct Hotkey: Equatable {
    static let control = 1, shift = 2, option = 4, command = 8

    var vk: Int
    var modifiers: Int

    init(vk: Int, modifiers: Int) {
        self.vk = vk
        self.modifiers = modifiers
    }

    /// Parses "vk,modifiers" as stored in the ini file.
    init?(string: String) {
        let parts = string.split(separator: ",").map { atoiLike(String($0)) }
        guard parts.count == 2, parts[0] > 0, parts[0] < 0xFF else { return nil }
        vk = parts[0]
        modifiers = parts[1]
    }

    var string: String { "\(vk),\(modifiers)" }

    /// True while the key and exactly these modifiers are held.
    var isDown: Bool {
        guard VK.isDown(vk) else { return false }
        let held = [(Self.control, VK.control), (Self.shift, VK.shift), (Self.option, VK.menu), (Self.command, VK.lWin)]
        for (bit, key) in held {
            let down = key == VK.lWin ? (VK.isDown(VK.lWin) || VK.isDown(VK.rWin)) : VK.isDown(key)
            if down != (modifiers & bit != 0) { return false }
        }
        return true
    }

    var displayName: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.command != 0 { s += "⌘" }
        return s + KeyNames.name(vk)
    }
}
