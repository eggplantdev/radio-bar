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
symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
