import AppKit

/// Floating, click-through panel in the top-right corner showing recording or playback progress.
final class ProgressHUD {
    private let panel: NSPanel
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 74),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let fx = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        fx.material = .hudWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 12
        panel.contentView = fx

        title.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.style = .bar
        bar.controlSize = .small
        for v in [title, detail, bar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            fx.addSubview(v)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: fx.leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: fx.trailingAnchor, constant: -14),
            title.topAnchor.constraint(equalTo: fx.topAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            bar.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            detail.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 4),
        ])
    }

    func show(title t: String, detail d: String, progress: Double?) {
        title.stringValue = t
        detail.stringValue = d
        bar.isHidden = progress == nil
        bar.doubleValue = progress ?? 0
        if !panel.isVisible {
            if let screen = NSScreen.main?.visibleFrame {
                panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - panel.frame.width - 16, y: screen.maxY - 16))
            }
            panel.orderFrontRegardless()
        }
    }

    func hide() { panel.orderOut(nil) }
}

/// Big "3 · 2 · 1" in the middle of the screen before a recording starts.
final class CountdownOverlay {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var timer: Timer?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 160, height: 160),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let fx = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        fx.material = .hudWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 32
        panel.contentView = fx
        label.font = .monospacedDigitSystemFont(ofSize: 88, weight: .bold)
        label.alignment = .center
        label.textColor = .systemRed
        label.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: fx.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: fx.centerYAnchor),
        ])
    }

    var isRunning: Bool { timer != nil }

    func run(seconds: Int, completion: @escaping () -> Void) {
        var left = seconds
        label.stringValue = "\(left)"
        panel.center()
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            left -= 1
            if left > 0 {
                self?.label.stringValue = "\(left)"
            } else {
                t.invalidate()
                self?.timer = nil
                self?.panel.orderOut(nil)
                completion()
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
    }
}
