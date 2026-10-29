// gifcap-icon: draw the gifcap.app icon into an .iconset directory for iconutil.
// usage: swift gifcap-icon.swift out.iconset
// The design: a selection marquee with a red record dot around "GIF".

import AppKit

func draw(in ctx: CGContext) {
    // Everything is laid out on a 1024 canvas; the caller scales the context.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    // Rounded square with the standard macOS icon margin, plus a soft shadow.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill()
    shape.fill()
    ctx.restoreGState()
    NSGradient(starting: NSColor(srgbRed: 0.42, green: 0.36, blue: 1.00, alpha: 1),
               ending: NSColor(srgbRed: 0.62, green: 0.16, blue: 0.80, alpha: 1))!.draw(in: shape, angle: -90)

    // Corner brackets of a selection marquee.
    let m = NSRect(x: 230, y: 250, width: 564, height: 470)
    let len: CGFloat = 120
    let brackets = NSBezierPath()
    brackets.lineWidth = 34
    brackets.lineCapStyle = .round
    brackets.lineJoinStyle = .round
    for (x, y, dx, dy) in [(m.minX, m.minY, 1.0, 1.0), (m.maxX, m.minY, -1.0, 1.0),
                           (m.minX, m.maxY, 1.0, -1.0), (m.maxX, m.maxY, -1.0, -1.0)] {
        brackets.move(to: NSPoint(x: x, y: y + dy * len))
        brackets.line(to: NSPoint(x: x, y: y))
        brackets.line(to: NSPoint(x: x + dx * len, y: y))
    }
    NSColor.white.setStroke()
    brackets.stroke()

    // "GIF" in the middle of the marquee.
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 220, weight: .heavy),
        .foregroundColor: NSColor.white,
        .kern: 6,
    ]
    let text = "GIF" as NSString
    let size = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: m.midX - size.width / 2, y: m.midY - size.height / 2 - 6), withAttributes: attrs)

    // Red record dot over the top-right bracket.
    let dot = NSRect(x: 724, y: 650, width: 140, height: 140)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: dot).fill()
    NSColor.systemRed.setFill()
    NSBezierPath(ovalIn: dot.insetBy(dx: 16, dy: 16)).fill()
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift gifcap-icon.swift out.iconset\n".data(using: .utf8)!)
    exit(1)
}
let dir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
        draw(in: ctx)
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir + "/" + name))
    }
}
