import Cocoa
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(red: 0.93, green: 0.45, blue: 0.20, alpha: 1), ending: NSColor(red: 0.90, green: 0.30, blue: 0.27, alpha: 1))!.draw(in: path, angle: -90)
let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .medium).applying(.init(paletteColors: [.white]))
let symbol = NSImage(systemSymbolName: "radio", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
let s = symbol.size
// The symbol's frame carries uneven padding around the glyph, so centre what it actually paints.
let glyph = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s.width), pixelsHigh: Int(s.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: glyph)
symbol.draw(in: NSRect(origin: .zero, size: s))
NSGraphicsContext.restoreGraphicsState()
var (minX, minY, maxX, maxY) = (Int.max, Int.max, Int.min, Int.min)
for y in 0..<glyph.pixelsHigh { for x in 0..<glyph.pixelsWide where glyph.colorAt(x: x, y: y)!.alphaComponent > 0.1 {
    (minX, maxX, minY, maxY) = (min(minX, x), max(maxX, x), min(minY, y), max(maxY, y))
} }
let inkMidX = CGFloat(minX + maxX + 1) / 2
let inkMidY = s.height - CGFloat(minY + maxY + 1) / 2
// The antenna lifts the ink box above the radio's body, which is what the eye centres; this splits the difference.
let opticalLift: CGFloat = 36
symbol.draw(in: NSRect(x: size / 2 - inkMidX, y: size / 2 - inkMidY + opticalLift, width: s.width, height: s.height))
print("glyph ink \(minX)...\(maxX) x \(minY)...\(maxY) of \(s)")
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
