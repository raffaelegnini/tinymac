import AppKit

// Renders the TinyMac app icon (blue record button on a rounded tile) into an .iconset.
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                   (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let path = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.99, alpha: 1),
               ending: NSColor(calibratedRed: 0.78, green: 0.84, blue: 0.95, alpha: 1))!.draw(in: path, angle: -90)
    NSColor(calibratedWhite: 0, alpha: 0.12).setStroke()
    path.lineWidth = max(1, s * 0.006)
    path.stroke()
    let ring = NSBezierPath(ovalIn: tile.insetBy(dx: s * 0.17, dy: s * 0.17))
    NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.85, alpha: 1).setStroke()
    ring.lineWidth = s * 0.04
    ring.stroke()
    let dot = NSBezierPath(ovalIn: tile.insetBy(dx: s * 0.26, dy: s * 0.26))
    NSGradient(starting: NSColor(calibratedRed: 0.35, green: 0.75, blue: 1, alpha: 1),
               ending: NSColor(calibratedRed: 0.05, green: 0.40, blue: 0.95, alpha: 1))!.draw(in: dot, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
