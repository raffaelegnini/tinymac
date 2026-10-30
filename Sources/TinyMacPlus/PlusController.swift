import AppKit
import TinyMacCore

/// TinyMac Plus: the TinyMac engine plus optional extras.
///
/// Everything TinyTask does is inherited unchanged from TinyMacController; the
/// extras hook in through its extension points and can each be switched off in
/// Prefs › Plus Options, which brings back plain TinyTask behaviour.
final class PlusController: TinyMacController, NSMenuDelegate {
    // Plus commands, next to TinyTask's 0x8000-0x801B
    static let cmdEdit = 0x9000, cmdScroll = 0x9001, cmdStopEsc = 0x9002, cmdStopMouse = 0x9003
    static let cmdHUD = 0x9004, cmdCountdown = 0x9005, cmdScale = 0x9006, cmdRemember = 0x9007
    static let cmdMenuBar = 0x9008, cmdRecordHotkey = 0x9010, cmdPlayHotkey = 0x9011
    static let cmdDefaultHotkeys = 0x9012, cmdShowWindow = 0x9020

    override var appName: String { "TinyMac Plus" }

    var plus = PlusSettings()
    private let watcher = InputWatcher()
    private let hud = ProgressHUD()
    private let countdown = CountdownOverlay()
    private lazy var editor = EditorWindow(controller: self)
    private var statusItem: NSStatusItem?
    private var hudTimer: Timer?

    private var recordScreen: CGSize?   // main display size the current recording was made on
    private var userMoved = 0.0         // real mouse movement since playback started, in pixels
    private var escPressed = false
    private var playTotal = 0
    private var statusMenuMark: Int?     // record count when the menu bar menu opened during a recording
    private var stopFromStatusMenu = false

    private static var mainScreenSize: CGSize { CGDisplayBounds(CGMainDisplayID()).size }

    // MARK: - Startup and shutdown

    override func applicationDidFinishLaunching(_ notification: Notification) {
        plus = PlusSettings.load(ini)
        let isCompiled = Bundle.main.url(forResource: "payload", withExtension: "rec") != nil
        if !isCompiled {
            // TinyTask forgets these on exit; Plus remembers them.
            loops = plus.loops
            continuous = plus.continuous
        }
        super.applicationDidFinishLaunching(notification)

        watcher.onScroll = { [weak self] dy, dx in
            guard let self, self.plus.recordScroll, self.state == Self.cmdRecord else { return }
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
            self.appendRecord(ScrollRecord.make(dy: dy, dx: dx, at: InputInjector.cursorLocation,
                                                time: Self.tickCount(), hwnd: UInt32(bitPattern: pid)))
        }
        watcher.onUserMouseMove = { [weak self] distance in
            guard let self, self.state == Self.cmdPlay else { return }
            self.userMoved += distance
        }
        watcher.onUserKeyDown = { [weak self] code in
            guard let self, self.state == Self.cmdPlay, code == 0x35 else { return }
            self.escPressed = true
        }
        watcher.start()
        if !compiled { updateStatusItem() }
    }

    override func applicationWillTerminate(_ notification: Notification) {
        if !compiled {
            plus.loops = loops
            plus.continuous = continuous
            plus.save(ini)
        }
        super.applicationWillTerminate(notification)
    }

    // MARK: - Commands

    override func command(_ id: Int, hi: Int) {
        switch id {
        case Self.cmdRecord where state == 0:
            if countdown.isRunning { countdown.cancel(); return }
            if plus.countdown > 0 && !compiled {
                countdown.run(seconds: plus.countdown) { [weak self] in self?.startRecording(hi: hi) }
            } else {
                startRecording(hi: hi)
            }
        case Self.cmdRecord where state == Self.cmdRecord:
            let mark = stopFromStatusMenu ? statusMenuMark : nil
            stopFromStatusMenu = false
            super.command(id, hi: hi)
            if let mark { trimRecording(to: mark) }
        case Self.cmdPlay where state == 0:
            playTotal = records.count
            userMoved = 0
            escPressed = false
            super.command(id, hi: hi)
        case Self.cmdEdit: openEditor()
        case Self.cmdScroll: plus.recordScroll.toggle()
        case Self.cmdStopEsc: plus.stopOnEsc.toggle()
        case Self.cmdStopMouse: plus.stopOnMouse.toggle()
        case Self.cmdHUD: plus.showHUD.toggle(); refreshHUD()
        case Self.cmdCountdown: plus.countdown = plus.countdown > 0 ? 0 : 3
        case Self.cmdScale: plus.scaleToScreen.toggle()
        case Self.cmdRemember: plus.rememberPerFile.toggle()
        case Self.cmdMenuBar: plus.menuBarIcon.toggle(); updateStatusItem()
        case Self.cmdRecordHotkey: askHotkey(forRecord: true)
        case Self.cmdPlayHotkey: askHotkey(forRecord: false)
        case Self.cmdDefaultHotkeys:
            plus.recordHotkey = nil
            plus.playHotkey = nil
        case Self.cmdShowWindow:
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        default:
            super.command(id, hi: hi)
        }
        if id >= 0x9000 && !compiled { plus.save(ini) }
    }

    private func startRecording(hi: Int) {
        guard state == 0 else { return }
        watcher.start()   // may only succeed once Input Monitoring has been granted
        recordScreen = Self.mainScreenSize
        super.command(Self.cmdRecord, hi: hi)
    }

    /// Cuts the recording back to `count` records, dropping the clicks on the menu bar icon.
    private func trimRecording(to count: Int) {
        guard buffer != nil, count < index else { return }
        index = count
        for z in count..<min(count + 3, buffer!.count) { buffer![z] = EventMsg() }
    }

    // MARK: - Engine hooks

    override func playExtra(_ r: EventMsg) {
        if r.message == ScrollRecord.message { ScrollRecord.play(r) }
    }

    override func playbackPoint(_ p: CGPoint) -> CGPoint {
        guard plus.scaleToScreen, let from = recordScreen else { return p }
        let to = Self.mainScreenSize
        guard from != to else { return p }
        return CGPoint(x: (p.x * to.width / from.width).rounded(), y: (p.y * to.height / from.height).rounded())
    }

    override func playbackShouldStop() -> Bool {
        (plus.stopOnEsc && escPressed) || (plus.stopOnMouse && userMoved > 24)
    }

    override func hotkeyDown(_ setting: UInt8, letter: Int) -> Bool {
        if letter == VK.keyR, let hk = plus.recordHotkey { return hk.isDown }
        if letter == VK.keyP, let hk = plus.playHotkey { return hk.isDown }
        return super.hotkeyDown(setting, letter: letter)
    }

    override func stateDidChange() {
        refreshHUD()
        updateStatusIcon()
    }

    override func didLoad(path: String) {
        let side = Sidecar.load(for: path)
        recordScreen = side?.screenSize
        guard !compiled, plus.rememberPerFile, let side else { return }
        if let s = side.speed { speed = s }
        if let l = side.loops { loops = max(1, l) }
        if let c = side.continuous { continuous = c }
    }

    override func didSave(path: String) {
        guard plus.rememberPerFile || plus.scaleToScreen else { return }
        let screen = recordScreen ?? Self.mainScreenSize
        var side = Sidecar(screenWidth: Double(screen.width), screenHeight: Double(screen.height))
        if plus.rememberPerFile {
            side.speed = speed
            side.loops = loops
            side.continuous = continuous
        }
        side.save(for: path)
    }

    override func compileExtras(resources: URL) -> Bool {
        if let screen = recordScreen {
            Sidecar(screenWidth: Double(screen.width), screenHeight: Double(screen.height))
                .save(for: resources.appendingPathComponent("payload.rec").path)
        }
        return true
    }

    // MARK: - Editor

    private func openEditor() {
        guard state == 0 else { return }
        guard !records.isEmpty else {
            messageBox("Nothing Recorded\n\nPress the blue button to start a new recording", title: appName, style: .informational)
            return
        }
        editor.show()
    }

    // MARK: - Progress overlay

    private func refreshHUD() {
        guard plus.showHUD, state != 0 else {
            hudTimer?.invalidate()
            hudTimer = nil
            hud.hide()
            return
        }
        if hudTimer == nil {
            let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.refreshHUD() }
            RunLoop.main.add(t, forMode: .common)
            hudTimer = t
        }
        let s = (Self.tickCount() &- startTick) / 1000
        let clock = String(format: "%02d:%02d", s / 60, s % 60)
        if state == Self.cmdRecord {
            hud.show(title: "● REC  \(clock)", detail: "\(records.count) events · press the record hotkey to stop", progress: nil)
        } else {
            let name = displayName.isEmpty ? "Recording" : displayName
            let loop = continuous ? "loop \(loopCounter + 1) of ∞" : "loop \(loopCounter + 1) of \(max(loops, 1))"
            var stops: [String] = []
            if plus.stopOnEsc { stops.append("Esc") }
            if plus.stopOnMouse { stops.append("move the mouse") }
            let hint = stops.isEmpty ? "" : " · \(stops.joined(separator: " or ")) to stop"
            hud.show(title: "▶ \(name)  \(clock)", detail: loop + hint,
                     progress: playTotal > 0 ? min(1, Double(index) / Double(playTotal)) : nil)
        }
    }

    // MARK: - Menus

    override func addExtraPrefsItems(to menu: NSMenu) {
        menu.addItem(item("Edit Recording...", Self.cmdEdit))
        let options = NSMenu()
        options.autoenablesItems = false
        options.addItem(item("Record Scroll Wheel", Self.cmdScroll, checked: plus.recordScroll))
        options.addItem(item("Stop Playback with Esc", Self.cmdStopEsc, checked: plus.stopOnEsc))
        options.addItem(item("Stop Playback when the Mouse Moves", Self.cmdStopMouse, checked: plus.stopOnMouse))
        options.addItem(item("Show Progress Overlay", Self.cmdHUD, checked: plus.showHUD))
        options.addItem(item("Countdown Before Recording (3 s)", Self.cmdCountdown, checked: plus.countdown > 0))
        options.addItem(item("Scale Positions to the Current Screen", Self.cmdScale, checked: plus.scaleToScreen))
        options.addItem(item("Remember Speed and Loops per Recording", Self.cmdRemember, checked: plus.rememberPerFile))
        options.addItem(item("Menu Bar Icon", Self.cmdMenuBar, checked: plus.menuBarIcon))
        options.addItem(.separator())
        options.addItem(item("Custom Recording Hotkey...  \(plus.recordHotkey.map { "(\($0.displayName))" } ?? "")",
                             Self.cmdRecordHotkey, checked: plus.recordHotkey != nil))
        options.addItem(item("Custom Playback Hotkey...  \(plus.playHotkey.map { "(\($0.displayName))" } ?? "")",
                             Self.cmdPlayHotkey, checked: plus.playHotkey != nil))
        options.addItem(item("Use the TinyTask Hotkeys", Self.cmdDefaultHotkeys,
                             checked: plus.recordHotkey == nil && plus.playHotkey == nil))
        let optionsItem = NSMenuItem(title: "Plus Options", action: nil, keyEquivalent: "")
        optionsItem.submenu = options
        menu.addItem(optionsItem)
        menu.addItem(.separator())
    }

    override func extendMainMenu(_ main: NSMenu) {
        let recording = NSMenu(title: "Recording")
        recording.addItem(item("Open...", Self.cmdOpen, key: "o"))
        recording.addItem(item("Save...", Self.cmdSave, key: "s"))
        recording.addItem(item("Edit Recording...", Self.cmdEdit, key: "e"))
        let top = NSMenuItem(title: "Recording", action: nil, keyEquivalent: "")
        top.submenu = recording
        main.addItem(top)
    }

    private func item(_ title: String, _ id: Int, checked: Bool = false, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: #selector(plusMenu(_:)), keyEquivalent: key)
        it.target = self
        it.tag = id
        it.state = checked ? .on : .off
        return it
    }

    @objc private func plusMenu(_ sender: NSMenuItem) {
        postCommand(sender.tag, hi: sender.tag == Self.cmdPlay && state == Self.cmdPlay ? 1 : 0)
    }

    // MARK: - Menu bar icon

    private func updateStatusItem() {
        if plus.menuBarIcon && statusItem == nil {
            let si = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let menu = NSMenu()
            menu.delegate = self
            si.menu = menu
            statusItem = si
        } else if !plus.menuBarIcon, let si = statusItem {
            NSStatusBar.system.removeStatusItem(si)
            statusItem = nil
        }
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbol = state == Self.cmdRecord ? "record.circle.fill" : (state == Self.cmdPlay ? "play.circle.fill" : "record.circle")
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: appName)
        img?.isTemplate = state == 0
        button.image = img
        button.contentTintColor = state == Self.cmdRecord ? .systemRed : (state == Self.cmdPlay ? .systemGreen : nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if state == Self.cmdRecord { statusMenuMark = index }
        menu.removeAllItems()
        let rec = item(state == Self.cmdRecord ? "Stop Recording" : "Record", Self.cmdRecord)
        rec.action = #selector(statusRecord(_:))
        menu.addItem(rec)
        menu.addItem(item(state == Self.cmdPlay ? "Stop Playback" : "Play", Self.cmdPlay))
        menu.addItem(.separator())
        for (title, id) in [("Open...", Self.cmdOpen), ("Save...", Self.cmdSave), ("Edit Recording...", Self.cmdEdit)] {
            let it = item(title, id)
            it.isEnabled = state == 0
            menu.addItem(it)
        }
        menu.addItem(.separator())
        menu.addItem(item("Show \(appName)", Self.cmdShowWindow))
        menu.addItem(NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }

    @objc private func statusRecord(_ sender: NSMenuItem) {
        stopFromStatusMenu = state == Self.cmdRecord
        postCommand(Self.cmdRecord)
    }

    // MARK: - Custom hotkeys

    private func askHotkey(forRecord: Bool) {
        let alert = NSAlert()
        alert.messageText = forRecord ? "Custom Recording Hotkey" : "Custom Playback Hotkey"
        alert.informativeText = "Press the key combination to use, then click Save."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let label = NSTextField(labelWithString: "Waiting for keys…")
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 0, width: 260, height: 30)
        alert.accessoryView = label
        var captured: Hotkey?
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let vk = KeyNames.vk(forMacKeyCode: CGKeyCode(event.keyCode)) else { return event }
            let f = event.modifierFlags
            var mods = 0
            if f.contains(.control) { mods |= Hotkey.control }
            if f.contains(.shift) { mods |= Hotkey.shift }
            if f.contains(.option) { mods |= Hotkey.option }
            if f.contains(.command) { mods |= Hotkey.command }
            let hk = Hotkey(vk: vk, modifiers: mods)
            captured = hk
            label.stringValue = hk.displayName
            return nil
        }
        alert.window.level = topmost ? .floating : .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if let monitor { NSEvent.removeMonitor(monitor) }
        guard response == .alertFirstButtonReturn, let hk = captured else { return }
        if hk == (forRecord ? plus.playHotkey : plus.recordHotkey) {
            messageBox("Hotkey Conflict", title: appName, style: .warning)
            return
        }
        if forRecord { plus.recordHotkey = hk } else { plus.playHotkey = hk }
    }
}
