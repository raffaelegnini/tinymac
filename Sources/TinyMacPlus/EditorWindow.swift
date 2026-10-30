import AppKit
import TinyMacCore

/// Event list editor: change delays and positions, delete events, insert waits, trim.
///
/// It edits a copy of the recording; Apply writes it back to the engine, so the
/// result is still a plain TinyTask recording that Save writes as .rec.
final class EditorWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private weak var controller: PlusController?
    private let window: NSWindow
    private let table = NSTableView()
    private let summary = NSTextField(labelWithString: "")
    private var records: [EventMsg] = []
    private var delays: [UInt32] = []   // delays[i] = gap before record i, in ms
    private var baseTime: UInt32 = 0
    private var dirty = false { didSet { updateSummary() } }

    var isVisible: Bool { window.isVisible }

    init(controller: PlusController) {
        self.controller = controller
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Edit Recording"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 300)
        window.delegate = self
        build()
    }

    private func build() {
        let columns: [(String, String, CGFloat)] = [
            ("index", "#", 60), ("time", "Time (s)", 80), ("delay", "Delay (ms)", 90),
            ("event", "Event", 150), ("x", "X / Key", 110), ("y", "Y", 70),
        ]
        for (id, title, width) in columns {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = width
            c.isEditable = ["delay", "x", "y"].contains(id)
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.style = .fullWidth
        table.rowHeight = 20

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        func button(_ title: String, _ action: Selector, key: String = "") -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            b.keyEquivalent = key
            return b
        }
        let del = button("Delete", #selector(deleteSelected))
        del.keyEquivalent = "\u{8}"
        let edits = NSStackView(views: [
            del,
            button("Insert Wait…", #selector(insertWait)),
            button("Set Delay…", #selector(setDelay)),
            button("Scale Delays…", #selector(scaleDelays)),
            button("Trim Before", #selector(trimBefore)),
            button("Trim After", #selector(trimAfter)),
        ])
        edits.spacing = 6
        let apply = button("Apply", #selector(apply), key: "\r")
        let revert = button("Revert", #selector(reload))
        let bottom = NSStackView(views: [summary, NSView(), revert, apply])
        bottom.spacing = 8
        summary.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [edits, scroll, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -12),
            bottom.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
        ])
        window.contentView = content
    }

    func show() {
        reload()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func reload() {
        records = controller?.records ?? []
        baseTime = records.first?.time ?? 0
        delays = records.indices.map { $0 == 0 ? 0 : records[$0].time &- records[$0 - 1].time }
        window.title = "Edit Recording — \(controller?.displayName.isEmpty == false ? controller!.displayName : "untitled")"
        dirty = false
        table.reloadData()
    }

    @objc private func apply() {
        guard let controller, controller.state == 0 else { NSSound.beep(); return }
        var t = baseTime
        let rebuilt = records.indices.map { i -> EventMsg in
            t = t &+ delays[i]
            var r = records[i]
            r.time = t
            return r
        }
        controller.replaceRecording(rebuilt)
        dirty = false
    }

    private func updateSummary() {
        let total = delays.reduce(0) { $0 + Int($1) }
        summary.stringValue = String(format: "%d events · %.1f s%@", records.count, Double(total) / 1000, dirty ? " · not applied" : "")
    }

    private var selection: [Int] { table.selectedRowIndexes.sorted() }

    private func changed(select rows: IndexSet? = nil) {
        dirty = true
        table.reloadData()
        if let rows { table.selectRowIndexes(rows, byExtendingSelection: false) }
    }

    // MARK: Edits

    @objc private func deleteSelected() {
        let rows = selection
        guard !rows.isEmpty else { NSSound.beep(); return }
        for i in rows.reversed() {
            // Keep the total duration: the gap before a removed event moves to the next one.
            if i + 1 < records.count { delays[i + 1] &+= delays[i] }
            records.remove(at: i)
            delays.remove(at: i)
        }
        if !delays.isEmpty { delays[0] = 0 }
        let next = min(rows.first!, records.count - 1)
        changed(select: next >= 0 ? IndexSet(integer: next) : nil)
    }

    @objc private func insertWait() {
        guard let i = selection.first, let ms = ask("Insert Wait", "Pause before the selected event, in milliseconds:", "1000") else {
            if selection.isEmpty { NSSound.beep() }
            return
        }
        delays[i] &+= UInt32(ms)
        changed(select: IndexSet(integer: i))
    }

    @objc private func setDelay() {
        let rows = selection
        guard !rows.isEmpty, let ms = ask("Set Delay", "Delay before each selected event, in milliseconds:", "\(delays[rows[0]])") else {
            if rows.isEmpty { NSSound.beep() }
            return
        }
        for i in rows where i > 0 { delays[i] = UInt32(ms) }
        changed(select: IndexSet(rows))
    }

    @objc private func scaleDelays() {
        var rows = selection
        if rows.count < 2 { rows = Array(records.indices) }
        guard !rows.isEmpty, let pct = ask("Scale Delays", "Percentage of the current delays (50 = twice as fast, 200 = half speed). Applies to the selection, or to everything when one row or none is selected:", "50") else { return }
        for i in rows { delays[i] = UInt32(min(Double(delays[i]) * Double(pct) / 100, Double(UInt32.max))) }
        changed(select: IndexSet(selection))
    }

    @objc private func trimBefore() {
        guard let i = selection.first, i > 0 else { NSSound.beep(); return }
        baseTime = baseTime &+ delays[0...i].reduce(0, &+)
        records.removeFirst(i)
        delays.removeFirst(i)
        delays[0] = 0
        changed(select: IndexSet(integer: 0))
    }

    @objc private func trimAfter() {
        guard let i = selection.last, i + 1 < records.count else { NSSound.beep(); return }
        records.removeSubrange((i + 1)...)
        delays.removeSubrange((i + 1)...)
        changed(select: IndexSet(integer: i))
    }

    private func ask(_ title: String, _ prompt: String, _ value: String) -> Int? {
        guard let controller, let s = controller.inputBox(title: title, prompt: prompt, value: value) else { return nil }
        return max(0, atoiLike(s))
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { records.count }

    private func isMouse(_ r: EventMsg) -> Bool { [0x200, 0x201, 0x202, 0x204, 0x205, ScrollRecord.message].contains(r.message) }

    private func eventName(_ r: EventMsg) -> String {
        switch r.message {
        case 0x100: return "Key Down"
        case 0x101: return "Key Up"
        case 0x200: return "Mouse Move"
        case 0x201: return "Left Down"
        case 0x202: return "Left Up"
        case 0x204: return "Right Down"
        case 0x205: return "Right Up"
        case ScrollRecord.message: return "Scroll"
        default: return String(format: "0x%X", r.message)
        }
    }

    func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
        let r = records[row]
        switch column?.identifier.rawValue {
        case "index": return row + 1
        case "time":
            let ms = delays[0...row].reduce(0) { $0 + Int($1) }
            return String(format: "%.3f", Double(ms) / 1000)
        case "delay": return delays[row]
        case "event": return eventName(r)
        case "x":
            if r.message == 0x100 || r.message == 0x101 { return KeyNames.name(Int(r.paramL & 0xFF)) }
            if r.message == ScrollRecord.message {
                let d = ScrollRecord.deltas(r)
                return "↕ \(d.dy)  ↔ \(d.dx)"
            }
            return Int(Int32(bitPattern: r.paramL))
        case "y":
            guard isMouse(r), r.message != ScrollRecord.message else { return "" }
            return Int(Int32(bitPattern: r.paramH))
        default: return nil
        }
    }

    func tableView(_ tableView: NSTableView, shouldEdit column: NSTableColumn?, row: Int) -> Bool {
        switch column?.identifier.rawValue {
        case "delay": return row > 0
        case "x", "y": return isMouse(records[row]) && records[row].message != ScrollRecord.message
        default: return false
        }
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for column: NSTableColumn?, row: Int) {
        let v = atoiLike("\(object ?? "")")
        switch column?.identifier.rawValue {
        case "delay": delays[row] = UInt32(max(0, v))
        case "x": records[row].paramL = UInt32(bitPattern: Int32(clamping: v))
        case "y": records[row].paramH = UInt32(bitPattern: Int32(clamping: v))
        default: return
        }
        changed(select: IndexSet(integer: row))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard dirty, let controller else { return true }
        let answer = controller.messageBox("Apply your changes to the recording?", title: "Edit Recording",
                                           style: .warning, buttons: ["Apply", "Discard", "Cancel"])
        if answer == 2 { return false }
        if answer == 0 { apply() }
        return true
    }
}
