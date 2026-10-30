import AppKit

/// The six-button toolbar (Open, Save, Rec, Play, .app, Prefs).
///
/// Geometry follows TinyTask 1.77: button i sits at x = pad + i * (w + pad),
/// y = pad; the client area is pad + 6 * (w + pad) wide and h + 2 * pad tall,
/// minus `hide_captions` (12 px) when captions are hidden. A custom toolbar
/// image is a strip of 7 equal sprites, the 7th replacing "Rec" while recording,
/// with the colour of pixel (0, 0) treated as transparent.
final class ToolbarView: NSView {
    weak var controller: TinyMacController?

    static let defaultButtonWidth = 52
    static let defaultButtonHeight = 50

    var buttonWidth = ToolbarView.defaultButtonWidth
    var buttonHeight = ToolbarView.defaultButtonHeight
    var padding = 5
    var hideCaptions = 0
    var customSprites: [NSImage]?   // 7 sprites when a custom toolbar is in use
    var isRecording = false { didSet { needsDisplay = true } }
    var isPlaying = false { didSet { needsDisplay = true } }

    private var hovered: Int?
    private var pressed: Int?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var contentSize: NSSize {
        NSSize(width: padding + 6 * (buttonWidth + padding),
               height: buttonHeight + 2 * padding - hideCaptions)
    }

    func buttonRect(_ i: Int) -> NSRect {
        NSRect(x: padding + i * (buttonWidth + padding), y: padding,
               width: buttonWidth, height: buttonHeight - hideCaptions)
    }

    /// WM_LBUTTONDOWN hit test: (x - pad/2) / (w + pad), clamped to 0...5.
    func buttonIndex(atX x: CGFloat) -> Int {
        let i = (Int(x) - padding / 2) / (buttonWidth + padding)
        return min(max(i, 0), 5)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = (0..<6).first { buttonRect($0).insetBy(dx: -CGFloat(padding) / 2, dy: -CGFloat(padding)).contains(p) }
        if i != hovered { hovered = i; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = buttonIndex(atX: p.x)
        pressed = i
        needsDisplay = true
        controller?.postCommand(0x8000 + i)
    }

    override func mouseUp(with event: NSEvent) {
        pressed = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 0x1F: controller?.postCommand(0x8000)        // 'O'
        case 0x24, 0x4C: controller?.postCommand(0x8005)  // Return
        default: super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    private struct Item { let symbol: String; let caption: String; let tint: NSColor }

    private func item(_ i: Int) -> Item {
        switch i {
        case 0: return Item(symbol: "folder", caption: "Open", tint: .systemGray)
        case 1: return Item(symbol: "square.and.arrow.down", caption: "Save", tint: .systemPurple)
        case 2:
            return isRecording
                ? Item(symbol: "record.circle.fill", caption: "*Rec*", tint: .systemRed)
                : Item(symbol: "record.circle", caption: "Rec", tint: .systemBlue)
        case 3:
            return isPlaying
                ? Item(symbol: "arrow.triangle.2.circlepath.circle.fill", caption: "Play", tint: .systemGreen)
                : Item(symbol: "arrow.triangle.2.circlepath", caption: "Play", tint: .systemGreen)
        case 4: return Item(symbol: "shippingbox", caption: ".app", tint: .systemBlue)
        default: return Item(symbol: "gearshape", caption: "Prefs", tint: .systemGray)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for i in 0..<6 {
            let r = buttonRect(i)
            let active = (i == 2 && isRecording) || (i == 3 && isPlaying)
            if pressed == i || hovered == i || active {
                let bg = NSBezierPath(roundedRect: r.insetBy(dx: -1, dy: -1), xRadius: 8, yRadius: 8)
                let base: NSColor = active ? item(i).tint : .labelColor
                base.withAlphaComponent(pressed == i ? 0.22 : (active ? 0.16 : 0.08)).setFill()
                bg.fill()
            }
            if let sprites = customSprites {
                drawSprite(sprites[i == 2 && isRecording ? 6 : i], in: r)
            } else {
                drawDefault(i, in: r)
            }
        }
    }

    private func drawSprite(_ img: NSImage, in r: NSRect) {
        // BitBlt of the top (h - hide_captions) rows of the sprite.
        let srcH = img.size.height * CGFloat(buttonHeight - hideCaptions) / CGFloat(buttonHeight)
        img.draw(in: r, from: NSRect(x: 0, y: img.size.height - srcH, width: img.size.width, height: srcH),
                 operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
    }

    private func drawDefault(_ i: Int, in r: NSRect) {
        let it = item(i)
        let captionH: CGFloat = 13
        let iconArea = NSRect(x: r.minX, y: r.minY, width: r.width,
                              height: hideCaptions > 0 ? r.height : r.height - captionH)
        let cfg = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
            .applying(.init(paletteColors: [it.tint]))
        if let img = NSImage(systemSymbolName: it.symbol, accessibilityDescription: it.caption)?.withSymbolConfiguration(cfg) {
            let s = img.size
            img.draw(in: NSRect(x: iconArea.midX - s.width / 2, y: iconArea.midY - s.height / 2, width: s.width, height: s.height),
                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        guard hideCaptions == 0 else { return }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let color: NSColor = (i == 2 && isRecording) ? .systemRed : (i == 2 || i == 3 ? it.tint : .labelColor)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        (it.caption as NSString).draw(in: NSRect(x: r.minX - 4, y: r.maxY - captionH - 1, width: r.width + 8, height: captionH), withAttributes: attrs)
    }
}

/// Splits a toolbar strip into 7 sprites, keying out the colour of pixel (0, 0).
func makeToolbarSprites(from rep: NSBitmapImageRep) -> [NSImage]? {
    let w = rep.pixelsWide, h = rep.pixelsHigh
    guard let rgb = rep.converting(to: .sRGB, renderingIntent: .default),
          let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: w * 4, bitsPerPixel: 32) else { return nil }
    func pixel(_ x: Int, _ y: Int) -> [Int] {
        var p = [Int](repeating: 0, count: max(rgb.samplesPerPixel, 4))
        rgb.getPixel(&p, atX: x, y: y)
        return p
    }
    let key = pixel(0, 0)
    for y in 0..<h {
        for x in 0..<w {
            let p = pixel(x, y)
            let transparent = p[0] == key[0] && p[1] == key[1] && p[2] == key[2]
            var o = transparent ? [0, 0, 0, 0] : [p[0], p[1], p[2], 255]
            out.setPixel(&o, atX: x, y: y)
        }
    }
    guard let full = out.cgImage else { return nil }
    let sw = w / 7
    return (0..<7).compactMap { i in
        guard let part = full.cropping(to: CGRect(x: i * sw, y: 0, width: sw, height: h)) else { return nil }
        return NSImage(cgImage: part, size: NSSize(width: sw, height: h))
    }
}
