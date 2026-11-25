// Draws the app icon: a curve easing out, with a dot sliding down it.
import AppKit
let out = CommandLine.arguments[1]
for (size, name) in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),(128,"128x128"),(256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    let tile = NSBezierPath(roundedRect: NSRect(x: 100*s, y: 100*s, width: 824*s, height: 824*s), xRadius: 186*s, yRadius: 186*s)
    NSGradient(starting: NSColor(red: 0.06, green: 0.42, blue: 0.40, alpha: 1), ending: NSColor(red: 0.05, green: 0.19, blue: 0.27, alpha: 1))!.draw(in: tile, angle: -90)
    let slope = NSBezierPath()
    slope.move(to: NSPoint(x: 250*s, y: 740*s))
    slope.curve(to: NSPoint(x: 780*s, y: 310*s), controlPoint1: NSPoint(x: 330*s, y: 390*s), controlPoint2: NSPoint(x: 500*s, y: 310*s))
    slope.lineWidth = 62*s; slope.lineCapStyle = .round
    NSColor(white: 1, alpha: 0.92).setStroke(); slope.stroke()
    NSColor(red: 1, green: 0.74, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 394*s, y: 436*s, width: 170*s, height: 170*s)).fill()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
