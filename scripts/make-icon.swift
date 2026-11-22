import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let dimension = CGFloat(pixels)
        let inset = dimension * 0.08
        NSColor(calibratedRed: 0.08, green: 0.46, blue: 0.46, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: dimension - 2 * inset,
                                      height: dimension - 2 * inset),
                     xRadius: dimension * 0.19, yRadius: dimension * 0.19).fill()
        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: dimension * 0.24, y: dimension * 0.22,
                                             width: dimension * 0.52, height: dimension * 0.52))
        ring.lineWidth = dimension * 0.045
        ring.stroke()
        let hands = NSBezierPath()
        hands.lineWidth = dimension * 0.045
        hands.lineCapStyle = .round
        hands.move(to: NSPoint(x: dimension * 0.5, y: dimension * 0.64))
        hands.line(to: NSPoint(x: dimension * 0.5, y: dimension * 0.48))
        hands.line(to: NSPoint(x: dimension * 0.61, y: dimension * 0.41))
        hands.stroke()
        let crown = NSBezierPath()
        crown.lineWidth = dimension * 0.045
        crown.lineCapStyle = .round
        crown.move(to: NSPoint(x: dimension * 0.44, y: dimension * 0.81))
        crown.line(to: NSPoint(x: dimension * 0.56, y: dimension * 0.81))
        crown.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let png = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
