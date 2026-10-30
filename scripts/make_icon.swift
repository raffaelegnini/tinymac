import AppKit

// Renders the app icon into an .iconset.
//   swift make_icon.swift <out.iconset>        TinyMac: blue record button on a light tile
//   swift make_icon.swift <out.iconset> plus   TinyMac Plus: same button on a dark tile, orange, with a "+" badge
let out = CommandLine.arguments[1]
let plus = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "plus"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: 1) }

let tileColors = plus ? (rgb(0.20, 0.19, 0.26), rgb(0.09, 0.08, 0.13)) : (rgb(0.93, 0.95, 0.99), rgb(0.78, 0.84, 0.95))
let ringColor = plus ? rgb(1.00, 0.55, 0.20) : rgb(0.20, 0.45, 0.85)
let dotColors = plus ? (rgb(1.00, 0.72, 0.30), rgb(0.95, 0.30, 0.25)) : (rgb(0.35, 0.75, 1), rgb(0.05, 0.40, 0.95))

for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                   (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let path = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: tileColors.0, ending: tileColors.1)!.draw(in: path, angle: -90)
    NSColor(calibratedWhite: 0, alpha: 0.12).setStroke()
    path.lineWidth = max(1, s * 0.006)
    path.stroke()
    let ring = NSBezierPath(ovalIn: tile.insetBy(dx: s * 0.17, dy: s * 0.17))
    ringColor.setStroke()
    ring.lineWidth = s * 0.04
    ring.stroke()
    let dot = NSBezierPath(ovalIn: tile.insetBy(dx: s * 0.26, dy: s * 0.26))
    NSGradient(starting: dotColors.0, ending: dotColors.1)!.draw(in: dot, angle: -90)
    if plus {
        // "+" badge in the top-right corner, kept inside the tile: macOS 26 puts icons
        // whose outline is not the standard rounded square into a grey container.
        let d = s * 0.20
        let badge = NSRect(x: tile.maxX - s * 0.17 - d / 2, y: tile.maxY - s * 0.17 - d / 2, width: d, height: d)
        tileColors.1.setFill()
        NSBezierPath(ovalIn: badge.insetBy(dx: -s * 0.015, dy: -s * 0.015)).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: badge).fill()
        let arm = d * 0.56, bar = d * 0.16
        rgb(0.95, 0.40, 0.22).setFill()
        NSBezierPath(roundedRect: NSRect(x: badge.midX - arm / 2, y: badge.midY - bar / 2, width: arm, height: bar),
                     xRadius: bar / 2, yRadius: bar / 2).fill()
        NSBezierPath(roundedRect: NSRect(x: badge.midX - bar / 2, y: badge.midY - arm / 2, width: bar, height: arm),
                     xRadius: bar / 2, yRadius: bar / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
