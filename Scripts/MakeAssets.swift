import AppKit
import LadderCore

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let examples = root.appendingPathComponent("Examples")
try FileManager.default.createDirectory(at: examples, withIntermediateDirectories: true)
try ExampleCircuits.sealIn.encoded().write(to: examples.appendingPathComponent("Motor-seal-in.ladder"))
try ExampleCircuits.setReset.encoded().write(to: examples.appendingPathComponent("Set-reset-memory.ladder"))
try ExampleCircuits.trafficLight.encoded().write(to: examples.appendingPathComponent("Exercise-10-Traffic-Light.ladder"))
let iconSet = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = NSBezierPath(roundedRect: NSRect(x: 90, y: 90, width: 844, height: 844), xRadius: 180, yRadius: 180)
        NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.21, alpha: 1).setFill(); background.fill()
        let accent = NSColor(calibratedRed: 0.30, green: 0.88, blue: 0.72, alpha: 1)
        func line(_ points: [NSPoint], color: NSColor, width: CGFloat = 25) {
            let path = NSBezierPath(); path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.move(to: points[0]); for p in points.dropFirst() { path.line(to: p) }; color.setStroke(); path.stroke()
        }
        for x: CGFloat in [245, 779] { line([.init(x: x, y: 280), .init(x: x, y: 744)], color: accent) }
        let white = NSColor(calibratedWhite: 0.97, alpha: 1)
        for y: CGFloat in [620, 400] {
            line([.init(x: 245, y: y), .init(x: 417, y: y)], color: white)
            line([.init(x: 497, y: y), .init(x: 599, y: y)], color: white)
            line([.init(x: 692, y: y), .init(x: 779, y: y)], color: white)
            for x: CGFloat in [417, 497] { line([.init(x: x, y: y-47), .init(x: x, y: y+47)], color: white) }
            let coil = NSBezierPath(); coil.lineWidth = 22; coil.lineCapStyle = .round
            coil.move(to: .init(x: 622, y: y-47)); coil.curve(to: .init(x: 622, y: y+47), controlPoint1: .init(x: 589, y: y-28), controlPoint2: .init(x: 589, y: y+28))
            coil.move(to: .init(x: 669, y: y-47)); coil.curve(to: .init(x: 669, y: y+47), controlPoint1: .init(x: 702, y: y-28), controlPoint2: .init(x: 702, y: y+28))
            white.setStroke(); coil.stroke()
        }
        line([.init(x: 341, y: 620), .init(x: 341, y: 510), .init(x: 548, y: 510), .init(x: 548, y: 620)], color: accent, width: 20)
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconSet.appendingPathComponent(name))
    }
}
