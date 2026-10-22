// Renders the AgentSweep app icon (an accretion ring around a black core) into an .iconset folder.
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
}

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px)
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // Squircle plate
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0x141B2E).cgColor, color(0x05070D).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    let c = CGPoint(x: 512, y: 512)
    // Glow
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [color(0x8FD8FF, 0.0).cgColor, color(0x8FD8FF, 0.35).cgColor, color(0xC084FC, 0.15).cgColor, color(0x5BA8FF, 0).cgColor] as CFArray,
                          locations: [0.25, 0.5, 0.62, 1])!
    ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: 400, options: [])

    // Ring of colour wedges
    let stops = [color(0x8FD8FF), color(0xC084FC), color(0x5BA8FF), color(0x8FD8FF)]
    let n = 360
    for i in 0..<n {
        let t = CGFloat(i) / CGFloat(n)
        let seg = t * 3, k = min(2, Int(seg))
        ctx.setFillColor(mix(stops[k], stops[k + 1], seg - CGFloat(k)).cgColor)
        let a0 = t * 2 * .pi, a1 = (t + 1.0 / CGFloat(n)) * 2 * .pi + 0.004
        let p = CGMutablePath()
        p.addArc(center: c, radius: 300, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: c, radius: 205, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        ctx.addPath(p); ctx.fillPath()
    }
    // Ticks
    ctx.setStrokeColor(color(0x8FD8FF, 0.45).cgColor)
    ctx.setLineWidth(5)
    for i in 0..<24 {
        let a = CGFloat(i) / 24 * 2 * .pi
        ctx.move(to: CGPoint(x: c.x + cos(a) * 330, y: c.y + sin(a) * 330))
        ctx.addLine(to: CGPoint(x: c.x + cos(a) * (i % 6 == 0 ? 365 : 348), y: c.y + sin(a) * (i % 6 == 0 ? 365 : 348)))
    }
    ctx.strokePath()
    // Core
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - 190, y: c.y - 190, width: 380, height: 380))
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
    ctx.setLineWidth(6)
    ctx.addArc(center: c, radius: 196, startAngle: 0.6, endAngle: 2.4, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
