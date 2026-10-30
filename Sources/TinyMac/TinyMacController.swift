import AppKit
import ApplicationServices
import UniformTypeIdentifiers

/// One recorded input event. Identical to the Win32 EVENTMSG structure that
/// TinyTask 1.77 writes to .rec files: 5 little-endian DWORDs, 20 bytes.
struct EventMsg {
    var message: UInt32 = 0  // WM_KEYDOWN 0x100, WM_KEYUP 0x101, WM_MOUSEMOVE 0x200, WM_[LR]BUTTON{DOWN,UP}
    var paramL: UInt32 = 0   // key: (scan << 8) | vk     mouse: x
    var paramH: UInt32 = 0   // key: scan                 mouse: y
    var time: UInt32 = 0     // GetTickCount() milliseconds
    var hwnd: UInt32 = 0     // foreground window at record time

    static let size = 20
}

/// TinyMac engine and main window: recording, playback, compile and preferences.
///
/// Behaviour, timings and settings reproduce TinyTask 1.77 so that recordings
/// and settings stay interchangeable with it (see COMPATIBILITY.md).
final class TinyMacController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // Commands (WM_COMMAND ids)
    static let cmdOpen = 0x8000, cmdSave = 0x8001, cmdRecord = 0x8002, cmdPlay = 0x8003
    static let cmdCompile = 0x8004, cmdPrefs = 0x8005
    // Timers
    static let timerRecord = 0x3E9, timerPlay = 0x3EA, timerHotkeys = 0x3ED

    static let section = "TinyTask"  // ini section kept as in the original
    static let version = "1.77"      // TinyTask release this port reproduces
    static let appVersion = "1.0"

    let ini = IniFile.standard
    let injector = InputInjector()

    var window: NSWindow!
    var toolbar: ToolbarView!

    var buffer: [EventMsg]?            // recording buffer (zero records past the end)
    var index = 0                      // record count AND playback position (shared, as in TinyTask)
    var state = 0                      // 0, 0x8002 recording, 0x8003 playing
    var speed = 0                      // 0 = 1x, 1 = 1/2x, 2 = 2x, 100 = 100x, other = custom
    var speedCustom = 8
    var loops = 1
    var loopCounter = 0
    var continuous = false
    var recordKey: UInt8 = 0           // 0 = Ctrl+Shift+Alt+R, 1 = Print Screen, 8 = F8, 12 = F12
    var playKey: UInt8 = 0             // 0 = Ctrl+Shift+Alt+P, ...
    var topmost = false
    var hideCaptions = 0               // 0 or 12
    var toolbarPadding = 5
    var customToolbar = false
    var startTick: UInt32 = 0
    var recordDuration: UInt32 = 0
    var keyTable = [UInt8](repeating: 0, count: 256)  // last key state per VK; slot 0 = (x + y) & 0xff of the last move
    var dragging = false
    var clicked = false                // never reset once set, as in TinyTask
    var compiled = false
    var displayName = ""
    var lastPath = ""
    var compiledSpeed = 0              // speed embedded by Compile
    var compiledLoops = 1              // loop count embedded by Compile

    private var timers: [Int: Timer] = [:]
    private var hotkeyLatch = (record: false, play: false)
    private var pendingOpen: String?
    private var launched = false

    // MARK: - Startup

    func applicationWillFinishLaunching(_ notification: Notification) {
        buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let payload = Bundle.main.url(forResource: "payload", withExtension: "rec")
        compiled = payload != nil
        if compiled {
            NSApp.setActivationPolicy(.accessory)
            let cfg = (try? String(contentsOf: Bundle.main.url(forResource: "payload", withExtension: "cfg")!, encoding: .utf8)) ?? ""
            for line in cfg.components(separatedBy: .newlines) {
                let kv = line.components(separatedBy: "=")
                guard kv.count == 2 else { continue }
                if kv[0] == "speed" { compiledSpeed = atoiLike(kv[1]) }
                if kv[0] == "loops" { compiledLoops = atoiLike(kv[1]) }
            }
        } else {
            toolbarPadding = ini.int(Self.section, "toolbar_padding", default: 5) & 0xFF
        }

        toolbar = ToolbarView(frame: .zero)
        toolbar.controller = self
        toolbar.padding = toolbarPadding
        loadToolbar()

        var origin: NSPoint?
        if !compiled {
            let screen = NSScreen.screens.first?.frame ?? .zero
            let size = toolbar.contentSize
            let cx = Int(screen.width) / 2 - Int(size.width) / 2
            let cy = Int(screen.height) / 2 - Int(size.height) / 2
            var x = ini.int(Self.section, "window_x", default: cx)
            var y = ini.int(Self.section, "window_y", default: cy)
            // RectVisible check: fall back to centred when the saved spot is off-screen.
            let probe = NSPoint(x: CGFloat(x) + 0.5, y: screen.height - CGFloat(y) - 0.5)
            if !NSScreen.screens.contains(where: { $0.frame.contains(probe) }) { x = cx; y = cy }
            origin = NSPoint(x: x, y: y)
            speed = ini.int(Self.section, "speed", default: 0)
            speedCustom = ini.int(Self.section, "speed_custom", default: 8)
            topmost = ini.int(Self.section, "topmost", default: 0) != 0
            hideCaptions = ini.int(Self.section, "hide_captions", default: 0)
            recordKey = UInt8(truncatingIfNeeded: ini.int(Self.section, "record_key", default: 0))
            playKey = UInt8(truncatingIfNeeded: ini.int(Self.section, "play_key", default: 0))
        }
        toolbar.hideCaptions = hideCaptions

        window = NSWindow(contentRect: NSRect(origin: .zero, size: toolbar.contentSize),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "TinyMac"
        window.contentView = toolbar
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.level = topmost ? .floating : .normal
        window.collectionBehavior = [.fullScreenAuxiliary]
        if let origin { setTopLeft(origin) } else { window.center() }

        // WM_CREATE
        setTimer(Self.timerHotkeys, 50)

        requestPermissions()

        if !compiled {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(toolbar)
            NSApp.activate(ignoringOtherApps: true)
        }
        launched = true

        if let path = pendingOpen {
            pendingOpen = nil
            _ = load(path)
        } else if compiled, let payload {
            guard load(payload.path) else { NSApp.terminate(nil); return }
            speed = compiledSpeed & 0xFF
            loops = compiledLoops
            postCommand(Self.cmdPlay)
        }
    }

    /// Equivalent of passing a .rec on the command line ("Open with TinyMac").
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        if !launched { pendingOpen = filename; return true }
        guard state == 0 else { return false }
        return load(filename)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !compiled { window.makeKeyAndOrderFront(nil) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        destroy()
    }

    /// WM_DESTROY: persist settings (not in a compiled app), free resources.
    private var destroyed = false
    func destroy() {
        guard !destroyed else { return }
        destroyed = true
        if !compiled {
            let screenH = NSScreen.screens.first?.frame.height ?? 0
            let f = window.frame
            ini.write(Self.section, "window_x", Int(f.minX))
            ini.write(Self.section, "window_y", Int(screenH - f.maxY))
            ini.write(Self.section, "speed", speed)
            ini.write(Self.section, "speed_custom", speedCustom)
            ini.write(Self.section, "record_key", Int(recordKey))
            ini.write(Self.section, "play_key", Int(playKey))
            ini.write(Self.section, "topmost", topmost ? 1 : 0)
            ini.write(Self.section, "hide_captions", hideCaptions)
            ini.write(Self.section, "toolbar_padding", toolbarPadding)
        }
        buffer = nil
        for id in Array(timers.keys) { killTimer(id) }
    }

    func windowWillClose(_ notification: Notification) {
        destroy()
        NSApp.terminate(nil)
    }

    private func requestPermissions() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSLog("TinyMac: Accessibility permission is required to replay input.")
        }
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
    }

    // MARK: - Timers (SetTimer / KillTimer)

    static func tickCount() -> UInt32 {
        UInt32(truncatingIfNeeded: Int64(ProcessInfo.processInfo.systemUptime * 1000))
    }

    /// SetTimer: repeating until killed; USER_TIMER_MINIMUM / MAXIMUM clamping.
    func setTimer(_ id: Int, _ elapse: UInt32) {
        killTimer(id)
        let ms = min(max(elapse, 10), 0x7FFF_FFFF)
        let t = Timer(timeInterval: Double(ms) / 1000, repeats: true) { [weak self] _ in self?.onTimer(id) }
        t.tolerance = 0
        RunLoop.main.add(t, forMode: .common)
        timers[id] = t
    }

    func killTimer(_ id: Int) {
        timers.removeValue(forKey: id)?.invalidate()
    }

    private func onTimer(_ id: Int) {
        switch id {
        case Self.timerRecord:
            killTimer(id)
            recordTick()
        case Self.timerPlay:
            guard buffer != nil else { return }
            killTimer(id)
            playTick()
        case Self.timerHotkeys:
            hotkeyTick()
        default:
            break
        }
    }

    /// PostMessage(hwnd, WM_COMMAND, MAKEWPARAM(id, hi), 0)
    func postCommand(_ id: Int, hi: Int = 0) {
        DispatchQueue.main.async { [weak self] in self?.command(id, hi: hi) }
    }

    // MARK: - Buffer helpers

    private func rec(_ i: Int) -> EventMsg {
        guard let b = buffer, i >= 0, i < b.count else { return EventMsg() }
        return b[i]
    }

    private var ourHwnd: UInt32 { UInt32(truncatingIfNeeded: window.windowNumber) }

    // MARK: - WM_COMMAND

    func command(_ id: Int, hi: Int) {
        switch id {
        case Self.cmdOpen: cmdOpenFile()
        case Self.cmdSave, Self.cmdCompile: cmdSaveOrCompile(compile: id == Self.cmdCompile)
        case Self.cmdRecord: cmdRecordToggle()
        case Self.cmdPlay: cmdPlay(hi: hi)
        case Self.cmdPrefs: if state == 0 { showPrefsMenu() }
        case 0x8006: speed = 1
        case 0x8007: speed = 0
        case 0x8008: speed = 2
        case 0x8009: speed = speedCustom
        case 0x800A: speed = 100
        case 0x800B: continuous.toggle()
        case 0x800C: askLoops()
        case 0x8019: askCustomSpeed()
        case 0x800D: openWebsite()
        case 0x800E: showAbout()
        case 0x800F: recordKey = 0
        case 0x8010: if playKey == 1 { hotkeyConflict() } else { recordKey = 1 }
        case 0x8011: if playKey == 8 { hotkeyConflict() } else { recordKey = 8 }
        case 0x8012: if playKey == 12 { hotkeyConflict() } else { recordKey = 12 }
        case 0x8013: playKey = 0
        case 0x8014: if recordKey == 1 { hotkeyConflict() } else { playKey = 1 }
        case 0x8015: if recordKey == 8 { hotkeyConflict() } else { playKey = 8 }
        case 0x8016: if recordKey == 12 { hotkeyConflict() } else { playKey = 12 }
        case 0x8017:
            topmost.toggle()
            window.level = topmost ? .floating : .normal
        case 0x8018:
            hideCaptions = hideCaptions != 0 ? 0 : 12
            toolbar.hideCaptions = hideCaptions
            resizeToToolbar()
        case 0x801A: chooseCustomToolbar()
        case 0x801B:
            ini.write(Self.section, "toolbar_image", nil)
            toolbarPadding = 5
            toolbar.padding = 5
            loadToolbar()
            resizeToToolbar()
        default: break
        }
    }

    // MARK: Open (0x8000)

    private func cmdOpenFile() {
        guard state == 0 else { return }
        let panel = NSOpenPanel()
        panel.title = "Open"
        panel.allowedContentTypes = [UTType(filenameExtension: "rec") ?? .data, .data]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = load(url.path)
    }

    /// Load a recording.
    @discardableResult
    func load(_ path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path), data.count >= 1 else {
            messageBox("Unable to read file \"\(path)\"", title: "TinyMac", style: .critical)
            return false
        }
        buffer = nil
        // HeapAlloc(size + 0x1000, zeroed): the capacity includes 4 KB of zero records.
        var bytes = [UInt8](data)
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 0x1000))
        let capacity = bytes.count / EventMsg.size
        var recs = [EventMsg](repeating: EventMsg(), count: capacity)
        bytes.withUnsafeBytes { raw in
            for i in 0..<capacity {
                let o = i * EventMsg.size
                recs[i] = EventMsg(message: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian,
                                   paramL: raw.loadUnaligned(fromByteOffset: o + 4, as: UInt32.self).littleEndian,
                                   paramH: raw.loadUnaligned(fromByteOffset: o + 8, as: UInt32.self).littleEndian,
                                   time: raw.loadUnaligned(fromByteOffset: o + 12, as: UInt32.self).littleEndian,
                                   hwnd: raw.loadUnaligned(fromByteOffset: o + 16, as: UInt32.self).littleEndian)
            }
        }
        buffer = recs
        let read = data.count
        if !(read >= 2 && data[data.startIndex] == 0 && read % EventMsg.size == 0) {
            let answer = messageBox("This file does not appear to be a valid recording.\n\nLoad anyway?",
                                    title: path, style: .warning, buttons: ["Yes", "No"])
            if answer == 1 {
                buffer = nil
                return false
            }
        }
        index = read / EventMsg.size
        displayName = (path as NSString).lastPathComponent
        window.title = displayName
        return true
    }

    // MARK: Save / Compile (0x8001 / 0x8004)

    private func cmdSaveOrCompile(compile: Bool) {
        guard state == 0 else { return }
        guard buffer != nil, index >= 1 else { nothingRecorded(); return }
        var name = lastPath
        if compile, name.lowercased().hasSuffix(".rec") { name.removeLast(4) }

        let panel = NSSavePanel()
        panel.title = compile ? "Compile" : "Save"
        panel.allowsOtherFileTypes = true
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if compile {
            panel.message = "Application (*.app)"
        } else if let rec = UTType(filenameExtension: "rec") {
            panel.allowedContentTypes = [rec]
        }
        if !name.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (name as NSString).deletingLastPathComponent)
            panel.nameFieldStringValue = (name as NSString).lastPathComponent
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        lastPath = url.path
        let ext = compile ? ".app" : ".rec"
        if !lastPath.lowercased().hasSuffix(ext) { lastPath += ext }
        try? FileManager.default.removeItem(atPath: lastPath)

        if !compile {
            _ = writeRecording(to: URL(fileURLWithPath: lastPath))
            displayName = (lastPath as NSString).lastPathComponent
            window.title = displayName
            return
        }
        compileApp(to: lastPath)
    }

    private func recordingData() -> Data {
        var d = Data(capacity: index * EventMsg.size)
        for i in 0..<index {
            let r = rec(i)
            for v in [r.message, r.paramL, r.paramH, r.time, r.hwnd] {
                withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
            }
        }
        return d
    }

    private func writeRecording(to url: URL) -> Bool {
        (try? recordingData().write(to: url)) != nil
    }

    /// Compile: copies this .app, stores the recording plus the current loop
    /// count and speed as resources, then re-signs the copy (ad hoc). The copy
    /// runs hidden, plays the recording and quits, like a compiled TinyTask .exe.
    private func compileApp(to path: String) {
        let dest = URL(fileURLWithPath: path)
        do {
            try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: dest)
        } catch {
            messageBox("Unable to write file", title: path, style: .critical)
            return
        }
        let res = dest.appendingPathComponent("Contents/Resources", isDirectory: true)
        let cfg = String(format: "loops=%05d\nspeed=%05d\n", min(loops, 99999), min(speed, 99999))
        var ok = (try? FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)) != nil
        ok = ok && (try? cfg.write(to: res.appendingPathComponent("payload.cfg"), atomically: true, encoding: .utf8)) != nil
        ok = ok && writeRecording(to: res.appendingPathComponent("payload.rec"))

        let plistURL = dest.appendingPathComponent("Contents/Info.plist")
        if ok, let plist = NSMutableDictionary(contentsOf: plistURL) {
            let base = (dest.deletingPathExtension().lastPathComponent)
            let safe = base.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
            plist["CFBundleName"] = base
            plist["CFBundleDisplayName"] = base
            plist["CFBundleIdentifier"] = "io.github.tinymac.compiled.\(safe)"
            plist["LSUIElement"] = true
            plist.removeObject(forKey: "CFBundleDocumentTypes")
            ok = plist.write(to: plistURL, atomically: true)
        }
        if ok {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            p.arguments = ["--force", "--deep", "--sign", "-", dest.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }

        guard ok else {
            messageBox("  Compile Error\n\n\(path)", title: "TinyMac", style: .critical)
            return
        }
        let total = directorySize(dest)
        let (sizeValue, unit) = total > 0x100000 ? (total / 0x100000, "MB") : (total / 0x400, "KB")
        let (speedValue, speedSuffix): (Int, String) = speed == 1 ? (1, "/2") : (speed == 0 ? (1, "") : (speed, ""))
        let text = "  Compile successful\t\n\n  \"\(path)\"   (\(sizeValue) \(unit))\n\nProgram attributes:\n----------------------------------\n  Execution Speed:\t \(speedValue)\(speedSuffix)x\n  Repeat Loops:\t \(loops)"
        messageBox(text, title: "TinyMac", style: .informational, icon: NSApp.applicationIconImage)
    }

    private func directorySize(_ url: URL) -> Int {
        var total = 0
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in e {
                total += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
        }
        return total
    }

    private func nothingRecorded() {
        messageBox("Nothing Recorded\n\nPress the blue button to start a new recording", title: "TinyMac", style: .informational)
    }

    // MARK: Release keys (start of recording and of every playback loop)

    private func releaseKeys() {
        injector.button(.left, down: false)                       // mouse_event(MOUSEEVENTF_LEFTUP)
        for vk in 0..<0x100 where vk != VK.capital && vk != VK.numLock && vk != VK.scroll {
            if VK.isDown(vk) { injector.key(vk, up: true) }
        }
        // SetKeyboardState(zeros) / GetAsyncKeyState flush / Scroll Lock reset have
        // no macOS counterpart (there is no Scroll Lock toggle state on a Mac).
        usleep(1000)
    }

    // MARK: Record (0x8002)

    private func cmdRecordToggle() {
        releaseKeys()
        if state == 0 {
            state = Self.cmdRecord
            buffer = nil
            index = 0
            let p = InputInjector.cursorLocation
            keyTable[0] = UInt8(truncatingIfNeeded: Int(p.x) + Int(p.y))
            for vk in 1...254 { keyTable[vk] = VK.isDown(vk) ? 1 : 0 }
            startTick = Self.tickCount()
            setTimer(Self.timerRecord, 10)
        } else {
            // Also reached while *playing*: like the original, this stops the
            // playback and cuts the recording at the current playback position.
            killTimer(Self.timerRecord)
            recordDuration = Self.tickCount() &- startTick
            state = 0
            window.title = displayName.isEmpty ? "TinyMac" : displayName
            if buffer != nil {
                var end = index
                var i = end != 0 ? end - 1 : 0
                // Drop the trailing click on our own Stop button.
                while i > 0 {
                    let r = rec(i)
                    if r.message == 0 { break }
                    if r.message == 0x201 && r.hwnd == ourHwnd { break }
                    i -= 1
                }
                if i != 0 { index = i; end = i }
                for z in end..<(end + 3) where z < buffer!.count { buffer![z] = EventMsg() }
            }
        }
        updateToolbarState()
    }

    /// WM_TIMER 0x3E9, every 10 ms: at most one key/button transition, else a mouse move.
    private func recordTick() {
        if buffer == nil || buffer!.isEmpty || index + 100 >= buffer!.count {
            if buffer == nil { buffer = [] }
            buffer!.append(contentsOf: [EventMsg](repeating: EventMsg(), count: 20000 / EventMsg.size))
        }
        var vk = 1
        var down: UInt8 = 0
        while vk < 0xFF {
            down = VK.isDown(vk) ? 1 : 0
            if keyTable[vk] != down { keyTable[vk] = down; break }
            vk += 1
        }
        let p = InputInjector.cursorLocation
        let x = Int32(clamping: Int(p.x.rounded(.down)))
        let y = Int32(clamping: Int(p.y.rounded(.down)))
        var message: UInt32 = 0
        var paramL: UInt32 = 0
        var paramH: UInt32 = 0
        if vk < 0xFF {
            switch vk {
            case VK.lButton:
                message = down == 1 ? 0x201 : 0x202
                paramL = UInt32(bitPattern: x); paramH = UInt32(bitPattern: y)
            case VK.rButton:
                message = down == 1 ? 0x204 : 0x205
                paramL = UInt32(bitPattern: x); paramH = UInt32(bitPattern: y)
            case VK.lShift:
                break   // VK_LSHIFT is ignored; VK_SHIFT already carries it
            default:
                message = down == 1 ? 0x100 : 0x101
                let scan = VK.mapVirtualKey(vk)
                paramL = (scan << 8) | UInt32(vk)
                paramH = scan
            }
        }
        if message == 0 {
            let sum = UInt8(truncatingIfNeeded: Int(x) &+ Int(y))
            guard x != 0, y != 0, sum != keyTable[0] else {
                setTimer(Self.timerRecord, 10)
                return
            }
            message = 0x200
            paramL = UInt32(bitPattern: x)
            paramH = UInt32(bitPattern: y)
            keyTable[0] = sum
        }
        let foreground: UInt32 = window.frame.contains(NSEvent.mouseLocation) || NSApp.isActive
            ? ourHwnd
            : UInt32(bitPattern: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
        buffer![index] = EventMsg(message: message, paramL: paramL, paramH: paramH, time: Self.tickCount(), hwnd: foreground)
        index += 1
        setTimer(Self.timerRecord, 10)
    }

    // MARK: Play (0x8003)

    private func cmdPlay(hi: Int) {
        if state == Self.cmdRecord { return }
        guard buffer != nil else { nothingRecorded(); return }
        if state == 0 {
            loopCounter = 0
            state = Self.cmdPlay
        } else {
            loopCounter += 1
        }
        releaseKeys()
        if hi == 0 && (loopCounter < loops || continuous) {
            startTick = Self.tickCount()
            index = 0
            setTimer(Self.timerPlay, 25)
            updateToolbarState()
            return
        }
        if compiled { postClose() }
        loopCounter = 0
        state = 0
        window.title = displayName.isEmpty ? "TinyMac" : displayName
        updateToolbarState()
    }

    /// WM_TIMER 0x3EA: replay one event, then wait for the recorded gap.
    private func playTick() {
        if VK.isDown(VK.pause) || VK.isDown(VK.scroll) { state = 0 }
        if state == 0 {
            if compiled { postClose() }
            updateToolbarState()
            return
        }
        let r = rec(index)
        switch r.message {
        case 0x100, 0x101:
            let vk = Int(r.paramL & 0xFF)
            if vk != VK.lShift { injector.key(vk, up: r.message == 0x101) }
        case 0x200:
            injector.move(to: CGPoint(x: Int(Int32(bitPattern: r.paramL)), y: Int(Int32(bitPattern: r.paramH))))
        case 0x201, 0x202:
            clicked = true
            injector.button(.left, down: r.message == 0x201)
            dragging = r.message == 0x201
        case 0x204, 0x205:
            injector.button(.right, down: r.message == 0x204)
            dragging = false
        default:
            break
        }
        index += 1

        if index >= (buffer?.count ?? 0) || rec(index).message == 0 {
            if clicked { usleep(useconds_t(NSEvent.doubleClickInterval * 1_000_000 / 2)) }
            postCommand(state & 0xFFFF)
            return
        }

        if speed < 100 {
            var delay = rec(index).time &- rec(index - 1).time
            if speed == 1 {
                delay = delay &+ delay
            } else if speed >= 2 {
                delay /= UInt32(speed)
            }
            setTimer(Self.timerPlay, delay)
            return
        }

        // 100x: collapse runs of mouse moves, replaying every 6th one.
        var moved = false
        while !dragging && rec(index).message == 0x200 {
            if index % 6 != 0 && rec(index + 1).message == 0x200 {
                index += 1
                continue
            }
            let m = rec(index)
            injector.move(to: CGPoint(x: Int(Int32(bitPattern: m.paramL)), y: Int(Int32(bitPattern: m.paramH))))
            usleep(1000)
            moved = true
            index += 1
        }
        setTimer(Self.timerPlay, moved ? 75 : 1)
    }

    private func postClose() {
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    // MARK: Hotkeys + title (timer 0x3ED, every 50 ms)

    private func hotkeyDown(_ setting: UInt8, letter: Int) -> Bool {
        switch setting {
        case 0: return VK.isDown(letter) && VK.isDown(VK.control) && VK.isDown(VK.shift) && VK.isDown(VK.menu)
        case 1: return VK.isDown(VK.snapshot)
        case 8: return VK.isDown(VK.f8)
        case 12: return VK.isDown(VK.f12)
        default: return false
        }
    }

    private func hotkeyTick() {
        // The original relies on the synthetic key-ups sent at record/play start to
        // avoid re-triggering while the combination is held; macOS keeps reporting
        // the physical key state, so trigger on the press edge instead.
        let rec = hotkeyDown(recordKey, letter: VK.keyR)
        let play = !rec && hotkeyDown(playKey, letter: VK.keyP)
        if rec && !hotkeyLatch.record {
            postCommand(Self.cmdRecord)
        } else if play && !hotkeyLatch.play {
            usleep(150_000)
            postCommand(Self.cmdPlay, hi: state == Self.cmdPlay ? 1 : 0)
        }
        hotkeyLatch = (rec, play)

        var title = ""
        if state == Self.cmdRecord {
            let s = (Self.tickCount() &- startTick) / 1000
            title = String(format: "REC %02d:%02d", s / 60, s % 60)
        } else if state == Self.cmdPlay {
            let s = (Self.tickCount() &- startTick) / 1000
            title = String(format: "%02d:%02d (%d/%d%@)", s / 60, s % 60, loopCounter + 1,
                           continuous ? 0 : loops, continuous ? "*" : "")
        } else if !displayName.isEmpty {
            title = displayName
        }
        if title.isEmpty { title = "TinyMac" }
        if window.title != title { window.title = title }
    }

    private func updateToolbarState() {
        toolbar.isRecording = state == Self.cmdRecord
        toolbar.isPlaying = state == Self.cmdPlay
    }

    // MARK: - Prefs menu (0x8005)

    private func showPrefsMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ id: Int, checked: Bool = false, enabled: Bool = true, to m: NSMenu? = nil) {
            let item = NSMenuItem(title: title, action: #selector(menuCommand(_:)), keyEquivalent: "")
            item.target = self
            item.tag = id
            item.state = checked ? .on : .off
            item.isEnabled = enabled
            (m ?? menu).addItem(item)
        }
        add("Play Speed:   ½x", 0x8006, checked: speed == 1)
        add("Play Speed:   1x", 0x8007, checked: speed == 0)
        add("Play Speed:   2x", 0x8008, checked: speed == 2)
        add("Play Speed:   100x", 0x800A, checked: speed == 100)
        add("Play Custom Speed:  \(speedCustom)x", 0x8009, checked: ![0, 1, 2, 100].contains(speed))
        add("Set Custom Speed...", 0x8019)
        menu.addItem(.separator())
        add("Continuous Playback", 0x800B, checked: continuous)
        add("Set Playback Loops...  (\(max(loops, 1)))", 0x800C)
        menu.addItem(.separator())

        let recMenu = NSMenu()
        recMenu.autoenablesItems = false
        add("Control + Shift + Alt (⌥) + R", 0x800F, checked: recordKey == 0, to: recMenu)
        add("Print Screen  (F13)", 0x8010, checked: recordKey == 1, to: recMenu)
        add("F8", 0x8011, checked: recordKey == 8, to: recMenu)
        add("F12", 0x8012, checked: recordKey == 12, to: recMenu)
        let recItem = NSMenuItem(title: "Recording Hotkey", action: nil, keyEquivalent: "")
        recItem.submenu = recMenu
        menu.addItem(recItem)

        let playMenu = NSMenu()
        playMenu.autoenablesItems = false
        add("Control + Shift + Alt (⌥) + P", 0x8013, checked: playKey == 0, to: playMenu)
        add("Print Screen  (F13)", 0x8014, checked: playKey == 1, to: playMenu)
        add("F8", 0x8015, checked: playKey == 8, to: playMenu)
        add("F12", 0x8016, checked: playKey == 12, to: playMenu)
        playMenu.addItem(.separator())
        add("•  Hint:  Press {PAUSE} (F15) or {ScrollLock} (F14) to stop playbacks", 0x800E, enabled: false, to: playMenu)
        let playItem = NSMenuItem(title: "Playback Hotkey", action: nil, keyEquivalent: "")
        playItem.submenu = playMenu
        menu.addItem(playItem)
        menu.addItem(.separator())

        add("Always on Top", 0x8017, checked: topmost)
        add("Show Captions", 0x8018, checked: hideCaptions == 0)
        add("Use Custom Toolbar...", 0x801A, checked: customToolbar)
        add("Use Default Toolbar", 0x801B, checked: !customToolbar)
        menu.addItem(.separator())
        add("TinyTask Website", 0x800D)
        add("About TinyMac", 0x800E)

        // At the cursor when it is over the Prefs button, else at the window's bottom-right.
        let mouse = NSEvent.mouseLocation
        let f = window.frame
        var p = toolbar.convert(window.convertPoint(fromScreen: mouse), from: nil)
        if !(f.contains(mouse) && mouse.x >= f.maxX - CGFloat(toolbar.padding + toolbar.buttonWidth)) {
            p = NSPoint(x: toolbar.bounds.maxX - CGFloat(toolbar.buttonWidth), y: toolbar.bounds.maxY - 9)
        }
        menu.popUp(positioning: nil, at: p, in: toolbar)
    }

    @objc private func menuCommand(_ sender: NSMenuItem) {
        postCommand(sender.tag)
    }

    private func hotkeyConflict() {
        messageBox("Hotkey Conflict", title: "TinyMac", style: .warning)
    }

    private func askLoops() {
        if let s = inputBox(title: "Set Playback Loops", prompt: "Set the number of playback loops:", value: "\(max(loops, 1))") {
            let v = atoiLike(s)
            loops = v > 1 ? v : 1
            continuous = false
        }
    }

    private func askCustomSpeed() {
        if let s = inputBox(title: "Set Custom Speed", prompt: "Playback speed multiplier (1-100):", value: "\(speedCustom)") {
            let v = atoiLike(s)
            speedCustom = v < 1 ? 1 : min(v, 1000)
            speed = speedCustom
        }
    }

    private func openWebsite() {
        if !NSWorkspace.shared.open(URL(string: "https://www.tinytask.net")!) {
            messageBox("Unable to connect to \"www.tinytask.net\"", title: "TinyMac", style: .warning)
        }
    }

    /// About box. The original adds a blue, double-size "tinytask.net" label to the
    /// message box (subclassed STATIC, id 0x800D) that opens the website when clicked.
    private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "TinyMac \(Self.appVersion)"
        alert.informativeText = "macOS port of TinyTask \(Self.version) (Copyright © 2019, www.tinytask.net). Not affiliated with the TinyTask author.\n\n•••> If you like this software, please keep it alive by donating at the website above. Thank You!!   : )"
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        let link = NSButton(title: "", target: self, action: #selector(menuCommand(_:)))
        link.tag = 0x800D
        link.isBordered = false
        link.attributedTitle = NSAttributedString(string: "tinytask.net", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize * 2),
            .foregroundColor: NSColor(srgbRed: 0x07 / 255.0, green: 0x8D / 255.0, blue: 0xD7 / 255.0, alpha: 1),
        ])
        link.sizeToFit()
        link.addCursorRect(link.bounds, cursor: .pointingHand)
        alert.accessoryView = link
        alert.window.title = "About TinyMac"
        alert.window.level = topmost ? .floating : .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: Toolbar image

    private func chooseCustomToolbar() {
        let current = ini.string(Self.section, "toolbar_image", default: "")
        let panel = NSOpenPanel()
        panel.title = "Use Custom Toolbar"
        panel.allowedContentTypes = [.bmp, .png, .image]
        if !current.isEmpty { panel.directoryURL = URL(fileURLWithPath: (current as NSString).deletingLastPathComponent) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ini.write(Self.section, "toolbar_image", url.path)
        loadToolbar()
        resizeToToolbar()
    }

    /// Load the custom strip (7 sprites) or the stock toolbar.
    private func loadToolbar() {
        let path = ini.string(Self.section, "toolbar_image", default: "")
        toolbar.customSprites = nil
        customToolbar = false
        if !path.isEmpty {
            customToolbar = true
            let rep = NSImage(contentsOfFile: path).flatMap { img -> NSBitmapImageRep? in
                img.representations.compactMap { $0 as? NSBitmapImageRep }.first
                    ?? img.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
            }
            let screenW = Int((NSScreen.main?.frame.width ?? 0) * (NSScreen.main?.backingScaleFactor ?? 1))
            if let rep, rep.pixelsHigh >= 10, rep.pixelsWide / 7 >= 10, rep.pixelsWide <= screenW,
               let sprites = makeToolbarSprites(from: rep), sprites.count == 7 {
                toolbar.customSprites = sprites
                toolbar.buttonWidth = rep.pixelsWide / 7
                toolbar.buttonHeight = rep.pixelsHigh
            } else {
                messageBox("Invalid toolbar BMP (too small or big)\n\nReverting to stock toolbar", title: path, style: .critical)
                ini.write(Self.section, "toolbar_image", nil)
                customToolbar = false
            }
        }
        if !customToolbar {
            toolbar.buttonWidth = ToolbarView.defaultButtonWidth
            toolbar.buttonHeight = ToolbarView.defaultButtonHeight
        }
        toolbar.needsDisplay = true
    }

    private func setTopLeft(_ p: NSPoint) {
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: toolbar.contentSize))
        window.setFrame(NSRect(x: p.x, y: screenH - p.y - frame.height, width: frame.width, height: frame.height), display: true)
    }

    private func resizeToToolbar() {
        guard let window else { return }
        let old = window.frame
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: toolbar.contentSize))
        window.setFrame(NSRect(x: old.minX, y: old.maxY - frame.height, width: frame.width, height: frame.height), display: true)
        toolbar.needsDisplay = true
    }

    // MARK: - Dialogs

    @discardableResult
    func messageBox(_ text: String, title: String, style: NSAlert.Style, buttons: [String] = ["OK"], icon: NSImage? = nil) -> Int {
        let alert = NSAlert()
        let parts = text.trimmingCharacters(in: .whitespaces).components(separatedBy: "\n\n")
        alert.messageText = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        alert.informativeText = parts.dropFirst().joined(separator: "\n\n")
        alert.alertStyle = style
        if let icon { alert.icon = icon }
        for b in buttons { alert.addButton(withTitle: b) }
        alert.window.title = title
        alert.window.level = topmost ? .floating : .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    private let digitsOnly = DigitsOnlyFieldDelegate()

    private func inputBox(title: String, prompt: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        // ES_NUMBER | ES_CENTER edit control; its text is read into a 32-byte buffer.
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.stringValue = value
        field.alignment = .center
        field.delegate = digitsOnly
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.window.level = topmost ? .floating : .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { field.selectText(nil) }
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    // MARK: - Menu bar

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let app = NSMenu()
        let about = NSMenuItem(title: "About TinyMac", action: #selector(menuCommand(_:)), keyEquivalent: "")
        about.target = self
        about.tag = 0x800E
        app.addItem(about)
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: "Hide TinyMac", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: "Quit TinyMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = app
        NSApp.mainMenu = main
    }
}

/// Keeps only digits (ES_NUMBER) and at most 31 characters (the 0x1F-byte read buffer).
final class DigitsOnlyFieldDelegate: NSObject, NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let filtered = String(field.stringValue.filter { $0.isASCII && $0.isNumber }.prefix(31))
        if filtered != field.stringValue { field.stringValue = filtered }
    }
}
